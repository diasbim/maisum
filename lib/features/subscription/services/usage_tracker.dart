import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../data/subscription_dao.dart';
import '../domain/plan_catalog.dart';
import '../domain/subscription_state.dart';
import '../domain/usage_balance.dart';
import '../domain/usage_event.dart';
import '../domain/usage_metrics.dart';
import 'remote_config_reader.dart';

class UsageRecordResult {
  const UsageRecordResult({
    required this.event,
    required this.used,
    this.limit,
    this.overLimit = false,
  });

  final UsageEvent event;
  final int used;
  final int? limit;
  final bool overLimit;
}

class UsageTracker {
  UsageTracker(
    this._database,
    this._subscriptionDao,
    this._syncDao, {
    required this.merchantId,
    RemoteConfigReader? remoteConfigReader,
  }) : _remoteConfigReader = remoteConfigReader;

  final AppDatabase _database;
  final SubscriptionDao _subscriptionDao;
  final SyncDao _syncDao;
  final String? merchantId;
  final RemoteConfigReader? _remoteConfigReader;

  static const _uuid = Uuid();

  Future<UsageRecordResult> record({
    required String metricKey,
    int quantity = 1,
    String? source,
    Map<String, dynamic>? metadata,
    DateTime? occurredAt,
  }) async {
    final resolvedMerchantId = merchantId ?? _syncDao.merchantId;
    if (resolvedMerchantId == null) {
      throw StateError('No merchant id available for usage tracking');
    }

    final now = occurredAt ?? DateTime.now();
    final window = UsageWindow.monthly(now);
    final entitlement = await _subscriptionDao.getEntitlement(metricKey);
    final state = await _subscriptionDao.getSubscriptionState();
    final planLimit = _resolvePlanLimit(metricKey, state);
    final override = await _remoteConfigReader?.getQuotaOverride(metricKey);
    final limitValue = override?.limit ?? entitlement?.limitValue ?? planLimit;

    final event = UsageEvent(
      id: _uuid.v4(),
      merchantId: resolvedMerchantId,
      metricKey: metricKey,
      quantity: quantity,
      occurredAt: now,
      source: source,
      metadata: metadata,
    );

    var updatedUsed = quantity;
    await _database.database.then((db) async {
      await db.transaction((txn) async {
        await txn.insert('usage_events', event.toDbMap());

        final existing = await txn.query(
          'usage_balances',
          where:
              'merchant_id = ? AND metric_key = ? AND window_start = ? AND window_end = ?',
          whereArgs: [
            resolvedMerchantId,
            metricKey,
            window.start.millisecondsSinceEpoch,
            window.end.millisecondsSinceEpoch,
          ],
          limit: 1,
        );

        updatedUsed =
            (existing.isEmpty ? 0 : existing.first['used'] as int? ?? 0) +
                quantity;

        final existingLimit =
            existing.isEmpty ? null : existing.first['limit_value'] as int?;
        final balance = UsageBalance(
          id: existing.isEmpty
              ? '${resolvedMerchantId}_${metricKey}_${window.start.millisecondsSinceEpoch}'
              : existing.first['id'] as String,
          merchantId: resolvedMerchantId,
          metricKey: metricKey,
          windowStart: window.start,
          windowEnd: window.end,
          used: updatedUsed,
          limitValue: limitValue ?? existingLimit,
          softLimit: override?.softLimit ?? true,
          updatedAt: DateTime.now(),
        );

        await txn.insert(
          'usage_balances',
          balance.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    });

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'usage_event',
        entityId: event.id,
        payload: jsonEncode(event.toSyncPayload()),
        createdAt: now,
      ),
    );

    final overLimit = limitValue != null && updatedUsed > limitValue;
    return UsageRecordResult(
      event: event,
      used: updatedUsed,
      limit: limitValue,
      overLimit: overLimit,
    );
  }

  int? _resolvePlanLimit(String metricKey, SubscriptionState? state) {
    final plan = PlanCatalog.fromCode(state?.planCode);
    if (metricKey == UsageMetrics.whatsappMessages) {
      return plan.whatsappMonthlyLimit;
    }
    return null;
  }
}

class UsageWindow {
  const UsageWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;

  factory UsageWindow.monthly(DateTime now) {
    final start = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final end = nextMonth.subtract(const Duration(milliseconds: 1));
    return UsageWindow(start, end);
  }
}
