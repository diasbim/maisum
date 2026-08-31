import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/utils/points_calculator.dart';
import '../../../core/database/app_database.dart';
import '../../customers/domain/customer.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';
import 'sale_dao.dart';
import 'sale_item_dao.dart';
import '../../sync/domain/sync_item.dart';

class SaleRepository {
  SaleRepository(
    AppDatabase database,
    this._saleDao, {
    this.merchantId,
    this.deviceId,
    this.appUserId,
    SaleItemDao? saleItemDao,
    int pointsPerMzn = 100,
  })  : _database = database,
        _points = PointsCalculator(pointsPerMzn: pointsPerMzn),
        _saleItemDao =
            saleItemDao ?? SaleItemDao(database, merchantId: merchantId);

  final AppDatabase _database;

  final SaleDao _saleDao;
  final SaleItemDao _saleItemDao;
  final String? merchantId;
  final String? deviceId;
  final String? appUserId;
  static const _uuid = Uuid();
  final PointsCalculator _points;

  Future<Sale> createSale({
    required String customerId,
    required double amount,
    List<SaleItemInput> items = const <SaleItemInput>[],
    String? replacesSaleId,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final points = _points.calculate(amount);
      final sale = Sale(
        id: _uuid.v4(),
        customerId: customerId,
        amount: amount,
        points: points,
        createdAt: now,
      );

      await txn.insert('sales', _saleRow(sale));
      var saleWithItems = sale;

      final customerRows = await txn.query(
        'customers',
        where: merchantId == null
            ? 'id = ? AND archived_at IS NULL'
            : 'id = ? AND merchant_id = ? AND archived_at IS NULL',
        whereArgs: merchantId == null ? [customerId] : [customerId, merchantId],
        limit: 1,
      );

      if (customerRows.isEmpty) {
        throw StateError('Active customer not found for sale');
      }
      final customer = customerFromMap(customerRows.first);
      final newTotal = customer.totalPoints + sale.points;
      final updatedCustomer = customer.copyWith(
        totalPoints: newTotal,
        updatedAt: now,
        synced: false,
      );

      await txn.update(
        'customers',
        {...updatedCustomer.toDbMap(), 'merchant_id': merchantId},
        where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
        whereArgs: merchantId == null ? [customerId] : [customerId, merchantId],
      );

      await txn.insert(
        'sync_queue',
        _syncQueueRow(
          SyncItem(
            id: _uuid.v4(),
            operation: 'update',
            entityType: 'customer',
            entityId: customerId,
            payload: jsonEncode({
              ...updatedCustomer.toClientSyncMap(),
              'merchant_id': merchantId,
            }),
            createdAt: now,
          ),
        ),
      );

      await txn.insert(
        'sync_queue',
        _syncQueueRow(
          SyncItem(
            id: _uuid.v4(),
            operation: 'create',
            entityType: 'sale',
            entityId: sale.id,
            payload: jsonEncode(_saleSyncRow(sale)),
            createdAt: now,
          ),
        ),
      );

      if (items.isNotEmpty) {
        final saleItems = await _saleItemDao.insertItems(
          txn,
          saleId: sale.id,
          items: items,
          now: now,
          appUserId: appUserId,
        );
        saleWithItems = sale.copyWith(items: saleItems);
        for (final saleItem in saleItems) {
          await txn.insert(
            'sync_queue',
            _syncQueueRow(
              SyncItem(
                id: _uuid.v4(),
                operation: 'create',
                entityType: 'sale_item',
                entityId: saleItem.id,
                payload: jsonEncode(
                  _saleItemDao.rowForSync(saleItem, appUserId: appUserId),
                ),
                createdAt: now.add(const Duration(milliseconds: 1)),
              ),
            ),
          );
        }
      }

      if (replacesSaleId != null && replacesSaleId.isNotEmpty) {
        final replacedRows = await txn.query(
          'sales',
          where: merchantId == null
              ? "id = ? AND cancellation_status = 'CANCELLED'"
              : "id = ? AND merchant_id = ? "
                  "AND cancellation_status = 'CANCELLED'",
          whereArgs: merchantId == null
              ? [replacesSaleId]
              : [replacesSaleId, merchantId],
          limit: 1,
        );
        if (replacedRows.length != 1) {
          throw StateError('Cancelled sale to replace was not found');
        }
        final replaced = saleFromMap(replacedRows.first).copyWith(
          replacementSaleId: sale.id,
          updatedAt: now,
          synced: false,
        );
        await txn.update(
          'sales',
          {
            'replacement_sale_id': sale.id,
            'updated_at': now.millisecondsSinceEpoch,
            'updated_by_app_user_id': appUserId,
            'synced': 0,
          },
          where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
          whereArgs: merchantId == null
              ? [replacesSaleId]
              : [replacesSaleId, merchantId],
        );
        await txn.insert(
          'sync_queue',
          _syncQueueRow(
            SyncItem(
              id: _uuid.v4(),
              operation: 'cancel',
              entityType: 'sale',
              entityId: replaced.id,
              payload: jsonEncode(
                _saleSyncRow(replaced, includeCancellation: true),
              ),
              createdAt: now.add(const Duration(milliseconds: 2)),
            ),
          ),
        );
      }

      return saleWithItems;
    });
  }

  Future<List<Sale>> getByCustomer(String customerId) =>
      _saleDao.getByCustomer(customerId);

  Future<Sale> cancelSale({
    required String saleId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('O motivo da anulação é obrigatório.');
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
        whereArgs: merchantId == null ? [saleId] : [saleId, merchantId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Venda não encontrada.');
      }
      final existing = saleFromMap(rows.first);
      if (existing.isCancelled) return existing;

      final now = DateTime.now();
      final cancelled = existing.copyWith(
        cancellationStatus: SaleCancellationStatus.cancelled,
        cancelledAt: now,
        cancelledByAppUserId: appUserId,
        cancellationReason: trimmedReason,
        updatedAt: now,
        synced: false,
      );
      final updated = await txn.update(
        'sales',
        {
          'cancellation_status': cancelled.cancellationStatus.storageValue,
          'cancelled_at': now.millisecondsSinceEpoch,
          'cancelled_by_app_user_id': appUserId,
          'cancellation_reason': trimmedReason,
          'updated_at': now.millisecondsSinceEpoch,
          'updated_by_app_user_id': appUserId,
          'synced': 0,
        },
        where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
        whereArgs: merchantId == null ? [saleId] : [saleId, merchantId],
      );
      if (updated != 1) {
        throw StateError('A venda não pôde ser anulada.');
      }

      final customerRows = await txn.query(
        'customers',
        columns: const ['total_points', 'confirmed_points'],
        where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
        whereArgs: merchantId == null
            ? [existing.customerId]
            : [existing.customerId, merchantId],
        limit: 1,
      );
      if (customerRows.isNotEmpty) {
        final customer = customerRows.first;
        final totalPoints = ((customer['total_points'] as num?)?.toInt() ?? 0) -
            existing.points;
        final confirmedPoints = (customer['confirmed_points'] as num?)?.toInt();
        await txn.update(
          'customers',
          {
            'total_points': totalPoints < 0 ? 0 : totalPoints,
            if (confirmedPoints != null &&
                existing.confirmationStatus ==
                    SaleConfirmationStatus.confirmed &&
                existing.confirmedPoints != null)
              'confirmed_points':
                  (confirmedPoints - existing.confirmedPoints!) < 0
                      ? 0
                      : confirmedPoints - existing.confirmedPoints!,
          },
          where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
          whereArgs: merchantId == null
              ? [existing.customerId]
              : [existing.customerId, merchantId],
        );
      }

      await txn.insert(
        'sync_queue',
        _syncQueueRow(
          SyncItem(
            id: _uuid.v4(),
            operation: 'cancel',
            entityType: 'sale',
            entityId: saleId,
            payload: jsonEncode(
              _saleSyncRow(cancelled, includeCancellation: true),
            ),
            createdAt: now,
          ),
        ),
      );
      return cancelled;
    });
  }

  Future<Map<String, dynamic>> getTodayStats() => _saleDao.getTodayStats();

  Map<String, dynamic> _saleRow(Sale sale) => {
        ...sale.toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
        'created_by_app_user_id': appUserId,
        'updated_by_app_user_id': appUserId,
        'cancellation_status': sale.cancellationStatus.storageValue,
        'cancelled_at': sale.cancelledAt?.millisecondsSinceEpoch,
        'cancelled_by_app_user_id': sale.cancelledByAppUserId,
        'cancellation_reason': sale.cancellationReason,
        'replacement_sale_id': sale.replacementSaleId,
      };

  Map<String, dynamic> _saleSyncRow(
    Sale sale, {
    bool includeCancellation = false,
  }) =>
      {
        ...sale.toClientSyncMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
        'created_by_app_user_id': appUserId,
        'updated_by_app_user_id': appUserId,
        if (includeCancellation) ...{
          'cancellation_status': sale.cancellationStatus.storageValue,
          'cancelled_at': sale.cancelledAt?.millisecondsSinceEpoch,
          'cancelled_by_app_user_id': sale.cancelledByAppUserId,
          'cancellation_reason': sale.cancellationReason,
          'replacement_sale_id': sale.replacementSaleId,
        },
      };

  Map<String, dynamic> _syncQueueRow(SyncItem item) => {
        ...item.toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
      };
}
