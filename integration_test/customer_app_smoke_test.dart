import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';

class _SmokeCustomerRepository extends Fake implements CustomerAppRepository {
  @override
  Future<void> event(String eventType) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Customer shell opens every primary destination', (tester) async {
    final router = GoRouter(
      initialLocation: '/customer/home',
      routes: [
        ShellRoute(
          builder: (_, __, child) => CustomerShell(child: child),
          routes: [
            GoRoute(
              path: '/customer/home',
              builder: (_, __) => const CustomerHomeScreen(),
            ),
            GoRoute(
              path: '/customer/rewards',
              builder: (_, __) => const CustomerRewardsScreen(),
            ),
            GoRoute(
              path: '/customer/activity',
              builder: (_, __) => const CustomerActivityScreen(),
            ),
            GoRoute(
              path: '/customer/businesses',
              builder: (_, __) => const CustomerBusinessesScreen(),
            ),
            GoRoute(
              path: '/customer/profile',
              builder: (_, __) => const CustomerProfileScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    final updatedAt = DateTime(2026, 9);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerAppRepositoryProvider.overrideWithValue(
            _SmokeCustomerRepository(),
          ),
          customerFeatureFlagsProvider.overrideWith(
            (ref) async => _flags,
          ),
          customerHomeProvider.overrideWith(
            (ref) async => CustomerData(
              _businesses,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerBusinessesProvider.overrideWith(
            (ref) async => CustomerData(
              _businesses,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerRewardsProvider.overrideWith(
            (ref) async => CustomerData(
              const [_reward],
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerActivityProvider.overrideWith(
            (ref) async => CustomerData(
              const <CustomerActivity>[],
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerProfileProvider.overrideWith(
            (ref) async => CustomerData(
              _profile,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerNotificationsProvider.overrideWith(
            (ref) async => CustomerData(
              const <String, dynamic>{
                'push': <String, dynamic>{'delivery': 'registered'},
              },
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => CustomerExperienceTheme(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tudo o que ganhou, pronto para usar.'), findsOneWidget);

    for (final destination in const {
      'Prémios': '/customer/rewards',
      'Atividade': '/customer/activity',
      'Negócios': '/customer/businesses',
      'Perfil': '/customer/profile',
      'Início': '/customer/home',
    }.entries) {
      await tester.tap(find.text(destination.key).last);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        destination.value,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

const _flags = CustomerFeatureFlags(
  appEnabled: true,
  redemptionEnabled: true,
  qrEnabled: true,
  pushEnabled: true,
  deepLinksEnabled: true,
);

const _reward = CustomerReward(
  id: 'reward-1',
  businessId: 'business-1',
  name: 'Café grátis',
  description: 'Um café à sua escolha.',
  pointsRequired: 100,
  confirmedPoints: 150,
  pointsRemaining: 0,
  eligible: true,
);

const _businesses = [
  CustomerBusiness(
    id: 'business-1',
    name: 'Café Central',
    address: 'Maputo',
    phone: '+258840000001',
    confirmedPoints: 150,
    rewards: [_reward],
  ),
];

const _profile = CustomerProfile(
  displayName: 'Ana Mucavele',
  phone: '+258 84 000 0001',
  linkedBusinessCount: 1,
  preferences: CustomerPreferences(
    notificationsEnabled: true,
    marketingEnabled: false,
    deepLinksEnabled: true,
  ),
);
