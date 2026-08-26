import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/business_profile/domain/business_profile.dart';
import 'package:maisum/features/settings/presentation/settings_screen.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_snapshot.dart';
import 'package:maisum/features/subscription/domain/subscription_status.dart';
import 'package:maisum/features/subscription/domain/usage_quota.dart';
import 'package:maisum/features/subscription/presentation/feature_upsell_screen.dart';
import 'package:maisum/features/subscription/services/remote_config_reader.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.session);

  final AuthSession session;

  @override
  Future<AuthSession> build() async => session;
}

class _FakeSubscriptionSnapshotController
    extends SubscriptionSnapshotController {
  _FakeSubscriptionSnapshotController(this.snapshot);

  final SubscriptionSnapshot snapshot;

  @override
  Future<SubscriptionSnapshot> build() async => snapshot;

  @override
  Future<void> refresh() async {}
}

class _FakeRemoteConfigReader implements RemoteConfigReader {
  @override
  Future<bool?> getBool(String key) async => null;

  @override
  Future<int?> getInt(String key) async => null;

  @override
  Future<Map<String, dynamic>?> getJson(String key) async => null;

  @override
  Future<PricingOverride?> getPricingOverride(String planCode) async => null;

  @override
  Future<QuotaOverride?> getQuotaOverride(String metricKey) async => null;

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<int> getTrialDays() async => 14;

  @override
  Future<UpsellWhatsAppConfig> getUpsellWhatsAppConfig() async =>
      const UpsellWhatsAppConfig(number: '258840000000', message: 'Olá');
}

final _session = AuthSession(
  userId: 'owner-1',
  merchantId: 'merchant-1',
  phone: '+258841234567',
  merchantName: 'Loja Teste',
  expiresAt: DateTime(2099, 1, 1),
);

final _snapshot = SubscriptionSnapshot(
  plan: Plan.free,
  status: SubscriptionStatus.active,
  entitlements: const [],
  flags: const [],
  usageBalances: const [],
  whatsappQuota: UsageQuotaSummary(
    metricKey: 'whatsapp_messages',
    used: 0,
    limit: 150,
    resetAt: DateTime(2099, 1, 1),
  ),
);

Widget _buildScreen(
  FakeFirebaseFirestore firestore, {
  SubscriptionSnapshot? snapshot,
}) {
  final effectiveSnapshot = snapshot ?? _snapshot;
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: featureUpsellRoutePath,
        builder: (_, state) => FeatureUpsellScreen(
          args: FeatureUpsellArgs.fromQuery(state.uri.queryParameters),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_session)),
      activeAppUserRoleProvider.overrideWith((_) async => 'OWNER'),
      isOwnerUserProvider.overrideWith((_) async => true),
      activeBusinessProfileProvider.overrideWith(
        (_) async => BusinessProfiles.generic,
      ),
      firestoreInstanceProvider.overrideWithValue(firestore),
      remoteConfigReaderProvider.overrideWithValue(_FakeRemoteConfigReader()),
      subscriptionSnapshotProvider.overrideWith(
        () => _FakeSubscriptionSnapshotController(effectiveSnapshot),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<FakeFirebaseFirestore> _catalogWithPlans({
  int starterPriceCents = 99000,
}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('plans').doc('free').set({
    'plan_code': 'free',
    'display_name': 'FREE',
    'price_cents': 0,
    'currency': 'MZN',
    'billing_interval': 'monthly',
  });
  await firestore.collection('plans').doc('starter').set({
    'plan_code': 'starter',
    'display_name': 'STARTER',
    'price_cents': starterPriceCents,
    'currency': 'MZN',
    'billing_interval': 'monthly',
  });
  await firestore.collection('plans').doc('business').set({
    'plan_code': 'business',
    'display_name': 'BUSINESS',
    'price_cents': 199000,
    'currency': 'MZN',
    'billing_interval': 'monthly',
  });
  return firestore;
}

void main() {
  testWidgets('reviews a plan and its MZN price before confirming',
      (tester) async {
    final firestore = await _catalogWithPlans();
    await tester.pumpWidget(_buildScreen(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Subscrição'));
    await tester.pumpAndSettle();
    expect(find.text('MZN 990 /mês'), findsOneWidget);

    await tester.tap(find.text('STARTER'));
    await tester.pumpAndSettle();

    expect(find.text('Rever alteração de plano'), findsOneWidget);
    expect(find.text('STARTER'), findsOneWidget);
    expect(find.text('MZN 990 /mês'), findsOneWidget);
    expect(find.text('Confirmar alteração'), findsOneWidget);
  });

  testWidgets('opens the existing contact flow from Falar Connosco',
      (tester) async {
    final firestore = await _catalogWithPlans();
    await tester.pumpWidget(_buildScreen(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Subscrição'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Falar Connosco'));
    await tester.pumpAndSettle();

    expect(find.text('Desbloquear funcionalidade'), findsOneWidget);
    expect(find.text('Plano BUSINESS'), findsOneWidget);
    expect(find.text('Confirmar alteração'), findsNothing);
  });

  testWidgets('requires contact when the selected plan price is untrusted',
      (tester) async {
    final firestore = await _catalogWithPlans(starterPriceCents: -1);
    await tester.pumpWidget(_buildScreen(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Subscrição'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('STARTER'));
    await tester.pumpAndSettle();

    expect(find.text('Preço sob consulta'), findsOneWidget);
    expect(find.text('Falar Connosco'), findsOneWidget);
    expect(find.text('Confirmar alteração'), findsNothing);
  });

  testWidgets('empty catalog keeps fallback Free confirmable', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final starterSnapshot = SubscriptionSnapshot(
      plan: Plan.starter,
      status: SubscriptionStatus.active,
      entitlements: const [],
      flags: const [],
      usageBalances: const [],
      whatsappQuota: UsageQuotaSummary(
        metricKey: 'whatsapp_messages',
        used: 0,
        limit: 150,
        resetAt: DateTime(2099, 1, 1),
      ),
    );
    await tester.pumpWidget(
      _buildScreen(firestore, snapshot: starterSnapshot),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Subscrição'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free'));
    await tester.pumpAndSettle();

    expect(find.text('MZN 0 /mês'), findsOneWidget);
    expect(find.text('Confirmar alteração'), findsOneWidget);
    expect(find.text('Falar Connosco'), findsNothing);
  });
}
