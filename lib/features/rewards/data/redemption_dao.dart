import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/redemption.dart';

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
      where: merchantId == null
          ? 'synced = 0'
          : 'merchant_id = ? AND synced = 0',
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
}
