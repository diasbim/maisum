import 'package:freezed_annotation/freezed_annotation.dart';

part 'redemption.freezed.dart';
part 'redemption.g.dart';

@freezed
class Redemption with _$Redemption {
  const Redemption._();

  const factory Redemption({
    required String id,
    required String customerId,
    required String rewardId,
    required int pointsSpent,
    required DateTime redeemedAt,
    @Default(false) bool synced,
  }) = _Redemption;

  factory Redemption.fromJson(Map<String, dynamic> json) =>
      _$RedemptionFromJson(json);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'customer_id': customerId,
        'reward_id': rewardId,
        'points_spent': pointsSpent,
        'redeemed_at': redeemedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };
}

Redemption redemptionFromMap(Map<String, dynamic> map) => Redemption(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      rewardId: map['reward_id'] as String,
      pointsSpent: map['points_spent'] as int,
      redeemedAt:
          DateTime.fromMillisecondsSinceEpoch(map['redeemed_at'] as int),
      synced: (map['synced'] as int? ?? 0) == 1,
    );
