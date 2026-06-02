import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/entitlement.dart';
import '../domain/feature_keys.dart';
import '../domain/plan.dart';
import '../domain/plan_catalog.dart';
import '../domain/subscription_state.dart';
import '../domain/subscription_snapshot.dart';
import '../domain/subscription_status.dart';
import '../domain/usage_balance.dart';
import '../domain/usage_metrics.dart';
import '../services/usage_quota_engine.dart';
import 'subscription_dao.dart';

class SubscriptionRepository {
  SubscriptionRepository(this._dao, this._quotaEngine, this._syncDao);

  final SubscriptionDao _dao;
  final UsageQuotaEngine _quotaEngine;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<SubscriptionSnapshot> getSnapshot() async {
    final state = await _dao.getSubscriptionState();
    final plan = PlanCatalog.fromCode(state?.planCode).plan;
    final status = SubscriptionStatus.fromWire(state?.status);

    final entitlements = await _dao.getEntitlements();
    final flags = await _dao.getFeatureFlags();
    final balances = await _dao.getUsageBalances();
    final whatsappQuota = await _quotaEngine.getQuota(
      metricKey: UsageMetrics.whatsappMessages,
    );

    return SubscriptionSnapshot(
      state: state,
      plan: plan,
      status: status,
      entitlements: entitlements,
      flags: flags,
      usageBalances: balances,
      whatsappQuota: whatsappQuota,
    );
  }

  Future<void> switchPlan({
    required String merchantId,
    required Plan plan,
    String? status,
  }) async {
    final now = DateTime.now();
    final currentState = await _dao.getSubscriptionState();
    final planDefinition = PlanCatalog.forPlan(plan);
    final resolvedStatus = (status != null && status.trim().isNotEmpty)
        ? status.trim().toUpperCase()
        : (currentState?.status.trim().isNotEmpty ?? false)
            ? currentState!.status
            : 'TRIAL';

    final nextState = SubscriptionState(
      merchantId: merchantId,
      planCode: plan.code,
      planName: planDefinition.displayName,
      status: resolvedStatus,
      planVersion: currentState?.planVersion ?? 1,
      pricingVersion: currentState?.pricingVersion ?? 1,
      trialEndsAt: currentState?.trialEndsAt,
      graceEndsAt: currentState?.graceEndsAt,
      periodStart: currentState?.periodStart,
      periodEnd: currentState?.periodEnd,
      updatedAt: now,
    );

    await _dao.upsertSubscriptionState(nextState);
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'subscription_state',
        entityId: merchantId,
        payload: jsonEncode(nextState.toDbMap()),
        createdAt: now,
      ),
    );

    for (final featureKey in FeatureKeys.all) {
      final entitlement = Entitlement(
        id: '${merchantId}_$featureKey',
        merchantId: merchantId,
        featureKey: featureKey,
        isEnabled: planDefinition.allowsFeature(featureKey),
        updatedAt: now,
      );
      await _dao.upsertEntitlement(entitlement);
      await _syncDao.enqueue(
        SyncItem(
          id: _uuid.v4(),
          operation: 'update',
          entityType: 'entitlement',
          entityId: entitlement.id,
          payload: jsonEncode(entitlement.toDbMap()),
          createdAt: now,
        ),
      );
    }

    final window = _monthlyWindow(now);
    final existingBalance = await _dao.getUsageBalance(
      metricKey: UsageMetrics.whatsappMessages,
      windowStart: window.start,
      windowEnd: window.end,
    );
    final usageBalance = UsageBalance(
      id: '${merchantId}_${UsageMetrics.whatsappMessages}_${window.start.millisecondsSinceEpoch}',
      merchantId: merchantId,
      metricKey: UsageMetrics.whatsappMessages,
      windowStart: window.start,
      windowEnd: window.end,
      used: existingBalance?.used ?? 0,
      limitValue: planDefinition.whatsappMonthlyLimit,
      softLimit: existingBalance?.softLimit ?? true,
      updatedAt: now,
    );
    await _dao.upsertUsageBalance(usageBalance);
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'usage_balance',
        entityId: usageBalance.id,
        payload: jsonEncode(usageBalance.toDbMap()),
        createdAt: now,
      ),
    );
  }

  _UsageWindow _monthlyWindow(DateTime now) {
    final start = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final end = nextMonth.subtract(const Duration(milliseconds: 1));
    return _UsageWindow(start, end);
  }
}

class _UsageWindow {
  const _UsageWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;
}
