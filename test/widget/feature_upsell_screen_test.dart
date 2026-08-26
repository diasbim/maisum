import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/subscription/presentation/feature_upsell_screen.dart';

void main() {
  Future<void> pumpUpsellScreen(
    WidgetTester tester, {
    required bool isOwner,
  }) async {
    final router = GoRouter(
      initialLocation: featureUpsellRoutePath,
      routes: [
        GoRoute(
          path: featureUpsellRoutePath,
          builder: (_, __) => const FeatureUpsellScreen(
            args: FeatureUpsellArgs(
              featureKey: 'analytics',
              featureName: 'Relatórios de vendas',
            ),
          ),
        ),
        GoRoute(
          path: '/subscription-admin',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Gestão de planos')),
          ),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Painel')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOwnerUserProvider.overrideWith((ref) async => isOwner),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('owner can open plan management from the upsell screen',
      (tester) async {
    await pumpUpsellScreen(tester, isOwner: true);

    expect(find.text('Ver planos e subscrição'), findsOneWidget);
    expect(
      find.textContaining('Apenas o proprietário do negócio'),
      findsNothing,
    );

    await tester.tap(find.text('Ver planos e subscrição'));
    await tester.pumpAndSettle();

    expect(find.text('Gestão de planos'), findsOneWidget);
  });

  testWidgets('staff are guided to request the owner and can return home',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpUpsellScreen(tester, isOwner: false);

      expect(
        find.textContaining('Apenas o proprietário do negócio'),
        findsOneWidget,
      );
      expect(find.textContaining('Peça-lhe para rever a subscrição'),
          findsOneWidget);
      expect(find.text('Ver planos e subscrição'), findsNothing);
      expect(find.bySemanticsLabel('Voltar ao painel'), findsOneWidget);

      await tester.tap(find.text('Voltar ao painel'));
      await tester.pumpAndSettle();

      expect(find.text('Painel'), findsOneWidget);
      expect(find.text('Gestão de planos'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
