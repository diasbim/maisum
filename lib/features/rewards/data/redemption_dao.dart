import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/redemption.dart';

class PendingRedemptionRequest {
  const PendingRedemptionRequest({
    required this.id,
    required this.pointsRequired,
  });

  final String id;
  final int pointsRequired;
}

class RedemptionDao {
  RedemptionDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<Redemption> create({
    required String customerId,
    required String rewardId,
    required int pointsSpent,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final redemption = Redemption(
      id: _uuid.v4(),
      customerId: customerId,
      rewardId: rewardId,
      pointsSpent: pointsSpent,
      redeemedAt: now,
    );
    await db.insert('redemptions', {
      ...redemption.toDbMap(),
      'merchant_id': merchantId,
    });
    return redemption;
  }

  Future<List<Redemption>> getByCustomer(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'redemptions',
      where: merchantId == null
          ? 'customer_id = ?'
          : 'merchant_id = ? AND customer_id = ?',
      whereArgs: merchantId == null ? [customerId] : [merchantId, customerId],
      orderBy: 'redeemed_at DESC',
    );
    return rows.map(redemptionFromMap).toList();
  }

  Future<List<Redemption>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query(
      'redemptions',
      where:
          merchantId == null ? 'synced = 0' : 'merchant_id = ? AND synced = 0',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'redeemed_at ASC',
    );
    return rows.map(redemptionFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'redemptions',
      {'synced': 1},
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<PendingRedemptionRequest> getOrCreatePendingRequest({
    required String customerId,
    required String rewardId,
    required int pointsRequired,
  }) async {
    final scopedMerchantId = merchantId;
    if (scopedMerchantId == null || scopedMerchantId.isEmpty) {
      throw StateError('Redemption requires an active merchant');
    }
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'redemption_requests',
        where: 'merchant_id = ? AND customer_id = ? AND reward_id = ? '
            "AND status = 'PENDING'",
        whereArgs: <Object?>[scopedMerchantId, customerId, rewardId],
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return PendingRedemptionRequest(
          id: existing.single['id'] as String,
          pointsRequired: (existing.single['points_required'] as num).toInt(),
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final id = _uuid.v4();
      await txn.insert('redemption_requests', <String, Object?>{
        'id': id,
        'merchant_id': scopedMerchantId,
        'customer_id': customerId,
        'reward_id': rewardId,
        'points_required': pointsRequired,
        'status': 'PENDING',
        'created_at': now,
        'updated_at': now,
      });
      return PendingRedemptionRequest(
        id: id,
        pointsRequired: pointsRequired,
      );
    });
  }

  Future<void> recordRequestFailure(String requestId, Object error) async {
    final db = await _db.database;
    await db.update(
      'redemption_requests',
      <String, Object?>{
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'last_error': error.toString(),
      },
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null
          ? <Object?>[requestId]
          : <Object?>[merchantId, requestId],
    );
  }

  Future<void> applyConfirmedRedemption({
    required String requestId,
    required Redemption redemption,
    required int confirmedPoints,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(
        'redemptions',
        <String, Object?>{
          ...redemption.toDbMap(),
          'merchant_id': merchantId,
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final updated = await txn.update(
        'customers',
        <String, Object?>{
          'total_points': confirmedPoints,
          'confirmed_points': confirmedPoints,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
        whereArgs: merchantId == null
            ? <Object?>[redemption.customerId]
            : <Object?>[merchantId, redemption.customerId],
      );
      if (updated != 1) {
        throw StateError('Confirmed redemption customer was not found');
      }
      await txn.delete(
        'redemption_requests',
        where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
        whereArgs: merchantId == null
            ? <Object?>[requestId]
            : <Object?>[merchantId, requestId],
      );
    });
  }
}
