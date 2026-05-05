import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../domain/reward.dart';

class RewardDao {
  RewardDao(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<Reward>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'rewards',
      where: 'active = 1',
      orderBy: 'points_required ASC',
    );
    return rows.map(rewardFromMap).toList();
  }

  Future<Reward?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'rewards',
      where: 'id = ?',
      whereArgs: [id],
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
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [reward.id],
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
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'rewards',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Reward>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query('rewards', where: 'synced = 0');
    return rows.map(rewardFromMap).toList();
  }
}
