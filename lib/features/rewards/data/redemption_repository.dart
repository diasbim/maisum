import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../customers/data/customer_dao.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/redemption.dart';
import 'redemption_dao.dart';

class RedemptionRepository {
  RedemptionRepository(this._redemptionDao, this._customerDao, this._syncDao);

  final RedemptionDao _redemptionDao;
  final CustomerDao _customerDao;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<Redemption> redeemReward({
    required String customerId,
    required String rewardId,
    required int pointsRequired,
  }) async {
    final customer = await _customerDao.getById(customerId);
    if (customer == null) throw const UnknownException('Cliente não encontrado');
    if (customer.totalPoints < pointsRequired) {
      throw const UnknownException(
          'Pontos insuficientes para resgatar esta recompensa');
    }

    final redemption = await _redemptionDao.create(
      customerId: customerId,
      rewardId: rewardId,
      pointsSpent: pointsRequired,
    );

    final newTotal = customer.totalPoints - pointsRequired;
    await _customerDao.updatePoints(customerId, newTotal);

    await _syncDao.enqueue(SyncItem(
      id: _uuid.v4(),
      operation: 'create',
      entityType: 'redemption',
      entityId: redemption.id,
      payload: jsonEncode(redemption.toDbMap()),
      createdAt: DateTime.now(),
    ));

    final updatedCustomer = customer.copyWith(
      totalPoints: newTotal,
      updatedAt: DateTime.now(),
    );
    await _syncDao.enqueue(SyncItem(
      id: _uuid.v4(),
      operation: 'update',
      entityType: 'customer',
      entityId: customerId,
      payload: jsonEncode(updatedCustomer.toDbMap()),
      createdAt: DateTime.now(),
    ));

    return redemption;
  }

  Future<List<Redemption>> getByCustomer(String customerId) =>
      _redemptionDao.getByCustomer(customerId);
}
