import '../data/subscription_dao.dart';
import '../domain/plan_catalog.dart';
import '../domain/usage_metrics.dart';
import '../domain/usage_quota.dart';
import 'remote_config_reader.dart';

class UsageQuotaEngine {
  UsageQuotaEngine(this._dao, {RemoteConfigReader? remoteConfigReader})
      : _remoteConfigReader = remoteConfigReader;

  final SubscriptionDao _dao;
  final RemoteConfigReader? _remoteConfigReader;

  Future<UsageQuotaSummary> getQuota({
    required String metricKey,
    DateTime? now,
  }) async {
    final resolvedNow = now ?? DateTime.now();
    final window = _monthlyWindow(resolvedNow);
    final balance = await _dao.getUsageBalance(
      metricKey: metricKey,
      windowStart: window.start,
      windowEnd: window.end,
    );

    final state = await _dao.getSubscriptionState();
    final planDefinition = PlanCatalog.fromCode(state?.planCode);
    final defaultLimit = _defaultLimit(metricKey, planDefinition);
    final override = await _remoteConfigReader?.getQuotaOverride(metricKey);

    final used = balance?.used ?? 0;
    final limit = override?.limit ?? balance?.limitValue ?? defaultLimit;
    final softLimit = override?.softLimit ?? balance?.softLimit ?? true;

    return UsageQuotaSummary(
      metricKey: metricKey,
      used: used,
      limit: limit,
      resetAt: window.end,
      softLimit: softLimit,
    );
  }

  int? _defaultLimit(String metricKey, PlanDefinition plan) {
    if (metricKey == UsageMetrics.whatsappMessages) {
      return plan.whatsappMonthlyLimit;
    }
    return null;
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
