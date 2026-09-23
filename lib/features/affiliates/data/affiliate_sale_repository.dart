import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../catalog/domain/merchant_item.dart';
import '../../customers/domain/customer.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_item.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/referral_sale_commit.dart';
import 'affiliate_sale_api.dart';

/// A referred sale, committed on the server and then projected locally.
///
/// This is the one sale path that is online-first, and deliberately so. A
/// referral moves an affiliate's reward and a code's usage count, and those
/// cannot be decided on a phone that has not spoken to the server — two tills
/// would each believe they were the first to use a limited code. So the server
/// writes the sale, the discount, the points, the acquisition and the reward in
/// one transaction, and this repository stores the answer.
///
/// Which is why nothing here computes anything. The sale row it writes is the
/// canonical one, marked `synced` because the server already has it; putting it
/// on the queue would ask the authoritative record to accept a copy of itself.
/// The only thing queued is the customer's own totals, which is the same row the
/// ordinary sale path sends.
///
/// `SaleRepository.createSale` is untouched and still handles every sale with no
/// code: same transaction, same queue, same offline behaviour. A sale without a
/// referral never reaches this file.
class AffiliateSaleRepository {
  AffiliateSaleRepository(
    this._database,
    this._api, {
    required this.merchantId,
    required this.deviceId,
    this.appUserId,
  }) {
    if (merchantId.trim().isEmpty) {
      throw ArgumentError.value(merchantId, 'merchantId', 'must not be empty');
    }
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
    }
  }

  final AppDatabase _database;
  final AffiliateSaleGateway _api;
  final String merchantId;
  final String deviceId;
  final String? appUserId;
  static const _uuid = Uuid();

  /// Confirms a sale with a referral code.
  ///
  /// [localSaleId] is the till's own id for the sale and, with the device, the
  /// idempotency key: calling this again with the same pair after a dropped
  /// response resolves to the sale already committed. A refusal comes back as a
  /// result rather than an exception, so the caller can confirm the sale without
  /// a code instead of losing it.
  Future<ReferralSaleCommit> commitReferredSale({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) async {
    final itemIds = <String>[
      for (var index = 0; index < items.length; index++)
        referralSaleItemId(
          deviceId,
          localSaleId,
          index,
        ),
    ];

    final commit = await _api.commitSale(
      deviceId: deviceId,
      localSaleId: localSaleId,
      customerId: customerId,
      customerPhone: customerPhone,
      grossAmount: grossAmount,
      code: code,
      items: items,
      itemIds: itemIds,
    );

    final sale = commit.sale;
    if (!commit.isAccepted || sale == null) return commit;

    await _projectCommittedSale(commit, sale, items, itemIds);
    return commit;
  }

  /// Writes the server's answer into SQLite, once.
  ///
  /// Everything is keyed by the canonical sale id and replaces what is there, so
  /// a replay of the same commit converges instead of doubling. The customer's
  /// points are only moved when the sale is new to this device, because the
  /// points were already added the first time it was stored.
  Future<void> _projectCommittedSale(
    ReferralSaleCommit commit,
    Sale sale,
    List<SaleItemInput> items,
    List<String> itemIds,
  ) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'sales',
        columns: const ['id'],
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [sale.id, merchantId],
        limit: 1,
      );
      final isNewLocally = existing.isEmpty;

      await txn.insert(
        'sales',
        <String, dynamic>{
          ...sale.toDbMap(),
          'merchant_id': merchantId,
          'device_id': deviceId,
          'created_by_app_user_id': appUserId,
          'updated_by_app_user_id': appUserId,
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        await txn.insert(
          'sale_items',
          <String, dynamic>{
            'id': itemIds[index],
            'merchant_id': merchantId,
            'sale_id': sale.id,
            'merchant_item_id': item.merchantItemId,
            'name_snapshot': item.nameSnapshot,
            'type_snapshot': item.typeSnapshot.dbValue,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'subtotal': item.subtotal,
            'created_at': sale.createdAt.millisecondsSinceEpoch,
            'updated_at': sale.createdAt.millisecondsSinceEpoch,
            'created_by_app_user_id': appUserId,
            'updated_by_app_user_id': appUserId,
            'synced': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (!isNewLocally) return;

      final customerRows = await txn.query(
        'customers',
        where: 'id = ? AND merchant_id = ? AND archived_at IS NULL',
        whereArgs: [sale.customerId, merchantId],
        limit: 1,
      );
      if (customerRows.isEmpty) return;

      final now = DateTime.now();
      final customer = customerFromMap(customerRows.first);
      // The promotional points of a POINTS benefit are not added here: they are
      // a server-owned ledger entry, and the confirmed balance arrives with the
      // next pull rather than being guessed twice.
      final updatedCustomer = customer.copyWith(
        totalPoints: customer.totalPoints + sale.points,
        updatedAt: now,
        synced: false,
      );
      await txn.update(
        'customers',
        {...updatedCustomer.toDbMap(), 'merchant_id': merchantId},
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [sale.customerId, merchantId],
      );

      final queueId = _uuid.v4();
      await txn.insert('sync_queue', <String, dynamic>{
        ...SyncItem(
          id: queueId,
          operation: 'update',
          entityType: 'customer',
          entityId: sale.customerId,
          payload: jsonEncode({
            ...updatedCustomer.toClientSyncMap(),
            'merchant_id': merchantId,
          }),
          createdAt: now,
        ).toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
        'local_id': sale.customerId,
        'idempotency_key': queueId,
      });
    });
  }
}
