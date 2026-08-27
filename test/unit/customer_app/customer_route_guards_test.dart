import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/customer_app/presentation/customer_route_guards.dart';

AuthSession _session(AuthActor actor) => AuthSession(
      userId: 'u1',
      phone: '+258841234567',
      expiresAt: DateTime(2030),
      actor: actor,
    );

void main() {
  test('customer route redirects an anonymous user to customer login', () {
    expect(
      resolveCustomerActorRedirect(location: '/customer/home', session: null),
      '/customer-login',
    );
  });

  test('merchant must explicitly choose the customer flow', () {
    expect(
      resolveCustomerActorRedirect(
        location: '/customer/rewards',
        session: _session(AuthActor.merchant),
      ),
      '/customer-login',
    );
  });

  test('customer actor cannot enter merchant or admin routes', () {
    expect(
      resolveCustomerActorRedirect(
          location: '/dashboard', session: _session(AuthActor.customer)),
      '/customer/home',
    );
    expect(
      resolveCustomerActorRedirect(
          location: '/admin', session: _session(AuthActor.customer)),
      '/customer/home',
    );
  });
}
