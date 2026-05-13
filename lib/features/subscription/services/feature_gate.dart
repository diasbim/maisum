import '../data/subscription_dao.dart';
import '../domain/feature_keys.dart';
import '../domain/plan_catalog.dart';
import '../domain/subscription_state.dart';
import '../domain/subscription_status.dart';
import 'usage_quota_engine.dart';

class GateDecision {
  const GateDecision({
    required this.allowed,
    required this.status,
    this.reason,
    this.used,
    this.limit,
    this.softLimited = false,
  });

  final bool allowed;
  final String status;
  final String? reason;
  final int? used;
  final int? limit;
  final bool softLimited;

  factory GateDecision.allowed({
    String status = 'ACTIVE',
    int? used,
    int? limit,
  }) =>
      GateDecision(allowed: true, status: status, used: used, limit: limit);

  factory GateDecision.softLimited({
    required String status,
    int? used,
    int? limit,
  }) =>
      GateDecision(
        allowed: true,
        status: status,
        used: used,
        limit: limit,
        softLimited: true,
        reason: 'soft_limit',
      );

  factory GateDecision.blocked({
    required String status,
    required String reason,
    int? used,
    int? limit,
  }) =>
      GateDecision(
        allowed: false,
        status: status,
        reason: reason,
        used: used,
        limit: limit,
      );
}

class FeatureGate {
  FeatureGate(this._dao, this._quotaEngine);

  final SubscriptionDao _dao;
  final UsageQuotaEngine _quotaEngine;

  Future<GateDecision> check({
    required String featureKey,
    String? metricKey,
  }) async {
    final now = DateTime.now();
    final state = await _dao.getSubscriptionState();
    final subscriptionStatus = SubscriptionStatus.fromWire(state?.status).code;

    final blockedStatus = _blockedBySubscription(state, now);
    if (blockedStatus != null) {
      return GateDecision.blocked(
        status: subscriptionStatus,
        reason: blockedStatus,
      );
    }

    final flag = await _dao.getFeatureFlag(featureKey);
    if (flag != null && !flag.isEnabled) {
      return GateDecision.blocked(
        status: subscriptionStatus,
        reason: 'flag_disabled',
      );
    }

    final entitlement = await _dao.getEntitlement(featureKey);
    final planDefinition = PlanCatalog.fromCode(state?.planCode);
    final planAllows = planDefinition.allowsFeature(featureKey);
    if (entitlement != null) {
      if (!entitlement.isEnabled) {
        return GateDecision.blocked(
          status: subscriptionStatus,
          reason: 'entitlement_disabled',
        );
      }
    } else if (!planAllows && FeatureKeys.all.contains(featureKey)) {
      return GateDecision.blocked(
        status: subscriptionStatus,
        reason: 'plan_restricted',
      );
    }

    final metric = metricKey ?? featureKey;
    final quota = await _quotaEngine.getQuota(metricKey: metric, now: now);
    final limit = quota.limit ?? entitlement?.limitValue;
    final used = quota.used;
    if (limit != null && used >= limit) {
      final softLimit = quota.softLimit;
      if (softLimit) {
        return GateDecision.softLimited(
          status: subscriptionStatus,
          used: used,
          limit: limit,
        );
      }
      return GateDecision.blocked(
        status: subscriptionStatus,
        reason: 'quota_exceeded',
        used: used,
        limit: limit,
      );
    }

    return GateDecision.allowed(
      status: subscriptionStatus,
      used: used,
      limit: limit,
    );
  }

  String? _blockedBySubscription(SubscriptionState? state, DateTime now) {
    if (state == null) return null;
    final status = SubscriptionStatus.fromWire(state.status);
    if (status.isInactive) {
      return 'subscription_inactive';
    }
    if (status.isPastDue) {
      final graceEndsAt = state.graceEndsAt;
      if (graceEndsAt != null && now.isAfter(graceEndsAt)) {
        return 'grace_expired';
      }
    }
    if (status == SubscriptionStatus.trial) {
      final trialEndsAt = state.trialEndsAt;
      if (trialEndsAt != null && now.isAfter(trialEndsAt)) {
        final graceEndsAt = state.graceEndsAt;
        if (graceEndsAt != null && now.isAfter(graceEndsAt)) {
          return 'trial_expired';
        }
      }
    }
    return null;
  }
}
