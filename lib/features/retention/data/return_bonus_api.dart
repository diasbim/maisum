import '../../../core/network/json_api_client.dart';
import '../domain/return_bonus.dart';

abstract interface class ReturnBonusGateway {
  Future<ReturnBonus> redeem({
    required String bonusId,
    required String customerId,
    String? redemptionSaleId,
    required String bearerToken,
  });
}

class ReturnBonusApi implements ReturnBonusGateway {
  const ReturnBonusApi(this._client);

  final JsonApiClient _client;

  @override
  Future<ReturnBonus> redeem({
    required String bonusId,
    required String customerId,
    String? redemptionSaleId,
    required String bearerToken,
  }) async {
    final response = await _client.post(
      '/return-bonuses/$bonusId/redeem',
      bearerToken: bearerToken,
      body: <String, Object?>{
        'customer_id': customerId,
        if (redemptionSaleId != null) 'redemption_sale_id': redemptionSaleId,
      },
    );
    final data = _asMap(response.data);
    return ReturnBonus.fromMap(data);
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('Return bonus redeem response did not include object data');
  }
}
