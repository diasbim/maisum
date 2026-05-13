import 'plan.dart';
import 'subscription_status.dart';

class SubscriptionState {
  const SubscriptionState({
    required this.merchantId,
    required this.planCode,
    required this.planName,
    required this.status,
    required this.planVersion,
    required this.pricingVersion,
    required this.updatedAt,
    this.trialEndsAt,
    this.graceEndsAt,
    this.periodStart,
    this.periodEnd,
  });

  final String merchantId;
  final String planCode;
  final String planName;
  final String status;
  final int planVersion;
  final int pricingVersion;
  final DateTime? trialEndsAt;
  final DateTime? graceEndsAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime updatedAt;

  Plan get plan => Plan.fromCode(planCode);
  SubscriptionStatus get statusEnum => SubscriptionStatus.fromWire(status);
  String get resolvedPlanName =>
      planName.isNotEmpty ? planName : plan.displayName;

  Map<String, dynamic> toDbMap() => {
        'merchant_id': merchantId,
        'plan_code': planCode,
        'plan_name': planName,
        'plan_version': planVersion,
        'pricing_version': pricingVersion,
        'status': status,
        'trial_ends_at': trialEndsAt?.millisecondsSinceEpoch,
        'grace_ends_at': graceEndsAt?.millisecondsSinceEpoch,
        'period_start': periodStart?.millisecondsSinceEpoch,
        'period_end': periodEnd?.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

SubscriptionState subscriptionStateFromMap(Map<String, dynamic> map) {
  return SubscriptionState(
    merchantId: map['merchant_id'] as String,
    planCode: map['plan_code'] as String? ?? 'starter',
    planName: map['plan_name'] as String? ?? 'Starter',
    status: map['status'] as String? ?? 'TRIAL',
    planVersion: map['plan_version'] as int? ?? 1,
    pricingVersion: map['pricing_version'] as int? ?? 1,
    trialEndsAt: _dateFromInt(map['trial_ends_at']),
    graceEndsAt: _dateFromInt(map['grace_ends_at']),
    periodStart: _dateFromInt(map['period_start']),
    periodEnd: _dateFromInt(map['period_end']),
    updatedAt: _dateFromInt(map['updated_at']) ?? DateTime.now(),
  );
}

DateTime? _dateFromInt(Object? raw) {
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  return null;
}
