const _customerFixedRoutes = <String>{
  '/customer/home',
  '/customer/rewards',
  '/customer/activity',
  '/customer/businesses',
  '/customer/profile',
  '/customer/qr',
  '/customer/preferences',
};

final _customerIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

String? parseCustomerDeepLink(Uri uri) {
  if (uri.scheme != 'maisum' ||
      uri.host != 'app' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 0 ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  return sanitizeCustomerRoutePath(uri.pathSegments);
}

String? parseCustomerPushRoute(Map<String, dynamic> data) {
  final route = data['customer_route'];
  if (route is! String || route.isEmpty) return null;

  final uri = Uri.tryParse(route);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  return sanitizeCustomerRoutePath(uri.pathSegments);
}

String? sanitizeCustomerRoutePath(List<String> segments) {
  if (segments.isEmpty || segments.any((segment) => segment.isEmpty)) {
    return null;
  }

  final route = '/${segments.join('/')}';
  if (_customerFixedRoutes.contains(route)) return route;
  if (segments.length == 3 &&
      segments.first == 'customer' &&
      (segments[1] == 'business' || segments[1] == 'redeem') &&
      _customerIdPattern.hasMatch(segments[2])) {
    return route;
  }
  return null;
}
