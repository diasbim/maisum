// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AuthSessionImpl _$$AuthSessionImplFromJson(Map<String, dynamic> json) =>
    _$AuthSessionImpl(
      userId: json['userId'] as String,
      phone: json['phone'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      token: json['token'] as String? ?? '',
      firebaseUid: json['firebaseUid'] as String?,
    );

Map<String, dynamic> _$$AuthSessionImplToJson(_$AuthSessionImpl instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'phone': instance.phone,
      'expiresAt': instance.expiresAt.toIso8601String(),
      'token': instance.token,
      'firebaseUid': instance.firebaseUid,
    };
