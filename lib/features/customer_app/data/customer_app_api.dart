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

  Future<CustomerRedemptionReceipt> redeem(
    String token, {
    required String rewardId,
    required String idempotencyKey,
  }) async =>
      CustomerRedemptionReceipt.fromJson(
        await _post('/customer/redemptions', token, {
          'reward_id': rewardId,
          'idempotency_key': idempotencyKey,
        }),
      );

  Future<CustomerRedemptionReceipt> redemptionStatus(
    String token,
    String redemptionId,
  ) async =>
      CustomerRedemptionReceipt.fromJson(
        await _get(
          '/customer/redemptions/${Uri.encodeComponent(redemptionId)}',
          token,
        ),
      );

  Future<CustomerRedemptionReceipt> reissueRedemption(
    String token, {
    required String redemptionId,
    required String idempotencyKey,
  }) async =>
      CustomerRedemptionReceipt.fromJson(
        await _post(
          '/customer/redemptions/${Uri.encodeComponent(redemptionId)}/reissue',
          token,
          {'idempotency_key': idempotencyKey},
        ),
      );

  Future<MerchantRedemptionPreview> resolveMerchantRedemption(
    String token,
    String redemptionCode,
  ) async =>
      MerchantRedemptionPreview.fromJson(
        await _post('/merchant/redemptions/resolve', token, {
          'redemption_code': redemptionCode,
        }),
      );

  Future<MerchantRedemptionPreview> consumeMerchantRedemption(
    String token, {
    required String redemptionCode,
    required String idempotencyKey,
  }) async =>
      MerchantRedemptionPreview.fromJson(
        await _post('/merchant/redemptions/consume', token, {
          'redemption_code': redemptionCode,
          'idempotency_key': idempotencyKey,
        }),
      );

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

  /// Customer app: links a physical NFC card (already read and normalized,
  /// see [NfcCardUidUtils]) to the authenticated customer's own account.
  Future<Map<String, dynamic>> linkCustomerNfcCard(
    String token,
    String cardUid,
  ) =>
      _post('/customer/nfc-cards/link', token, {'card_uid': cardUid});

  /// Customer app: revokes a previously self-linked NFC card.
  Future<Map<String, dynamic>> revokeCustomerNfcCard(
    String token,
    String cardUid,
  ) =>
      _post('/customer/nfc-cards/revoke', token, {'card_uid': cardUid});

  /// Business owner app: assisted association of a physical NFC card to one
  /// of the merchant's customers (existing or newly created).
  Future<Map<String, dynamic>> linkMerchantNfcCard(
    String token, {
    required String cardUid,
    String? customerId,
    String? phone,
    String? customerName,
    bool createCustomerIfMissing = true,
  }) =>
      _post('/merchant/customer-nfc/link', token, {
        'card_uid': cardUid,
        if (customerId != null) 'customer_id': customerId,
        if (phone != null) 'phone': phone,
        if (customerName != null) 'customer_name': customerName,
        'create_customer_if_missing': createCustomerIfMissing,
      });

  /// Business owner app: resolves a tapped NFC card to the merchant's
  /// customer, to process a sale or attribute a benefit.
  Future<Map<String, dynamic>> resolveMerchantNfcCard(
    String token, {
    required String cardUid,
    bool createCustomerIfMissing = true,
  }) =>
      _post('/merchant/customer-nfc/resolve', token, {
        'card_uid': cardUid,
        'create_customer_if_missing': createCustomerIfMissing,
      });

  /// Business owner app: revokes an NFC card linked to one of the
  /// merchant's own customers (e.g. lost/stolen card).
  Future<Map<String, dynamic>> revokeMerchantNfcCard(
    String token,
    String cardUid,
  ) =>
      _post('/merchant/customer-nfc/revoke', token, {'card_uid': cardUid});

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
