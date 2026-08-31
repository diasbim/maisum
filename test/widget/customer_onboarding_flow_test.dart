import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/errors/app_exception.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/auth/presentation/otp_verification_screen.dart';

class _FakeCustomerAuthController extends AuthController {
  _FakeCustomerAuthController({
    this.customerDisabled = false,
    this.genericFailure = false,
  });

  final bool customerDisabled;
  final bool genericFailure;
  AuthActor? verifiedActor;

  @override
  Future<AuthSession?> build() async => null;

  @override
  Future<AuthSession> verifyOtp({
    required String phone,
    required String verificationId,
    required String code,
    AuthActor actor = AuthActor.merchant,
  }) async {
    verifiedActor = actor;
    if (customerDisabled) {
      throw const CustomerFeatureDisabledException();
    }
    if (genericFailure) {
      throw Exception('Falha temporária no serviço.');
    }
    return AuthSession(
      userId: 'customer-1',
      firebaseUid: 'customer-1',
      phone: phone,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      actor: actor,
    );
  }
}

void main() {
  testWidgets('verified customer OTP opens customer home', (tester) async {
    final authController = _FakeCustomerAuthController();

    await tester.pumpWidget(_buildFlow(authController));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('otp_input')), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(authController.verifiedActor, AuthActor.customer);
    expect(find.text('customer-home'), findsOneWidget);
  });

  testWidgets('disabled customer feature opens the unavailable screen',
      (tester) async {
    final authController = _FakeCustomerAuthController(customerDisabled: true);

    await tester.pumpWidget(_buildFlow(authController));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('otp_input')), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(authController.verifiedActor, AuthActor.customer);
    expect(find.text('customer-disabled'), findsOneWidget);
  });

  testWidgets('generic customer error does not masquerade as feature disabled',
      (tester) async {
    final authController = _FakeCustomerAuthController(genericFailure: true);

    await tester.pumpWidget(_buildFlow(authController));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('otp_input')), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(authController.verifiedActor, AuthActor.customer);
    expect(find.text('customer-disabled'), findsNothing);
    expect(find.byKey(const Key('otp_input')), findsOneWidget);
  });
}

Widget _buildFlow(_FakeCustomerAuthController authController) {
  final router = GoRouter(
    initialLocation: '/otp',
    routes: [
      GoRoute(
        path: '/otp',
        builder: (_, __) => const OTPVerificationScreen(
          phoneNumber: '+258843262347',
          verificationId: 'test-verification-id',
          actor: AuthActor.customer,
        ),
      ),
      GoRoute(
        path: '/customer/home',
        builder: (_, __) => const Scaffold(body: Text('customer-home')),
      ),
      GoRoute(
        path: '/customer-disabled',
        builder: (_, __) => const Scaffold(body: Text('customer-disabled')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => authController),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
