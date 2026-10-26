import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/business_profile/domain/business_profile.dart';
import 'package:maisum/features/settings/presentation/settings_screen.dart';
import 'package:maisum/features/subscription/data/subscription_dao.dart';
import 'package:maisum/features/subscription/domain/entitlement.dart';
import 'package:maisum/features/subscription/domain/feature_flag.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_snapshot.dart';
import 'package:maisum/features/subscription/domain/subscription_state.dart';
import 'package:maisum/features/subscription/domain/subscription_status.dart';
import 'package:maisum/features/subscription/domain/usage_balance.dart';
import 'package:maisum/features/subscription/domain/usage_quota.dart';
import 'package:maisum/features/subscription/presentation/feature_upsell_screen.dart';
import 'package:maisum/features/subscription/services/remote_config_reader.dart';
import 'package:maisum/core/storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exercises every paid module listed in the Settings "Premium" section
/// against a merchant on the FREE plan: each one must be blocked (routed to
/// the upsell screen) by default, and must open its real route once the
/// debug-only "Liberar módulos pagos" bypass toggle is switched on. Confirms
/// the QA bypass added to [FeatureGate] actually unlocks every paid module,
/// not just the ones covered by narrower unit tests.
///
/// Uses an in-memory fake [SubscriptionDao] (rather than the real sqflite
/// database) so this can run as an ordinary widget test: sqflite_common_ffi
/// talks to a background isolate, which needs real event-loop time that the
/// fake async zone behind `testWidgets` does not provide.
void main() {
  const paidRoutes = [
    '/sales',
    '/retention',
    '/engage',
    '/engage/actions',
    '/engage/visit-report',
    '/engage/surveys/analytics',
  ];

  const paidTitles = [
    'Relatórios de vendas',
    'Retenção de clientes',
    'MaisUm Engage',
    'Fila de recuperação',
    'Relatórios de visitas',
    'Análise de questionários',
  ];

  testWidgets(
    'every paid module is blocked on the FREE plan without the bypass',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_buildScreen(firestore));
      await tester.pumpAndSettle();

      for (final title in paidTitles) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();

        expect(
          find.text('Desbloquear funcionalidade'),
          findsOneWidget,
          reason: '$title should be gated on the FREE plan',
        );

        // Sole route on the router stack is the upsell push — pop it to
        // return to Settings before checking the next module.
        final router =
            GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.pop();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'every paid module opens once the debug bypass toggle is enabled',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_buildScreen(firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Liberar módulos pagos'));
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isTrue);

      for (var i = 0; i < paidTitles.length; i++) {
        final title = paidTitles[i];
        final route = paidRoutes[i];

        await tester.tap(find.text(title));
        await tester.pumpAndSettle();

        expect(
          find.text('Desbloquear funcionalidade'),
          findsNothing,
          reason: '$title should bypass gating once the toggle is on',
        );
        expect(
          find.text('route:$route'),
          findsOneWidget,
          reason: '$title should open its real route ($route)',
        );

        final router =
            GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.pop();
        await tester.pumpAndSettle();
      }
    },
  );
}

/// In-memory stand-in for [SubscriptionDao] fixed to a merchant on the FREE
/// plan with no entitlements or flags, so every paid [FeatureKeys] entry is
/// blocked by [PlanCatalog] unless [FeatureGate]'s debug bypass is active.
class _FakeFreePlanSubscriptionDao extends SubscriptionDao {
  _FakeFreePlanSubscriptionDao()
      : super(AppDatabase.instance, merchantId: 'merchant-1');

  @override
  Future<SubscriptionState?> getSubscriptionState() async {
    final now = DateTime.now();
    return SubscriptionState(
      merchantId: 'merchant-1',
      planCode: Plan.free.code,
      planName: Plan.free.displayName,
      status: 'ACTIVE',
      planVersion: 1,
      pricingVersion: 1,
      trialEndsAt: null,
      periodStart: now.subtract(const Duration(days: 5)),
      periodEnd: now.add(const Duration(days: 25)),
      updatedAt: now,
    );
  }

  @override
  Future<Entitlement?> getEntitlement(String featureKey) async => null;

  @override
  Future<FeatureFlag?> getFeatureFlag(String flagKey) async => null;

  @override
  Future<UsageBalance?> getUsageBalance({
    required String metricKey,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async =>
      null;
}

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

/// In-memory secure storage so the debug-bypass toggle's persistence layer
/// doesn't touch the (unmocked) platform channel in this widget test.
class _FakeSecureStorageServiceForBypass extends SecureStorageService {
  _FakeSecureStorageServiceForBypass() : super(const FlutterSecureStorage());

  bool _bypass = false;

  @override
  Future<void> setDebugBypassPaidFeatureGate(bool value) async {
    _bypass = value;
  }

  @override
  Future<bool> getDebugBypassPaidFeatureGate() async => _bypass;
}

final _session = AuthSession(
  userId: 'owner-1',
  merchantId: 'merchant-1',
  phone: '+258841234567',
  merchantName: 'Loja Teste',
  expiresAt: DateTime(2099, 1, 1),
);

final _freeSnapshot = SubscriptionSnapshot(
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

Widget _buildScreen(FakeFirebaseFirestore firestore) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: featureUpsellRoutePath,
        builder: (_, state) => FeatureUpsellScreen(
          args: FeatureUpsellArgs.fromQuery(state.uri.queryParameters),
        ),
      ),
      for (final route in const [
        '/sales',
        '/retention',
        '/engage',
        '/engage/actions',
        '/engage/visit-report',
        '/engage/surveys/analytics',
      ])
        GoRoute(
          path: route,
          builder: (_, __) => Scaffold(body: Text('route:$route')),
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
        () => _FakeSubscriptionSnapshotController(_freeSnapshot),
      ),
      subscriptionDaoProvider.overrideWithValue(
        _FakeFreePlanSubscriptionDao(),
      ),
      secureStorageServiceProvider.overrideWithValue(
        _FakeSecureStorageServiceForBypass(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
