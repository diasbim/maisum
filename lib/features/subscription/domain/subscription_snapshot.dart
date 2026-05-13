import 'entitlement.dart';
import 'feature_flag.dart';
import 'plan.dart';
import 'subscription_state.dart';
import 'subscription_status.dart';
import 'usage_balance.dart';
import 'usage_quota.dart';

class SubscriptionSnapshot {
  const SubscriptionSnapshot({
    required this.plan,
    required this.status,
    required this.entitlements,
    required this.flags,
    required this.usageBalances,
    required this.whatsappQuota,
    this.state,
  });

  final SubscriptionState? state;
  final Plan plan;
  final SubscriptionStatus status;
  final List<Entitlement> entitlements;
  final List<FeatureFlag> flags;
  final List<UsageBalance> usageBalances;
  final UsageQuotaSummary whatsappQuota;
}
