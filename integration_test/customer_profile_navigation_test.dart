import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';
import 'package:maisum/features/legal/presentation/privacy_screen.dart';
import 'package:maisum/features/legal/presentation/terms_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile actions open their real Customer destinations',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/customer/profile',
      routes: [
        GoRoute(
          path: '/customer/profile',
          builder: (_, __) => const CustomerProfileScreen(),
        ),
        GoRoute(
          path: '/customer/preferences',
          builder: (_, __) => const CustomerPreferencesScreen(),
        ),
        GoRoute(
          path: '/customer/terms',
          builder: (_, __) => const TermsScreen(),
        ),
        GoRoute(
          path: '/customer/privacy',
          builder: (_, __) => const PrivacyScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerProfileProvider.overrideWith(
            (ref) async => CustomerData(
              _profile,
              fromCache: false,
              updatedAt: DateTime(2026, 9),
            ),
          ),
          customerNotificationsProvider.overrideWith(
            (ref) async => CustomerData(
              const <String, dynamic>{
                'push': <String, dynamic>{'delivery': 'registered'},
              },
              fromCache: false,
              updatedAt: DateTime(2026, 9),
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

    expect(find.text('Ana Mucavele'), findsOneWidget);
    expect(find.text('Terminar sessão'), findsOneWidget);

    final notificationsTile =
        find.widgetWithText(ListTile, 'Notificações push');
    await tester.ensureVisible(notificationsTile);
    await tester.pumpAndSettle();
    await tester.tap(notificationsTile);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        '/customer/preferences');
    expect(find.text('Novidades e ofertas'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    final termsTile = find.widgetWithText(ListTile, 'Termos de utilização');
    await tester.ensureVisible(termsTile);
    await tester.pumpAndSettle();
    await tester.tap(termsTile);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/customer/terms');
    expect(find.text('Termos e Condições'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    final privacyTile = find.widgetWithText(ListTile, 'Privacidade');
    await tester.ensureVisible(privacyTile);
    await tester.pumpAndSettle();
    await tester.tap(privacyTile);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/customer/privacy');
    expect(find.text('Política de Privacidade'), findsOneWidget);
  });
}

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
