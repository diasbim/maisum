import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maisum/features/auth/presentation/role_gate_screen.dart';

void main() {
  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/choose-role',
      routes: [
        GoRoute(
          path: '/choose-role',
          builder: (_, __) => const RoleGateScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => Text(
            'business:${state.uri.queryParameters['source']}',
          ),
        ),
        GoRoute(
          path: '/customer-login/phone',
          builder: (_, state) => Text(
            'customer:${state.uri.queryParameters['source']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('clearly presents business owner and customer roles',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Como quer usar\na MaisUm?'), findsOneWidget);
    expect(find.text('Sou proprietário de negócio'), findsOneWidget);
    expect(find.text('Sou cliente'), findsOneWidget);
    expect(find.byKey(const Key('business_owner_role')), findsOneWidget);
    expect(find.byKey(const Key('customer_role')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('business choice opens the direct business login',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final businessPanel = find.byKey(const Key('business_owner_role'));
    await tester.ensureVisible(businessPanel);
    await tester.pumpAndSettle();
    await tester.tap(businessPanel);
    await tester.pumpAndSettle();

    expect(find.text('business:role'), findsOneWidget);
  });

  testWidgets('customer choice opens the direct customer login',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final customerPanel = find.byKey(const Key('customer_role'));
    await tester.ensureVisible(customerPanel);
    await tester.pumpAndSettle();
    await tester.tap(customerPanel);
    await tester.pumpAndSettle();

    expect(find.text('customer:role'), findsOneWidget);
  });

  testWidgets('role gate remains usable on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.text('Sou proprietário de negócio'), findsOneWidget);

    final customerTitle = find.text('Sou cliente');
    await tester.scrollUntilVisible(customerTitle, 300);
    expect(customerTitle, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
