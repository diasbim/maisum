// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SyncItemImpl _$$SyncItemImplFromJson(Map<String, dynamic> json) =>
    _$SyncItemImpl(
      id: json['id'] as String,
      operation: json['operation'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      payload: json['payload'] as String,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$SyncItemImplToJson(_$SyncItemImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'operation': instance.operation,
      'entityType': instance.entityType,
      'entityId': instance.entityId,
      'payload': instance.payload,
      'retryCount': instance.retryCount,
      'status': instance.status,
      'createdAt': instance.createdAt.toIso8601String(),
    };
