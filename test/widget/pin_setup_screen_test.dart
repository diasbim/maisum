import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loyalty_app/app/providers.dart';
import 'package:loyalty_app/core/constants/app_strings.dart';
import 'package:loyalty_app/features/auth/presentation/pin_setup_screen.dart';

import '../helpers/fake_secure_storage.dart';

Widget _buildScreen({FakeSecureStorageService? storage}) {
  final fake = storage ?? FakeSecureStorageService();

  final router = GoRouter(
    initialLocation: '/pin-setup',
    routes: [
      GoRoute(path: '/pin-setup', builder: (_, __) => const PinSetupScreen()),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('dashboard'))),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('login'))),
    ],
  );

  return ProviderScope(
    overrides: [
      secureStorageServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.ensureVisible(find.text(d).first);
    await tester.tap(find.text(d).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('PinSetupScreen', () {
    testWidgets('shows setup title and subtitle initially', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      expect(find.text(AppStrings.pinSetupTitle), findsOneWidget);
      expect(find.text(AppStrings.pinSetupSubtitle), findsOneWidget);
    });

    testWidgets('shows lock icon', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/logo.png',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders number pad digits 0-9', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      for (final d in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
        expect(find.text(d), findsOneWidget);
      }
    });

    testWidgets('transitions to confirm title after 4 digits entered',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      await _tapDigits(tester, '1234');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppStrings.pinConfirmTitle), findsOneWidget);
      expect(find.text(AppStrings.pinConfirmSubtitle), findsOneWidget);
    });

    testWidgets('shows mismatch error when confirm PIN differs',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      // Enter first PIN: 1234
      await _tapDigits(tester, '1234');
      await tester.pump(const Duration(milliseconds: 400));

      // Enter different confirm PIN: 5678
      await _tapDigits(tester, '5678');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(AppStrings.pinMismatch), findsOneWidget);

      // drain the 800ms reset timer
      await tester.pump(const Duration(milliseconds: 900));
    });

    testWidgets('saves PIN when confirm matches', (tester) async {
      final storage = FakeSecureStorageService();
      await tester.pumpWidget(_buildScreen(storage: storage));
      await tester.pump();

      await _tapDigits(tester, '1234');
      await tester.pump(const Duration(milliseconds: 400));

      await _tapDigits(tester, '1234');
      await tester.pump(const Duration(milliseconds: 200));

      expect(await storage.getPin(), '1234');

      // drain the 700ms navigation delay timer
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('backspace removes last digit from PIN entry', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      await _tapDigits(tester, '123');
      await tester.ensureVisible(find.byIcon(Icons.backspace_outlined));
      await tester.tap(find.byIcon(Icons.backspace_outlined),
          warnIfMissed: false);
      await tester.pump();

      // Back to 2 filled dots — confirm screen should not appear
      expect(find.text(AppStrings.pinSetupTitle), findsOneWidget);
    });

    testWidgets('shows success text after matching PINs', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      await _tapDigits(tester, '4321');
      await tester.pump(const Duration(milliseconds: 400));

      await _tapDigits(tester, '4321');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(AppStrings.pinCreatedSuccess), findsOneWidget);

      // drain the 700ms navigation delay timer
      await tester.pump(const Duration(milliseconds: 800));
    });
  });
}
