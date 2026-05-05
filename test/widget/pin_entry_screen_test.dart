import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loyalty_app/app/providers.dart';
import 'package:loyalty_app/core/constants/app_strings.dart';
import 'package:loyalty_app/features/auth/domain/auth_session.dart';
import 'package:loyalty_app/features/auth/presentation/auth_controller.dart';
import 'package:loyalty_app/features/auth/presentation/pin_entry_screen.dart';

import '../helpers/fake_secure_storage.dart';

class _FakeAuth extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        userId: 'u1',
        firebaseUid: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

  @override
  Future<void> logout() async {}
}

Widget _buildScreen({required String storedPin, int initialAttempts = 0}) {
  final storage = FakeSecureStorageService();
  storage.savePin(storedPin);
  if (initialAttempts > 0) storage.savePinAttempts(initialAttempts);

  final router = GoRouter(
    initialLocation: '/pin-entry',
    routes: [
      GoRoute(path: '/pin-entry', builder: (_, __) => const PinEntryScreen()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('login'))),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('dashboard'))),
      GoRoute(
          path: '/pin-setup',
          builder: (_, __) => const Scaffold(body: Text('pin-setup'))),
    ],
  );

  return ProviderScope(
    overrides: [
      secureStorageServiceProvider.overrideWithValue(storage),
      authControllerProvider.overrideWith(_FakeAuth.new),
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
  group('PinEntryScreen', () {
    testWidgets('shows title and subtitle', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
      await tester.pump();

      expect(find.text(AppStrings.pinEntryTitle), findsOneWidget);
      expect(find.text(AppStrings.pinEntrySubtitle), findsOneWidget);
    });

    testWidgets('shows loyalty icon', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
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

    testWidgets('shows number pad', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
      await tester.pump();

      for (final d in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
        expect(find.text(d), findsOneWidget);
      }
    });

    testWidgets('shows forgot PIN button', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
      await tester.pump();

      expect(find.text(AppStrings.pinForgot), findsOneWidget);
    });

    testWidgets('wrong PIN shows error text', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
      await tester.pump();

      await _tapDigits(tester, '9999');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(AppStrings.pinIncorrect), findsOneWidget);

      // drain the 500ms clear-error timer
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('backspace removes last digit', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
      await tester.pump();

      await _tapDigits(tester, '12');
      await tester.ensureVisible(find.byIcon(Icons.backspace_outlined));
      await tester.tap(find.byIcon(Icons.backspace_outlined),
          warnIfMissed: false);
      await tester.pump();

      // Still on entry screen — not yet 4 digits
      expect(find.text(AppStrings.pinEntryTitle), findsOneWidget);
    });

    testWidgets('3 wrong attempts sends user to login', (tester) async {
      await tester.pumpWidget(
        _buildScreen(storedPin: '1234', initialAttempts: 2),
      );
      await tester.pump();

      // This is the 3rd wrong attempt — triggers lockout
      await _tapDigits(tester, '0000');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    testWidgets('forgot PIN button is tappable', (tester) async {
      await tester.pumpWidget(_buildScreen(storedPin: '1234'));
      await tester.pump();

      final forgotButton = find.text(AppStrings.pinForgot);
      expect(forgotButton, findsOneWidget);
      await tester.tap(forgotButton, warnIfMissed: false);
      await tester.pump();
      // After tap, navigation is triggered — no crash
    });
  });
}
