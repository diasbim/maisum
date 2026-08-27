import '../../auth/domain/auth_session.dart';

bool isCustomerRoute(String location) =>
    location == '/customer' || location.startsWith('/customer/');

bool isCustomerLoginRoute(String location) =>
    location == '/customer-login' || location.startsWith('/customer-login/');

String? resolveCustomerActorRedirect({
  required String location,
  required AuthSession? session,
}) {
  final customerRoute = isCustomerRoute(location);
  final customerLogin = isCustomerLoginRoute(location);
  if (session == null) return customerRoute ? '/customer-login' : null;
  if (session.isCustomer) {
    if (customerLogin) return '/customer/home';
    return customerRoute ? null : '/customer/home';
  }
  if (customerRoute) return '/customer-login';
  return null;
}
