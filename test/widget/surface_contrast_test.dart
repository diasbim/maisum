import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/core/theme/app_colors.dart';
import 'package:maisum/core/theme/app_theme.dart';
import 'package:maisum/core/widgets/sync_status_bar.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/auth/presentation/onboarding_entry_screen.dart';
import 'package:maisum/features/merchant_onboarding/presentation/widgets/onboarding_widgets.dart';
import 'package:maisum/features/sync/sync_service.dart';

void main() {
  test('light-surface semantic colors meet WCAG AA for normal text', () {
    expect(_contrast(AppColors.onSurface, AppColors.white), greaterThan(4.5));
    expect(
      _contrast(AppColors.onSurfaceVariant, AppColors.white),
      greaterThan(4.5),
    );
    expect(
      _contrast(AppColors.secondaryForeground, AppColors.white),
      greaterThan(4.5),
    );
    expect(
      _contrast(AppColors.error, AppColors.errorContainer),
      greaterThan(4.5),
    );
  });

  testWidgets('light surfaces establish readable semantics in a dark theme',
      (tester) async {
    await tester.pumpWidget(
      _darkApp(
        MaisUmSurface(
          child: Builder(
            builder: (context) => Column(
              children: [
                Text(
                  'Primary content',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Secondary content',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(onPressed: () {}, child: const Text('Edit')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('Primary content')).style?.color,
      AppColors.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Secondary content')).style?.color,
      AppColors.onSurfaceVariant,
    );
    expect(
      Theme.of(tester.element(find.text('Edit')))
          .textButtonTheme
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{}),
      AppColors.secondaryForeground,
    );
  });

  testWidgets('selected navy surfaces retain white and gold semantics',
      (tester) async {
    await tester.pumpWidget(
      _darkApp(
        MaisUmSurface(
          selected: true,
          child: Builder(
            builder: (context) => Column(
              children: [
                Text(
                  'Selected option',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(onPressed: () {}, child: const Text('Select')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('Selected option')).style?.color,
      AppColors.white,
    );
    expect(
      Theme.of(tester.element(find.text('Select')))
          .textButtonTheme
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{}),
      AppColors.secondary,
    );
  });

  testWidgets('review cards keep titles, values, and edit actions readable',
      (tester) async {
    await tester.pumpWidget(
      _darkApp(
        ReviewCard(
          title: 'Negócio',
          icon: Icons.storefront_rounded,
          onEdit: () {},
          child: const Text('MaisUm'),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('Negócio')).style?.color,
      AppColors.onSurface,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('MaisUm'))).style.color,
      AppColors.onSurface,
    );
    expect(
      Theme.of(tester.element(find.text('Editar')))
          .textButtonTheme
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{}),
      AppColors.secondaryForeground,
    );
  });

  testWidgets('onboarding option cards remain active-looking in dark mode',
      (tester) async {
    await tester.pumpWidget(_darkApp(const OnboardingEntryScreen()));

    final title =
        tester.widget<Text>(find.text('Entrar num negócio existente'));
    final subtitle =
        tester.widget<Text>(find.text('Usar o código do negócio.'));
    final unselectedRadio = tester.widget<Icon>(
      find.byIcon(Icons.radio_button_unchecked_rounded).first,
    );

    expect(title.style?.color, AppColors.onSurface);
    expect(subtitle.style?.color, AppColors.onSurfaceVariant);
    expect(unselectedRadio.color, AppColors.onSurfaceVariant);

    await tester.tap(find.text('Entrar num negócio existente'));
    await tester.pumpAndSettle();

    final selectedTitle =
        tester.widget<Text>(find.text('Entrar num negócio existente'));
    final selectedRadio = tester.widget<Icon>(
      find.byIcon(Icons.radio_button_checked_rounded),
    );
    expect(selectedTitle.style?.color, AppColors.white);
    expect(selectedRadio.color, AppColors.secondary);
  });

  testWidgets('failed sync action uses the error foreground on its light state',
      (tester) async {
    await tester.pumpWidget(
      _darkApp(
        const SyncStatusBar(
          status: SyncStatus(
            isOnline: true,
            phase: SyncPhase.syncFailed,
            pendingCount: 1,
            lastError: 'Algo correu mal. Tente novamente.',
          ),
          isOnline: true,
          onTap: _noop,
          onRetry: _noop,
        ),
      ),
    );

    final retryButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, AppStrings.syncRetryNow),
    );
    expect(
      retryButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      AppColors.error,
    );
  });
}

Widget _darkApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.dark,
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void _noop() {}
