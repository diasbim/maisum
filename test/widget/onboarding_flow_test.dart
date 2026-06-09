import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/storage/secure_storage.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/auth/presentation/onboarding_entry_screen.dart';
import 'package:maisum/features/auth/presentation/post_auth_navigation.dart';
import 'package:maisum/features/settings/presentation/merchant_config_screen.dart';

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
  _SpySecureStorageService({required this.initialPlanConfirmed})
      : super(const FlutterSecureStorage());

  final bool initialPlanConfirmed;
  int pendingPlanWrites = 0;

  @override
  Future<void> setOnboardingPlanConfirmed(bool value) async {
    if (!value) {
      pendingPlanWrites += 1;
    }
  }

  @override
  Future<bool> hasConfirmedOnboardingPlan() async => initialPlanConfirmed;
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
          _SpySecureStorageService(initialPlanConfirmed: planConfirmed)),
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

Widget _buildMerchantConfigFlow({
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
        builder: (_, __) => const MerchantConfigScreen(),
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
        builder: (_, __) => const Scaffold(body: Text('merchant-config-route')),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

Future<void> _openMerchantConfig(WidgetTester tester) async {
  await tester.tap(find.text('open-merchant-config'));
  await tester.pumpAndSettle();
}

Future<void> _selectDropdownOption(
  WidgetTester tester,
  int dropdownIndex,
  String value,
) async {
  final dropdown =
      find.byType(DropdownButtonFormField<String>).at(dropdownIndex);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Post-auth onboarding route resolution', () {
    testWidgets(
        'routes to onboarding plan when profile complete but plan not confirmed',
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
      await firestore.collection('businesses').doc('merchant-1').set({
        'merchant_name': 'Barbearia Z',
        'phone': '+258840000001',
        'city': 'Maputo',
        'business_type': 'Barbearia',
      });

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
  });

  group('Merchant onboarding first-time vs existing setup', () {
    testWidgets('first-time completed setup routes to mandatory plan selection',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);

      await tester.pumpWidget(
        _buildMerchantConfigFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await _openMerchantConfig(tester);

      await tester.enterText(
          find.byType(TextFormField).at(0), 'Barbearia Alfa');
      await tester.enterText(find.byType(TextFormField).at(1), '+258840000001');
      await _selectDropdownOption(tester, 0, 'Maputo');
      await _selectDropdownOption(tester, 1, 'Barbearia');

      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('onboarding-plan-route'), findsOneWidget);
      expect(storage.pendingPlanWrites, 1);
    });

    testWidgets('editing already complete profile returns to previous screen',
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
        phone: '+258840000001',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      final storage = _SpySecureStorageService(initialPlanConfirmed: true);

      await tester.pumpWidget(
        _buildMerchantConfigFlow(
          session: session,
          firestore: firestore,
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await _openMerchantConfig(tester);
      await tester.enterText(
          find.byType(TextFormField).at(0), 'Barbearia Zeta');
      await tester.ensureVisible(find.text('Continuar'));
      await tester.tap(find.text('Continuar'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('onboarding-plan-route'), findsNothing);
      expect(storage.pendingPlanWrites, 0);
    });
  });

  group('Onboarding entry UX', () {
    testWidgets('shows inline error when continuing without selection',
        (tester) async {
      await tester.pumpWidget(_buildOnboardingEntryFlow());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('Selecione uma opcao para continuar.'), findsOneWidget);
      expect(find.text('link-device-route'), findsNothing);
      expect(find.text('merchant-config-route'), findsNothing);
    });

    testWidgets('exposes core semantics labels for screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_buildOnboardingEntryFlow());
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('Progresso do onboarding'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Continuar para o proximo passo'),
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

      await tester.tap(find.text('Entrar em barbearia existente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('link-device-route'), findsOneWidget);
    });

    testWidgets('continues to merchant-config when create option is selected',
        (tester) async {
      await tester.pumpWidget(_buildOnboardingEntryFlow());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar nova barbearia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('merchant-config-route'), findsOneWidget);
    });
  });
}
