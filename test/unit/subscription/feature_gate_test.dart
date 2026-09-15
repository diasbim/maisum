import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/subscription/data/subscription_dao.dart';
import 'package:maisum/features/subscription/domain/entitlement.dart';
import 'package:maisum/features/subscription/domain/feature_flag.dart';
import 'package:maisum/features/subscription/domain/feature_keys.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_state.dart';
import 'package:maisum/features/subscription/services/feature_gate.dart';
import 'package:maisum/features/subscription/services/usage_quota_engine.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late SubscriptionDao dao;
  late FeatureGate gate;

  setUp(() async {
    db = await setUpTestDatabase();
    await _seedMerchant(db);
    dao = SubscriptionDao(AppDatabase.instance, merchantId: 'merchant-1');
    gate = FeatureGate(dao, UsageQuotaEngine(dao));
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test('active trial allows paid features regardless of free plan', () async {
    await dao.upsertSubscriptionState(_state(
      plan: Plan.free,
      status: 'TRIAL',
      trialEndsAt: DateTime.now().add(const Duration(days: 2)),
    ));

    final decision = await gate.check(
      featureKey: FeatureKeys.engageManageRecovery,
    );

    expect(decision.allowed, isTrue);
    expect(decision.status, 'TRIAL');
  });

  test('expired trial falls back to free features only', () async {
    final now = DateTime.now();
    await dao.upsertSubscriptionState(_state(
      plan: Plan.business,
      status: 'TRIAL',
      trialEndsAt: now.subtract(const Duration(days: 1)),
    ));
    await dao.upsertEntitlement(Entitlement(
      id: 'merchant-1_${FeatureKeys.engageManageRecovery}',
      merchantId: 'merchant-1',
      featureKey: FeatureKeys.engageManageRecovery,
      isEnabled: true,
      updatedAt: now,
    ));

    final paidDecision = await gate.check(
      featureKey: FeatureKeys.engageManageRecovery,
    );
    final freeDecision = await gate.check(
      featureKey: FeatureKeys.whatsappAutomation,
    );

    expect(paidDecision.allowed, isFalse);
    expect(paidDecision.reason, 'trial_expired');
    expect(freeDecision.allowed, isTrue);
  });

  test('undated trial falls back to free features only', () async {
    await dao.upsertSubscriptionState(_state(
      plan: Plan.business,
      status: 'TRIAL',
      trialEndsAt: null,
    ));

    final paidDecision = await gate.check(featureKey: FeatureKeys.analytics);
    final freeDecision = await gate.check(
      featureKey: FeatureKeys.whatsappAutomation,
    );

    expect(paidDecision.allowed, isFalse);
    expect(paidDecision.reason, 'trial_expired');
    expect(freeDecision.allowed, isTrue);
  });

  test('inactive subscription blocks trial access', () async {
    await dao.upsertSubscriptionState(_state(
      plan: Plan.business,
      status: 'SUSPENDED',
      trialEndsAt: DateTime.now().add(const Duration(days: 2)),
    ));

    final decision = await gate.check(
      featureKey: FeatureKeys.whatsappAutomation,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, 'subscription_inactive');
  });

  test('disabled feature flag blocks active trial feature', () async {
    final now = DateTime.now();
    await dao.upsertSubscriptionState(_state(
      plan: Plan.free,
      status: 'TRIAL',
      trialEndsAt: now.add(const Duration(days: 2)),
    ));
    await dao.upsertFeatureFlag(FeatureFlag(
      id: 'merchant-1_${FeatureKeys.campaigns}',
      merchantId: 'merchant-1',
      flagKey: FeatureKeys.campaigns,
      isEnabled: false,
      updatedAt: now,
    ));

    final decision = await gate.check(featureKey: FeatureKeys.campaigns);

    expect(decision.allowed, isFalse);
    expect(decision.reason, 'flag_disabled');
  });

  group('debug bypass', () {
    Future<void> seedWorstCaseBlockingState() async {
      final now = DateTime.now();
      // Suspended subscription on the FREE plan blocks every paid feature
      // for a different reason at every stage of FeatureGate.check: the
      // subscription check, the disabled flag, and the disabled entitlement.
      await dao.upsertSubscriptionState(_state(
        plan: Plan.free,
        status: 'SUSPENDED',
        trialEndsAt: null,
      ));
      for (final featureKey in FeatureKeys.all) {
        await dao.upsertFeatureFlag(FeatureFlag(
          id: 'merchant-1_$featureKey',
          merchantId: 'merchant-1',
          flagKey: featureKey,
          isEnabled: false,
          updatedAt: now,
        ));
        await dao.upsertEntitlement(Entitlement(
          id: 'merchant-1_$featureKey',
          merchantId: 'merchant-1',
          featureKey: featureKey,
          isEnabled: false,
          updatedAt: now,
        ));
      }
    }

    test('bypass disabled still blocks every feature (regression)', () async {
      await seedWorstCaseBlockingState();
      final blockedGate = FeatureGate(dao, UsageQuotaEngine(dao));

      for (final featureKey in FeatureKeys.all) {
        final decision = await blockedGate.check(featureKey: featureKey);
        expect(
          decision.allowed,
          isFalse,
          reason: '$featureKey should still be gated without the bypass',
        );
      }
    });

    test('bypass enabled allows every paid feature regardless of state',
        () async {
      await seedWorstCaseBlockingState();
      final bypassGate = FeatureGate(
        dao,
        UsageQuotaEngine(dao),
        debugBypassEnabled: true,
      );

      for (final featureKey in FeatureKeys.all) {
        final decision = await bypassGate.check(featureKey: featureKey);
        expect(
          decision.allowed,
          isTrue,
          reason: '$featureKey should be unlocked by the debug bypass',
        );
      }
    });
  });
}

Future<void> _seedMerchant(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('merchants', {
    'id': 'merchant-1',
    'phone': '+258840000000',
    'merchant_name': 'Minha Loja',
    'slug': 'minha-loja',
    'subscription_status': 'TRIAL',
    'created_at': now,
    'updated_at': now,
  });
}

SubscriptionState _state({
  required Plan plan,
  required String status,
  required DateTime? trialEndsAt,
}) {
  final now = DateTime.now();
  final periodStart = (trialEndsAt ?? now).subtract(const Duration(days: 30));
  return SubscriptionState(
    merchantId: 'merchant-1',
    planCode: plan.code,
    planName: plan.displayName,
    status: status,
    planVersion: 1,
    pricingVersion: 1,
    trialEndsAt: trialEndsAt,
    periodStart: periodStart,
    periodEnd: trialEndsAt,
    updatedAt: now,
  );
}
