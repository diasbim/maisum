import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/retention_metric.dart';
import 'retention_dao.dart';

class RetentionRepository {
  RetentionRepository(this._dao, this._syncDao);

  final RetentionDao _dao;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<List<RecurringCustomerSummary>> getRecurringCustomers({
    int limit = 50,
  }) {
    return _dao.getRecurringCustomers(limit: limit);
  }

  Future<List<InactiveCustomerSummary>> getInactiveCustomers({
    int limit = 50,
  }) {
    return _dao.getInactiveCustomers(limit: limit);
  }

  Future<List<RetentionMetric>> calculateRetention({DateTime? now}) async {
    final metrics = await _dao.calculateRetention(now: now);
    for (final metric in metrics) {
      await _enqueueMetric(metric);
    }
    return metrics;
  }

  Future<RetentionMetric?> updateCustomerRisk({
    required String customerId,
    required String riskLevel,
  }) async {
    final metric = await _dao.updateCustomerRisk(
      customerId: customerId,
      riskLevel: riskLevel,
    );
    if (metric != null) {
      await _enqueueMetric(metric);
    }
    return metric;
  }

  Future<void> _enqueueMetric(RetentionMetric metric) async {
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'retention_metric',
        entityId: metric.id,
        payload: jsonEncode(
          {
            ...metric.toJson(),
            'merchant_id': _dao.merchantId,
          },
        ),
        createdAt: DateTime.now(),
      ),
    );
  }
}
