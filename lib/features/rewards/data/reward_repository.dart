import 'dart:convert';
import '../domain/reward.dart';
import 'reward_dao.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import 'package:uuid/uuid.dart';

class RewardRepository {
  RewardRepository(this._dao, this._syncDao);

  final RewardDao _dao;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<List<Reward>> getRewards() => _dao.getAll();

  Future<Reward?> getById(String id) => _dao.getById(id);

  Future<Reward> createReward({
    required String name,
    required int pointsRequired,
    String? description,
  }) async {
    final reward = await _dao.create(
      name: name,
      pointsRequired: pointsRequired,
      description: description,
    );
    await _syncDao.enqueue(SyncItem(
      id: _uuid.v4(),
      operation: 'create',
      entityType: 'reward',
      entityId: reward.id,
      payload: jsonEncode(reward.toDbMap()),
      createdAt: DateTime.now(),
    ));
    return reward;
  }

  Future<void> deactivate(String id) async {
    await _dao.deactivate(id);
    final reward = await _dao.getById(id);
    if (reward == null) return;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _syncDao.enqueue(SyncItem(
      id: _uuid.v4(),
      operation: 'update',
      entityType: 'reward',
      entityId: id,
      payload: jsonEncode({
        ...reward.toDbMap(),
        'updated_at': updatedAt,
      }),
      createdAt: DateTime.now(),
    ));
  }
}
