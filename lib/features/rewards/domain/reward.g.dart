// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RewardImpl _$$RewardImplFromJson(Map<String, dynamic> json) => _$RewardImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      pointsRequired: (json['pointsRequired'] as num).toInt(),
      description: json['description'] as String?,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      synced: json['synced'] as bool? ?? false,
    );

Map<String, dynamic> _$$RewardImplToJson(_$RewardImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'pointsRequired': instance.pointsRequired,
      'description': instance.description,
      'active': instance.active,
      'createdAt': instance.createdAt.toIso8601String(),
      'synced': instance.synced,
    };
