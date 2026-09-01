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

  test('uses merchant redemption resolve and consume contracts', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = CustomerAppApi(
      JsonApiClient(baseUrl: 'http://${server.address.address}:${server.port}'),
    );
    final requests = server.asBroadcastStream();
    const code = 'r1_abcdefghijklmnopqrstuvwx';

    final resolve = api.resolveMerchantRedemption('token', code);
    final resolveRequest = await requests.first;
    expect(resolveRequest.method, 'POST');
    expect(resolveRequest.uri.path, '/merchant/redemptions/resolve');
    expect(
      jsonDecode(await utf8.decoder.bind(resolveRequest).join()),
      {'redemption_code': code},
    );
    await _writeRedemptionResponse(
      resolveRequest.response,
      status: 'PENDING',
    );
    expect((await resolve).receipt.status, CustomerRedemptionStatus.pending);

    final consume = api.consumeMerchantRedemption(
      'token',
      redemptionCode: code,
      idempotencyKey: 'operation_123',
    );
    final consumeRequest = await requests.first;
    expect(consumeRequest.method, 'POST');
    expect(consumeRequest.uri.path, '/merchant/redemptions/consume');
    expect(
      jsonDecode(await utf8.decoder.bind(consumeRequest).join()),
      {
        'redemption_code': code,
        'idempotency_key': 'operation_123',
      },
    );
    await _writeRedemptionResponse(
      consumeRequest.response,
      status: 'CONSUMED',
    );
    expect((await consume).receipt.status, CustomerRedemptionStatus.consumed);

    await server.close(force: true);
  });
}

Future<void> _writeRedemptionResponse(
  HttpResponse response, {
  required String status,
}) async {
  response
    ..statusCode = 200
    ..write(jsonEncode({
      'success': true,
      'data': {
        'business_id': 'm1',
        'business_name': 'Café Central',
        'redemption_id': 'redemption-1',
        'reward_id': 'reward-1',
        'redemption_code': 'r1_abcdefghijklmnopqrstuvwx',
        'points_spent': 500,
        'confirmed_points': 250,
        'redeemed_at': 1000,
        'redemption_code_expires_at': 901000,
        'fulfillment_status': status,
        'consumed_at': status == 'CONSUMED' ? 2000 : null,
        'customer': {
          'customer_id': 'customer-1',
          'name': 'Ana Mucavele',
          'phone': '841234567',
        },
        'reward': {
          'reward_id': 'reward-1',
          'name': 'Café grátis',
        },
      },
    }));
  await response.close();
}

class _Preferences {
  const _Preferences();
  CustomerPreferences get value => const CustomerPreferences(
        notificationsEnabled: true,
        marketingEnabled: true,
        deepLinksEnabled: true,
      );
}
