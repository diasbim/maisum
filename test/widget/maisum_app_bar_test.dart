import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maisum/core/theme/app_colors.dart';
import 'package:maisum/core/theme/app_theme.dart';
import 'package:maisum/design_system/components/maisum_app_bar.dart';

void main() {
  testWidgets('surface app bar keeps navigation and title visible', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/feature',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Painel')),
        ),
        GoRoute(
          path: '/feature',
          builder: (_, __) => const Scaffold(
            appBar: MaisUmAppBar(
              title: 'Desbloquear funcionalidade',
              dismissal: MaisUmAppBarDismissal.close,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, AppColors.offWhite);
    expect(appBar.foregroundColor, AppColors.onSurface);
    expect(appBar.titleTextStyle?.color, AppColors.onSurface);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('Desbloquear funcionalidade'), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();

    expect(find.text('Painel'), findsOneWidget);
  });
}
