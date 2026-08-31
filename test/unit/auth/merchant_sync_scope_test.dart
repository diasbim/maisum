import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession?> build() async => _session;
}

AuthSession _session({
  required AuthActor actor,
  String? merchantId,
}) =>
    AuthSession(
      userId: 'firebase-user',
      phone: '+258841234567',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      firebaseUid: 'firebase-user',
      merchantId: merchantId,
      actor: actor,
    );

void main() {
  test('customer session never exposes a business UID for merchant sync',
      () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(_session(actor: AuthActor.customer)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);

    expect(container.read(businessUidProvider), isNull);
  });

  test('merchant session exposes its merchant ID for merchant sync', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            _session(actor: AuthActor.merchant, merchantId: 'merchant-1'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);

    expect(container.read(businessUidProvider), 'merchant-1');
  });
}
