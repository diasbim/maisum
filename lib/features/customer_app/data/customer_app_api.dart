import '../../../core/network/json_api_client.dart';
import '../domain/customer_models.dart';

class CustomerAppApi {
  CustomerAppApi(this._client);
  final JsonApiClient _client;

  Future<CustomerSessionDto> session(String token) async =>
      CustomerSessionDto.fromJson(await _get('/customer/session', token));

  Future<Map<String, dynamic>> home(String token) =>
      _get('/customer/home', token);
  Future<Map<String, dynamic>> businesses(String token) =>
      _get('/customer/businesses', token);
  Future<Map<String, dynamic>> business(String token, String businessId) =>
      _get('/customer/businesses/${Uri.encodeComponent(businessId)}', token);
  Future<Map<String, dynamic>> rewards(String token) =>
      _get('/customer/rewards', token);
  Future<Map<String, dynamic>> activity(String token) =>
      _get('/customer/activity', token);
  Future<Map<String, dynamic>> profile(String token) =>
      _get('/customer/profile', token);
  Future<Map<String, dynamic>> notifications(String token) =>
      _get('/customer/notifications', token);
  Future<Map<String, dynamic>> deepLinks(String token) =>
      _get('/customer/deep-links', token);
  Future<Map<String, dynamic>> qr(String token) => _get('/customer/qr', token);

  Future<CustomerPreferences> updatePreferences(
    String token,
    CustomerPreferences preferences,
  ) async {
    final response = await _client.patch(
      '/customer/preferences',
      bearerToken: token,
      body: preferences.toJson(),
    );
    if (!response.success || response.data is! Map) {
      throw StateError(
          response.message ?? 'Não foi possível atualizar preferências.');
    }
    final data = (response.data as Map).cast<String, dynamic>();
    return CustomerPreferences.fromJson(
      (data['preferences'] as Map?)?.cast<String, dynamic>() ?? data,
    );
  }

  Future<Map<String, dynamic>> redeem(
    String token, {
    required String rewardId,
    required String idempotencyKey,
  }) =>
      _post('/customer/redemptions', token, {
        'reward_id': rewardId,
        'idempotency_key': idempotencyKey,
      });

  Future<void> event(String token, String eventType) async {
    await _post('/customer/events', token, {'event_type': eventType});
  }

  Future<void> registerPushToken(
    String bearerToken, {
    required String platform,
    required String token,
  }) async {
    await _post('/customer/push-tokens', bearerToken, {
      'platform': platform,
      'token': token,
    });
  }

  Future<void> removePushToken(
    String bearerToken, {
    required String platform,
    required String token,
  }) async {
    await _post('/customer/push-tokens/remove', bearerToken, {
      'platform': platform,
      'token': token,
    });
  }

  Future<Map<String, dynamic>> resolveMerchantQr(String token, String value) =>
      _post('/merchant/customer-qr/resolve', token, {'token': value});

  Future<Map<String, dynamic>> _get(String path, String token) async {
    final response = await _client.get(path, bearerToken: token);
    return _mapResponse(response.success, response.data, response.message);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(path, bearerToken: token, body: body);
    return _mapResponse(response.success, response.data, response.message);
  }

  Map<String, dynamic> _mapResponse(
      bool success, dynamic data, String? message) {
    if (!success || data is! Map) {
      throw StateError(message ?? 'Resposta inválida do serviço do cliente.');
    }
    return data.cast<String, dynamic>();
  }
}
