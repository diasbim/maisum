import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/reward.dart';

class RewardDao {
  RewardDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<List<Reward>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'rewards',
      where: merchantId == null
          ? 'active = 1'
          : 'merchant_id = ? AND active = 1',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'points_required ASC',
    );
    return rows.map(rewardFromMap).toList();
  }

  Future<Reward?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'rewards',
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rewardFromMap(rows.first);
  }

  Future<Reward> create({
    required String name,
    required int pointsRequired,
    String? description,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final reward = Reward(
      id: _uuid.v4(),
      name: name,
      pointsRequired: pointsRequired,
      description: description,
      createdAt: now,
    );
    await db.insert('rewards', {
      ...reward.toDbMap(),
      'merchant_id': merchantId,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return reward;
  }

  Future<void> update(Reward reward) async {
    final db = await _db.database;
    await db.update(
      'rewards',
      {
        ...reward.toDbMap(),
        'merchant_id': merchantId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [reward.id] : [merchantId, reward.id],
    );
  }

  Future<void> deactivate(String id) async {
    final db = await _db.database;
    await db.update(
      'rewards',
      {
        'active': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'rewards',
      {'synced': 1},
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<List<Reward>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query(
      'rewards',
      where: merchantId == null
          ? 'synced = 0'
          : 'merchant_id = ? AND synced = 0',
      whereArgs: merchantId == null ? null : [merchantId],
    );
    return rows.map(rewardFromMap).toList();
  }
}
