import '../../../core/network/json_api_client.dart';
import '../domain/redemption.dart';

class ConfirmedRedemption {
  const ConfirmedRedemption({
    required this.redemption,
    required this.confirmedPoints,
  });

  final Redemption redemption;
  final int confirmedPoints;
}

abstract interface class LoyaltyRedemptionGateway {
  Future<ConfirmedRedemption> redeem({
    required String merchantId,
    required String customerId,
    required String rewardId,
    required int pointsRequired,
    required String idempotencyKey,
    required String bearerToken,
  });
}

class LoyaltyRedemptionApi implements LoyaltyRedemptionGateway {
  const LoyaltyRedemptionApi(this._client);

  final JsonApiClient _client;

  @override
  Future<ConfirmedRedemption> redeem({
    required String merchantId,
    required String customerId,
    required String rewardId,
    required int pointsRequired,
    required String idempotencyKey,
    required String bearerToken,
  }) async {
    final response = await _client.post(
      '/loyalty/redemptions',
      bearerToken: bearerToken,
      body: <String, Object?>{
        'merchant_id': merchantId,
        'customer_id': customerId,
        'reward_id': rewardId,
        'points_required': pointsRequired,
        'idempotency_key': idempotencyKey,
      },
    );
    final data = _asMap(response.data);
    final redemptionData = _asMap(data['redemption']);
    final confirmedPoints = (data['confirmed_points'] as num?)?.toInt();
    if (confirmedPoints == null) {
      throw StateError('Redemption response omitted confirmed_points');
    }

    return ConfirmedRedemption(
      redemption: redemptionFromMap(<String, dynamic>{
        ...redemptionData,
        'synced': 1,
      }),
      confirmedPoints: confirmedPoints,
    );
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('Redemption response did not include object data');
  }
}
