// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'redemption.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RedemptionImpl _$$RedemptionImplFromJson(Map<String, dynamic> json) =>
    _$RedemptionImpl(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      rewardId: json['rewardId'] as String,
      pointsSpent: (json['pointsSpent'] as num).toInt(),
      redeemedAt: DateTime.parse(json['redeemedAt'] as String),
      synced: json['synced'] as bool? ?? false,
    );

Map<String, dynamic> _$$RedemptionImplToJson(_$RedemptionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customerId': instance.customerId,
      'rewardId': instance.rewardId,
      'pointsSpent': instance.pointsSpent,
      'redeemedAt': instance.redeemedAt.toIso8601String(),
      'synced': instance.synced,
    };
