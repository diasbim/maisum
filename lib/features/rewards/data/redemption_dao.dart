import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/redemption.dart';

class RedemptionDao {
  RedemptionDao(this._db);

  final AppDatabase _db;
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
    await db.insert('redemptions', redemption.toDbMap());
    return redemption;
  }

  Future<List<Redemption>> getByCustomer(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'redemptions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'redeemed_at DESC',
    );
    return rows.map(redemptionFromMap).toList();
  }

  Future<List<Redemption>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query(
      'redemptions',
      where: 'synced = 0',
      orderBy: 'redeemed_at ASC',
    );
    return rows.map(redemptionFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'redemptions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
