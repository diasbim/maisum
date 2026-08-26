import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/router.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/constants/app_constants.dart';
import 'package:maisum/core/storage/secure_storage.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/auth/presentation/onboarding_entry_screen.dart';
import 'package:maisum/features/auth/presentation/post_auth_navigation.dart';
import 'package:maisum/features/merchant_onboarding/data/merchant_onboarding_repository.dart';
import 'package:maisum/features/merchant_onboarding/domain/merchant_onboarding_models.dart';
import 'package:maisum/features/merchant_onboarding/presentation/controllers/merchant_onboarding_controller.dart';
import 'package:maisum/features/merchant_onboarding/presentation/pages/business_info_page.dart';
import 'package:maisum/features/merchant_onboarding/presentation/pages/business_location_page.dart';
import 'package:maisum/features/merchant_onboarding/presentation/pages/business_type_page.dart';
import 'package:maisum/features/merchant_onboarding/presentation/pages/review_page.dart';
import 'package:maisum/features/merchant_onboarding/presentation/pages/services_page.dart';
import 'package:maisum/features/merchant_onboarding/presentation/pages/working_hours_page.dart';
import 'package:maisum/features/subscription/data/subscription_repository.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_snapshot.dart';
import 'package:maisum/features/subscription/domain/subscription_state.dart';
import 'package:maisum/features/subscription/services/remote_config_reader.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);

  AuthSession _session;

  @override
  Future<AuthSession?> build() async => _session;

  @override
  Future<AuthSession> updateMerchantName(String merchantName) async {
    _session = _session.copyWith(merchantName: merchantName);
    return _session;
  }

  @override
  Future<void> logout() async {}
}

class _SpySecureStorageService extends SecureStorageService {
  _SpySecureStorageService({
    required this.initialPlanConfirmed,
    this.appUserRole = AppConstants.appUserRoleOwner,
  }) : super(const FlutterSecureStorage());

  final bool initialPlanConfirmed;
  final String appUserRole;
  final _drafts = <String, String>{};
  final planConfirmationWrites = <bool>[];

  @override
  Future<void> setOnboardingPlanConfirmed(
    bool value, {
    String? merchantId,
    String? role,
  }) async {
    planConfirmationWrites.add(value);
  }

  @override
  Future<bool> hasConfirmedOnboardingPlan({
    String? merchantId,
    String? role,
  }) async =>
      initialPlanConfirmed;

  @override
  Future<String?> getAppUserRole() async => appUserRole;

  @override
  Future<bool> isOwnerUser() async =>
      appUserRole == AppConstants.appUserRoleOwner;

  @override
  Future<bool> hasPin() async => true;

  @override
  Future<void> saveMerchantOnboardingDraft(
    String value, {
    String? merchantId,
    String? role,
  }) async {
    _drafts[_draftKey(merchantId: merchantId, role: role)] = value;
  }

  @override
  Future<String?> getMerchantOnboardingDraft({
    String? merchantId,
    String? role,
  }) async {
    return _drafts[_draftKey(merchantId: merchantId, role: role)];
  }

  @override
  Future<void> clearMerchantOnboardingDraft({
    String? merchantId,
    String? role,
  }) async {
    _drafts.remove(_draftKey(merchantId: merchantId, role: role));
  }

  String _draftKey({String? merchantId, String? role}) {
    return 'merchant_onboarding_draft_${merchantId ?? ''}_${role ?? ''}';
  }
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
  Future<UpsellWhatsAppConfig> getUpsellWhatsAppConfig() async {
    return const UpsellWhatsAppConfig(number: '', message: '');
  }
}

class _SpySubscriptionRepository implements SubscriptionRepository {
  String? trialMerchantId;

  @override
  Future<SubscriptionState> ensureTrialStarted({
    required String merchantId,
    DateTime? startedAt,
    int trialDays = 14,
  }) async {
    trialMerchantId = merchantId;
    final start = startedAt ?? DateTime.now();
    final end = start.add(Duration(days: trialDays));
    return SubscriptionState(
      merchantId: merchantId,
      planCode: Plan.free.code,
      planName: Plan.free.displayName,
      status: 'TRIAL',
      planVersion: 1,
      pricingVersion: 1,
      trialEndsAt: end,
      periodStart: start,
      periodEnd: end,
      updatedAt: start,
    );
  }

  @override
  Future<SubscriptionSnapshot> getSnapshot() {
    throw UnsupportedError('getSnapshot is not used by onboarding tests');
  }

  @override
  Future<void> switchPlan({
    required String merchantId,
    required Plan plan,
    String? status,
  }) {
    throw UnsupportedError('switchPlan is not used by onboarding tests');
  }
}

class _FailingMerchantOnboardingRepository
    implements MerchantOnboardingRepository {
  @override
  Future<MerchantOnboardingConfig> loadConfig() async {
    throw Exception('permission-denied');
  }

  @override
  Future<MerchantDraft> loadRemoteDraft(AuthSession session) async {
    throw Exception('unavailable');
  }

  @override
  Future<void> saveMerchant({
    required AuthSession session,
    required MerchantDraft draft,
    required String firebaseUid,
    required bool wasProfileCompleteAtLoad,
  }) async {}
}

Widget _buildPostAuthRouteProbe({
  required AuthSession session,
  required FakeFirebaseFirestore firestore,
  required bool planConfirmed,
  required ValueChanged<WidgetRef> onRefReady,
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(session)),
      firestoreInstanceProvider.overrideWithValue(firestore),
      secureStorageServiceProvider.overrideWithValue(
        _SpySecureStorageService(initialPlanConfirmed: planConfirmed),
      ),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (_, ref, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onRefReady(ref);
          });
          return FutureBuilder<String>(
            future: resolvePostAuthRoute(ref.read),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              return Text(snapshot.data!);
            },
          );
        },
      ),
    ),
  );
}

class _HostScreen extends StatelessWidget {
  const _HostScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => context.push('/merchant-config'),
          child: const Text('open-merchant-config'),
        ),
      ),
    );
  }
}

Widget _buildMerchantConfigRedirectFlow({
  required AuthSession session,
  required FakeFirebaseFirestore firestore,
  required _SpySecureStorageService storage,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _HostScreen()),
      GoRoute(
        path: '/merchant-config',
        redirect: (_, __) => '/merchant-onboarding/type',
      ),
      GoRoute(
        path: '/merchant-onboarding/type',
        builder: (_, __) => const Scaffold(
          body: Text('merchant-onboarding-type-route'),
        ),
      ),
      GoRoute(
        path: '/onboarding-plan',
        builder: (_, __) => const Scaffold(body: Text('onboarding-plan-route')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(session)),
      firestoreInstanceProvider.overrideWithValue(firestore),
      secureStorageServiceProvider.overrideWithValue(storage),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _buildOnboardingEntryFlow() {
  final router = GoRouter(
    initialLocation: '/onboarding-entry',
    routes: [
      GoRoute(
        path: '/onboarding-entry',
        builder: (_, __) => const OnboardingEntryScreen(),
      ),
      GoRoute(
        path: '/link-device',
        builder: (_, __) => const Scaffold(body: Text('link-device-route')),
      ),
      GoRoute(
        path: '/merchant-config',
        redirect: (_, __) => '/merchant-onboarding/type',
      ),
      GoRoute(
        path: '/merchant-onboarding/type',
        builder: (_, __) =>
            const Scaffold(body: Text('merchant-onboarding-type-route')),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

Widget _buildOnboardingEntryToMerchantFlow({
  required AuthSession session,
  required FakeFirebaseFirestore firestore,
  required _SpySecureStorageService storage,
}) {
  final router = GoRouter(
    initialLocation: '/onboarding-entry',
    routes: [
      GoRoute(
        path: '/onboarding-entry',
        builder: (_, __) => const OnboardingEntryScreen(),
      ),
      GoRoute(
        path: '/link-device',
        builder: (_, __) => const Scaffold(body: Text('link-device-route')),
      ),
      GoRoute(
        path: '/merchant-onboarding/type',
        builder: (_, __) => const BusinessTypePage(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(session)),
      firestoreInstanceProvider.overrideWithValue(firestore),
      secureStorageServiceProvider.overrideWithValue(storage),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _buildMerchantOnboardingFlow({
  required AuthSession session,
  required FakeFirebaseFirestore firestore,
  required _SpySecureStorageService storage,
  _SpySubscriptionRepository? subscriptionRepository,
  String initialLocation = '/merchant-onboarding/type',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/onboarding-entry',
        builder: (_, __) =>
            const Scaffold(body: Text('onboarding-entry-route')),
      ),
      GoRoute(
        path: '/merchant-onboarding/type',
        builder: (_, state) => BusinessTypePage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/info',
        builder: (_, state) => BusinessInfoPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/location',
        builder: (_, state) => BusinessLocationPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/hours',
        builder: (_, state) => WorkingHoursPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/services',
        builder: (_, state) => ServicesPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/review',
        builder: (_, __) => const ReviewPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('dashboard-route')),
      ),
      GoRoute(
        path: '/onboarding-plan',
        builder: (_, __) => const Scaffold(
          body: Text('onboarding-plan-route'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(session)),
      firestoreInstanceProvider.overrideWithValue(firestore),
      secureStorageServiceProvider.overrideWithValue(storage),
      remoteConfigReaderProvider.overrideWithValue(_FakeRemoteConfigReader()),
      subscriptionRepositoryProvider.overrideWithValue(
        subscriptionRepository ?? _SpySubscriptionRepository(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _buildRouterFlow({
  required AuthSession session,
  required FakeFirebaseFirestore firestore,
  required _SpySecureStorageService storage,
  required String initialLocation,
}) {
  const ownerOnlyRoutes = {
    '/onboarding-plan',
    '/staff-management',
  };
  const merchantOnboardingBypassRoutes = {
    '/onboarding-entry',
    '/link-device',
    '/merchant-onboarding/type',
    '/merchant-onboarding/info',
    '/merchant-onboarding/location',
    '/merchant-onboarding/hours',
    '/merchant-onboarding/services',
    '/merchant-onboarding/review',
  };
  const planBypassRoutes = {
    '/onboarding-entry',
    '/link-device',
    '/merchant-onboarding/type',
    '/merchant-onboarding/info',
    '/merchant-onboarding/location',
    '/merchant-onboarding/hours',
    '/merchant-onboarding/services',
    '/merchant-onboarding/review',
    '/onboarding-plan',
  };

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(session)),
      firestoreInstanceProvider.overrideWithValue(firestore),
      secureStorageServiceProvider.overrideWithValue(storage),
    ],
    child: Consumer(
      builder: (_, ref, __) {
        final router = GoRouter(
          initialLocation: initialLocation,
          redirect: (_, state) async {
            final route = state.matchedLocation;
            final canAccessWithoutMerchantLink =
                merchantOnboardingBypassRoutes.contains(route);
            if (!canAccessWithoutMerchantLink) {
              final resolvedRoute = await resolvePostAuthRoute(ref.read);
              if (resolvedRoute == '/onboarding-entry' ||
                  resolvedRoute.startsWith('/merchant-onboarding')) {
                return resolvedRoute;
              }
            }

            final isOwner = await storage.isOwnerUser();
            if (ownerOnlyRoutes.contains(route) && !isOwner) {
              return '/dashboard';
            }

            if (isOwner) {
              final hasConfirmedPlan = await storage.hasConfirmedOnboardingPlan(
                merchantId: ref.read(activeMerchantIdProvider),
                role: await storage.getAppUserRole(),
              );
              if (!hasConfirmedPlan && !planBypassRoutes.contains(route)) {
                return '/onboarding-plan';
              }
            }

            return null;
          },
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const Scaffold(body: Text('dashboard-route')),
            ),
            GoRoute(
              path: '/merchant-config',
              redirect: (_, __) => '/merchant-onboarding/type',
            ),
            GoRoute(
              path: '/merchant-onboarding/type',
              builder: (_, __) => const Scaffold(
                body: Text('merchant-onboarding-type-route'),
              ),
            ),
            GoRoute(
              path: '/onboarding-entry',
              builder: (_, __) => const Scaffold(
                body: Text('onboarding-entry-route'),
              ),
            ),
            GoRoute(
              path: '/onboarding-plan',
              builder: (_, __) => const Scaffold(
                body: Text('onboarding-plan-route'),
              ),
            ),
          ],
        );
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}

Future<void> _openMerchantConfig(WidgetTester tester) async {
  await tester.tap(find.text('open-merchant-config'));
  await tester.pumpAndSettle();
}

Future<void> _seedMerchantOnboardingConfig(
  FakeFirebaseFirestore firestore,
) {
  return firestore.collection('merchant_onboarding_config').doc('default').set({
    'business_types': [
      {'id': 'barber_from_firestore', 'label': 'Barbearia Firestore'},
      {'id': 'salon_from_firestore', 'label': 'Salao Firestore'},
    ],
    'service_suggestions': [
      {'id': 'cut_from_firestore', 'name': 'Corte Firestore'},
      {'id': 'beard_from_firestore', 'name': 'Barba Firestore'},
    ],
    'weekday_labels': {
      '1': 'Segunda Firestore',
      '2': 'Terca Firestore',
    },
    'default_working_hours': {
      '1': {
        'weekday': 1,
        'open_time': '09:15',
        'close_time': '17:45',
        'is_open': true,
      },
      '2': {
        'weekday': 2,
        'open_time': '10:00',
        'close_time': '16:00',
        'is_open': true,
      },
    },
  });
}

Map<String, Object?> _completeBusinessData() {
  return {
    'merchant_name': 'Barbearia Z',
    'phone': '+258840000001',
    'city': 'Maputo',
    'district': 'KaMpfumo',
    'business_type': 'barber_from_firestore',
    'address': 'Rua Completa 123',
    'location': {
      'latitude': -25.95,
      'longitude': 32.58,
    },
    'working_hours': {
      '1': {
        'weekday': 1,
        'open_time': '09:00',
        'close_time': '18:00',
        'is_open': true,
      },
    },
    'services': [
      {'id': 'cut_from_firestore', 'name': 'Corte Firestore'},
    ],
  };
}

Future<void> _tapVisibleText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  group('Post-auth onboarding route resolution', () {
    testWidgets(
        'routes to onboarding plan when profile complete but plan not confirmed',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('businesses')
          .doc('merchant-1')
          .set(_completeBusinessData());

      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;

      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: false,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/onboarding-plan');
    });

    testWidgets('routes to dashboard when profile complete and plan confirmed',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('businesses')
          .doc('merchant-1')
          .set(_completeBusinessData());

      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;

      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: true,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/dashboard');
    });

    testWidgets('routes to onboarding entry when session has no merchant id',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final session = AuthSession(
        userId: 'user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;

      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: false,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/onboarding-entry');
    });

    testWidgets('routes to onboarding entry when merchant id is detached',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;

      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: false,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/onboarding-entry');
    });

    testWidgets('routes explicit incomplete merchant document to setup',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('businesses').doc('merchant-1').set({
        'merchant_name': 'Minha Loja',
        'phone': '+258840000001',
      });

      final session = AuthSession(
        userId: 'user-2',
        merchantId: 'merchant-1',
        firebaseUid: 'user-2',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;

      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: true,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/merchant-onboarding/type');
    });
  });

  group('Merchant onboarding first-time vs existing setup', () {
    testWidgets(
        'new flow falls back when Firestore onboarding catalog is absent',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        firebaseUid: 'firebase-user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Barbearia'), findsOneWidget);
      expect(find.text('Salão de beleza'), findsOneWidget);
      expect(
        find.text(
          'As categorias de negócio ainda não foram configuradas no Firestore.',
        ),
        findsNothing,
      );
    });

    testWidgets('new flow still opens when remote draft and config fail',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        firebaseUid: 'firebase-user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider
                .overrideWith(() => _FakeAuthController(session)),
            firestoreInstanceProvider.overrideWithValue(firestore),
            secureStorageServiceProvider.overrideWithValue(storage),
            merchantOnboardingRepositoryProvider.overrideWithValue(
              _FailingMerchantOnboardingRepository(),
            ),
          ],
          child: const MaterialApp(home: BusinessTypePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Barbearia'), findsOneWidget);
      expect(
        find.text('Não foi possível carregar a configuração inicial.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('business type selection advances to business info',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        firebaseUid: 'firebase-user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(
        const Key('business_type_option_barber_from_firestore'),
      ));
      await tester.pumpAndSettle();
      await _tapVisibleText(tester, 'Continuar');

      expect(find.text('Dados do negócio'), findsOneWidget);
      expect(
          find.widgetWithText(TextField, 'Nome do negócio *'), findsOneWidget);
    });

    testWidgets('business info requires city and district', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-required-location',
        merchantId: 'merchant-required-location',
        firebaseUid: 'firebase-required-location',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
          initialLocation: '/merchant-onboarding/info',
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome do negócio *'),
        'Lavandaria Central',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Cidade *'),
        'Maputo',
      );
      await _tapVisibleText(tester, 'Continuar');

      expect(find.text('Informe o bairro ou distrito.'), findsOneWidget);
      expect(find.text('Dados do negócio'), findsOneWidget);
    });

    testWidgets('system back follows the previous onboarding step',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-system-back',
        merchantId: 'merchant-system-back',
        firebaseUid: 'firebase-system-back',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      const cases = {
        '/merchant-onboarding/type': 'onboarding-entry-route',
        '/merchant-onboarding/info': 'Qual é o tipo do negócio?',
        '/merchant-onboarding/location': 'Dados do negócio',
        '/merchant-onboarding/hours': 'Detalhes da localização',
        '/merchant-onboarding/services': 'Horário de funcionamento',
        '/merchant-onboarding/review': 'Produtos e serviços',
      };

      for (final entry in cases.entries) {
        await tester.pumpWidget(
          _buildMerchantOnboardingFlow(
            session: session,
            firestore: firestore,
            storage: storage,
            initialLocation: entry.key,
          ),
        );
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'System back failed from ${entry.key}',
        );
      }
    });

    testWidgets('toolbar back follows the previous onboarding step',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-toolbar-back',
        merchantId: 'merchant-toolbar-back',
        firebaseUid: 'firebase-toolbar-back',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      const cases = {
        '/merchant-onboarding/type': 'onboarding-entry-route',
        '/merchant-onboarding/info': 'Qual é o tipo do negócio?',
        '/merchant-onboarding/location': 'Dados do negócio',
        '/merchant-onboarding/hours': 'Detalhes da localização',
        '/merchant-onboarding/services': 'Horário de funcionamento',
        '/merchant-onboarding/review': 'Produtos e serviços',
      };

      for (final entry in cases.entries) {
        await tester.pumpWidget(
          _buildMerchantOnboardingFlow(
            session: session,
            firestore: firestore,
            storage: storage,
            initialLocation: entry.key,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();

        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'Toolbar back failed from ${entry.key}',
        );
      }
    });

    testWidgets('business type continue ignores stale incomplete location step',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Salao Cache',
        firebaseUid: 'firebase-user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      await storage.saveMerchantOnboardingDraft(
        jsonEncode(const MerchantDraft(
          businessType: 'salon_from_firestore',
          businessName: 'Salao Cache',
          city: 'Maputo',
          phone: '+258840000001',
        ).toJson()),
        merchantId: session.resolvedMerchantId,
        role: AppConstants.appUserRoleOwner,
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisibleText(tester, 'Continuar');

      expect(find.text('Dados do negócio'), findsOneWidget);
      expect(find.text('Selecione a localização do negócio.'), findsNothing);
    });

    testWidgets('new flow starts trial and continues to plan selection',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: false);
      final subscriptionRepository = _SpySubscriptionRepository();
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        firebaseUid: 'firebase-user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
          subscriptionRepository: subscriptionRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(
        const Key('business_type_option_barber_from_firestore'),
      ));
      await tester.pumpAndSettle();
      await _tapVisibleText(tester, 'Continuar');

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome do negócio *'),
        'Barbearia Firebase',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Cidade *'),
        'Matola',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Bairro ou distrito *'),
        'Matola A',
      );
      await tester.pumpAndSettle();
      await _tapVisibleText(tester, 'Continuar');

      expect(find.text('Latitude *'), findsNothing);
      expect(find.text('Longitude *'), findsNothing);
      await _tapVisibleText(tester, 'Adicionar depois');

      expect(find.text('Segunda Firestore'), findsOneWidget);
      expect(find.text('09:15 - 17:45'), findsOneWidget);
      await _tapVisibleText(tester, 'Configurar depois');

      await _tapVisibleText(tester, 'Configurar depois');

      await _tapVisibleText(tester, 'Criar conta');
      await tester.pumpAndSettle();

      final savedBusiness =
          await firestore.collection('businesses').doc('merchant-1').get();
      final data = savedBusiness.data();
      expect(data, isNotNull);
      expect(data, containsPair('merchant_name', 'Barbearia Firebase'));
      expect(data, containsPair('business_type', 'barber_from_firestore'));
      expect(data, containsPair('business_profile_version', 1));
      expect(data, containsPair('city', 'Matola'));
      expect(data, containsPair('district', 'Matola A'));
      expect(data, containsPair('owner_user_id', 'user-1'));
      expect(data, containsPair('firebase_uid', 'firebase-user-1'));
      expect(data?.containsKey('address'), isFalse);
      expect(data?.containsKey('location'), isFalse);
      expect(data?.containsKey('working_hours'), isFalse);
      expect(data?.containsKey('services'), isFalse);
      final catalogItem = await firestore
          .collection('businesses')
          .doc('merchant-1')
          .collection('merchant_items')
          .doc('cut_from_firestore')
          .get();
      expect(catalogItem.exists, isFalse);
      expect(subscriptionRepository.trialMerchantId, 'merchant-1');
      expect(storage.planConfirmationWrites, isEmpty);
      expect(
        await storage.getMerchantOnboardingDraft(
          merchantId: 'merchant-1',
          role: AppConstants.appUserRoleOwner,
        ),
        isNull,
      );
      expect(find.text('onboarding-plan-route'), findsOneWidget);
    });

    testWidgets('editing business type from review returns to review',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      await firestore
          .collection('businesses')
          .doc('merchant-review-edit')
          .set(_completeBusinessData());
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-review-edit',
        merchantId: 'merchant-review-edit',
        firebaseUid: 'firebase-review-edit',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
          initialLocation: '/merchant-onboarding/review',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editar').first);
      await tester.pumpAndSettle();
      expect(find.text('Qual é o tipo do negócio?'), findsOneWidget);

      await tester.tap(find.byKey(
        const Key('business_type_option_salon_from_firestore'),
      ));
      await tester.pumpAndSettle();
      await _tapVisibleText(tester, 'Continuar');

      expect(find.text('Confirme os dados'), findsOneWidget);
      expect(find.text('Salao Firestore'), findsOneWidget);
    });

    testWidgets('skipping location preserves existing coordinates',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      await firestore
          .collection('businesses')
          .doc('merchant-existing-location')
          .set(_completeBusinessData());
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-existing-location',
        merchantId: 'merchant-existing-location',
        firebaseUid: 'firebase-existing-location',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantOnboardingFlow(
          session: session,
          firestore: firestore,
          storage: storage,
          initialLocation: '/merchant-onboarding/location',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Latitude *'), findsNothing);
      expect(find.text('Longitude *'), findsNothing);
      await _tapVisibleText(tester, 'Adicionar depois');
      await _tapVisibleText(tester, 'Configurar depois');
      await _tapVisibleText(tester, 'Configurar depois');
      await _tapVisibleText(tester, 'Criar conta');

      final saved = await firestore
          .collection('businesses')
          .doc('merchant-existing-location')
          .get();
      expect(saved.data()?['location'], containsPair('latitude', -25.95));
      expect(saved.data()?['location'], containsPair('longitude', 32.58));
    });

    testWidgets('legacy merchant-config path redirects to new onboarding',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        firebaseUid: 'user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildMerchantConfigRedirectFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await _openMerchantConfig(tester);
      expect(find.text('merchant-onboarding-type-route'), findsOneWidget);
    });

    testWidgets('legacy complete profile fields still enter new onboarding',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('businesses').doc('merchant-1').set({
        'merchant_name': 'Barbearia Z',
        'phone': '+258840000001',
        'city': 'Maputo',
        'business_type': 'Barbearia',
      });

      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Barbearia Z',
        firebaseUid: 'user-1',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;
      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: true,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/merchant-onboarding/type');
    });
  });

  group('Router onboarding guards', () {
    test(
        'production plan guard allows contact flow but not protected administration',
        () {
      expect(
        canAccessWithoutOnboardingPlanConfirmation('/feature-upsell'),
        isTrue,
      );
      expect(
        canAccessWithoutOnboardingPlanConfirmation('/subscription-admin'),
        isFalse,
      );
      expect(
        canAccessWithoutOnboardingPlanConfirmation('/dashboard'),
        isFalse,
      );
    });

    testWidgets('redirects staff away from onboarding plan', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('businesses')
          .doc('merchant-1')
          .set(_completeBusinessData());

      final session = AuthSession(
        userId: 'staff-1',
        merchantId: 'merchant-1',
        merchantName: 'Barbearia Z',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildRouterFlow(
          session: session,
          firestore: firestore,
          storage: _SpySecureStorageService(
            initialPlanConfirmed: true,
            appUserRole: AppConstants.appUserRoleStaff,
          ),
          initialLocation: '/onboarding-plan',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('dashboard-route'), findsOneWidget);
      expect(find.text('Escolha o seu plano'), findsNothing);
    });

    testWidgets('resolves protected deep links to incomplete merchant setup',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('businesses').doc('merchant-1').set({
        'merchant_name': 'Minha Loja',
        'phone': '+258840000001',
      });

      final session = AuthSession(
        userId: 'user-2',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        firebaseUid: 'user-2',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      WidgetRef? capturedRef;

      await tester.pumpWidget(
        _buildPostAuthRouteProbe(
          session: session,
          firestore: firestore,
          planConfirmed: true,
          onRefReady: (ref) => capturedRef = ref,
        ),
      );
      await tester.pumpAndSettle();

      final route = await resolvePostAuthRoute(capturedRef!.read);
      expect(route, '/merchant-onboarding/type');
    });
  });

  group('Onboarding entry UX', () {
    testWidgets('shows inline error when continuing without selection',
        (tester) async {
      await tester.pumpWidget(_buildOnboardingEntryFlow());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('Selecione uma opção para continuar.'), findsOneWidget);
      expect(find.text('link-device-route'), findsNothing);
      expect(find.text('merchant-config-route'), findsNothing);
    });

    testWidgets('exposes core semantics labels for screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_buildOnboardingEntryFlow());
        await tester.pumpAndSettle();

        expect(find.text('Vamos começar'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Continuar para o próximo passo'),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('continues to link-device when join option is selected',
        (tester) async {
      await tester.pumpWidget(_buildOnboardingEntryFlow());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entrar num negócio existente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('link-device-route'), findsOneWidget);
    });

    testWidgets(
        'continues to merchant onboarding when create option is selected',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMerchantOnboardingConfig(firestore);
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);
      final session = AuthSession(
        userId: 'user-new-business',
        firebaseUid: 'firebase-new-business',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _buildOnboardingEntryToMerchantFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar novo negócio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.byType(BusinessTypePage), findsOneWidget);
      expect(find.text('Barbearia Firestore'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
