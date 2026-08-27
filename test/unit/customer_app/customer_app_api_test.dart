import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/features/customer_app/data/customer_app_api.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';

void main() {
  test('uses PATCH for customer preferences', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = server.first;
    final api = CustomerAppApi(
      JsonApiClient(baseUrl: 'http://${server.address.address}:${server.port}'),
    );
    final call = api.updatePreferences(
      'token',
      const _Preferences().value,
    );
    final incoming = await request;
    expect(incoming.method, 'PATCH');
    expect(await utf8.decoder.bind(incoming).join(),
        contains('marketing_enabled'));
    incoming.response
      ..statusCode = 200
      ..write(jsonEncode({
        'success': true,
        'data': {
          'preferences': {
            'notifications_enabled': true,
            'marketing_enabled': true,
            'deep_links_enabled': true,
          }
        }
      }));
    await incoming.response.close();
    expect((await call).marketingEnabled, isTrue);
    await server.close(force: true);
  });

  test('uses customer-owned endpoints for push token registration and removal',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = CustomerAppApi(
      JsonApiClient(baseUrl: 'http://${server.address.address}:${server.port}'),
    );
    const token = 'a-long-fcm-token-value-1234567890';
    final requests = server.asBroadcastStream();

    final register = api.registerPushToken(
      'bearer-token',
      platform: 'android',
      token: token,
    );
    final registrationRequest = await requests.first;
    expect(registrationRequest.method, 'POST');
    expect(registrationRequest.uri.path, '/customer/push-tokens');
    expect(registrationRequest.headers.value(HttpHeaders.authorizationHeader),
        'Bearer bearer-token');
    expect(await utf8.decoder.bind(registrationRequest).join(),
        jsonEncode({'platform': 'android', 'token': token}));
    registrationRequest.response
      ..statusCode = 201
      ..write(jsonEncode({'success': true, 'data': {}}));
    await registrationRequest.response.close();
    await register;

    final remove = api.removePushToken(
      'bearer-token',
      platform: 'android',
      token: token,
    );
    final removalRequest = await requests.first;
    expect(removalRequest.method, 'POST');
    expect(removalRequest.uri.path, '/customer/push-tokens/remove');
    expect(await utf8.decoder.bind(removalRequest).join(),
        jsonEncode({'platform': 'android', 'token': token}));
    removalRequest.response
      ..statusCode = 200
      ..write(jsonEncode({'success': true, 'data': {}}));
    await removalRequest.response.close();
    await remove;
    await server.close(force: true);
  });
}

class _Preferences {
  const _Preferences();
  CustomerPreferences get value => const CustomerPreferences(
        notificationsEnabled: true,
        marketingEnabled: true,
        deepLinksEnabled: true,
      );
}
