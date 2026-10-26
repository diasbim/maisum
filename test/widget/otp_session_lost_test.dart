import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/otp_verification_screen.dart';
import 'package:maisum/features/auth/presentation/phone_auth_screen.dart';

/// The screen can outlive the session it depends on: `extra` carries the
/// verification id, is not serialisable, and is gone after a process restart
/// or a deep link. Running the app found the screen rendering six boxes and
/// a ready-looking button over a session that could never accept a code.
Widget _screen({required String verificationId}) {
  final router = GoRouter(
    initialLocation: '/otp',
    routes: [
      GoRoute(
        path: '/otp',
        builder: (_, __) => OTPVerificationScreen(
          phoneNumber: '+258840000001',
          verificationId: verificationId,
          actor: AuthActor.merchant,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('ecrã de telefone')),
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  group('a verification session that is gone', () {
    testWidgets('says so before anything is typed', (tester) async {
      await tester.pumpWidget(_screen(verificationId: ''));
      await tester.pump();

      expect(find.byKey(const Key('otp_session_lost')), findsOneWidget);
      expect(find.textContaining('expirou'), findsWidgets);
      // And names the way out, rather than "tente novamente".
      expect(find.textContaining('Reenviar código'), findsWidgets);
    });

    testWidgets('does not offer a button that cannot work', (tester) async {
      await tester.pumpWidget(_screen(verificationId: ''));
      await tester.pump();

      final button = tester.widget<AuthGradientButton>(
        find.byKey(const Key('verify_button')),
      );
      expect(button.onPressed, isNull, reason: 'disabled, with the reason shown above');
    });

    testWidgets('the resend countdown does not hold the only door shut',
        (tester) async {
      // The countdown exists to stop someone spamming SMS they are waiting
      // for. With no session there is nothing to wait for.
      await tester.pumpWidget(_screen(verificationId: ''));
      await tester.pump();

      expect(find.text('60'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Reenviar código'), findsWidgets);
    });

    testWidgets('a live session shows none of this', (tester) async {
      await tester.pumpWidget(_screen(verificationId: 'verification-abc'));
      await tester.pump();

      expect(find.byKey(const Key('otp_session_lost')), findsNothing);
      final button = tester.widget<AuthGradientButton>(
        find.byKey(const Key('verify_button')),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('reaching /otp with no arguments at all', () {
    testWidgets('explains instead of crashing', (tester) async {
      // The route used to do `state.extra as OtpScreenArgs` unchecked, which
      // threw inside the builder — a crash, not a screen.
      final router = GoRouter(
        initialLocation: '/otp',
        routes: [
          GoRoute(
            path: '/otp',
            builder: (_, state) {
              final args = state.extra;
              if (args is! OtpScreenArgs) return const OtpSessionLostScreen();
              return OTPVerificationScreen(
                phoneNumber: args.phone,
                verificationId: args.verificationId,
                actor: args.actor,
              );
            },
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('ecrã de telefone')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('sessão de verificação expirou'), findsOneWidget);
    });

    testWidgets('one tap leads back to where a code can be asked for',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/otp',
              routes: [
                GoRoute(
                  path: '/otp',
                  builder: (_, __) => const OtpSessionLostScreen(),
                ),
                GoRoute(
                  path: '/login',
                  builder: (_, __) =>
                      const Scaffold(body: Text('ecrã de telefone')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('otp_session_lost_restart')));
      await tester.pumpAndSettle();

      expect(find.text('ecrã de telefone'), findsOneWidget);
    });
  });
}
