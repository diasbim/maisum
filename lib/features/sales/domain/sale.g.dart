// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SaleImpl _$$SaleImplFromJson(Map<String, dynamic> json) => _$SaleImpl(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      amount: (json['amount'] as num).toDouble(),
      points: (json['points'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      synced: json['synced'] as bool? ?? false,
    );

Map<String, dynamic> _$$SaleImplToJson(_$SaleImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customerId': instance.customerId,
      'amount': instance.amount,
      'points': instance.points,
      'createdAt': instance.createdAt.toIso8601String(),
      'synced': instance.synced,
    };
