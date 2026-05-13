import '../domain/plan_catalog.dart';
import '../domain/subscription_snapshot.dart';
import '../domain/subscription_status.dart';
import '../domain/usage_metrics.dart';
import '../services/usage_quota_engine.dart';
import 'subscription_dao.dart';

class SubscriptionRepository {
  SubscriptionRepository(this._dao, this._quotaEngine);

  final SubscriptionDao _dao;
  final UsageQuotaEngine _quotaEngine;

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
}
