import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/subscription/data/subscription_dao.dart';
import 'package:maisum/features/subscription/data/subscription_repository.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_state.dart';
import 'package:maisum/features/subscription/services/usage_quota_engine.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  const merchantId = 'merchant-1';
  late SubscriptionDao subscriptionDao;
  late SyncDao syncDao;
  late SubscriptionRepository repository;

  setUp(() async {
    await setUpTestDatabase();
    subscriptionDao =
        SubscriptionDao(AppDatabase.instance, merchantId: merchantId);
    syncDao = SyncDao(AppDatabase.instance, merchantId: merchantId);
    repository = SubscriptionRepository(
      subscriptionDao,
      UsageQuotaEngine(subscriptionDao),
      syncDao,
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test('starts a free-plan trial and enqueues sync once', () async {
    final startedAt = DateTime(2026, 7, 6, 10);

    final state = await repository.ensureTrialStarted(
      merchantId: merchantId,
      startedAt: startedAt,
      trialDays: 30,
    );

    expect(state.planCode, Plan.free.code);
    expect(state.status, 'TRIAL');
    expect(state.periodStart, startedAt);
    expect(state.periodEnd, startedAt.add(const Duration(days: 30)));
    expect(state.trialEndsAt, startedAt.add(const Duration(days: 30)));

    final persisted = await subscriptionDao.getSubscriptionState();
    expect(persisted?.trialEndsAt, state.trialEndsAt);

    final pending = await syncDao.getPending();
    expect(pending, hasLength(1));
    expect(pending.single.entityType, 'subscription_state');
    expect(pending.single.entityId, merchantId);
    final payload = jsonDecode(pending.single.payload) as Map<String, dynamic>;
    expect(payload['trial_ends_at'], state.trialEndsAt!.millisecondsSinceEpoch);
  });

  test('does not reset an existing trial', () async {
    final existingEndsAt = DateTime(2026, 8, 1, 10);
    await subscriptionDao.upsertSubscriptionState(SubscriptionState(
      merchantId: merchantId,
      planCode: Plan.free.code,
      planName: Plan.free.displayName,
      status: 'TRIAL',
      planVersion: 1,
      pricingVersion: 1,
      trialEndsAt: existingEndsAt,
      periodStart: DateTime(2026, 7, 2, 10),
      periodEnd: existingEndsAt,
      updatedAt: DateTime(2026, 7, 2, 10),
    ));

    final state = await repository.ensureTrialStarted(
      merchantId: merchantId,
      startedAt: DateTime(2026, 7, 6, 10),
      trialDays: 30,
    );

    expect(state.trialEndsAt, existingEndsAt);
    expect(await syncDao.getPending(), isEmpty);
  });
}
