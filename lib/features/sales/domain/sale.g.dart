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
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      confirmationStatus: $enumDecodeNullable(
              _$SaleConfirmationStatusEnumMap, json['confirmationStatus']) ??
          SaleConfirmationStatus.pending,
      confirmedPoints: (json['confirmedPoints'] as num?)?.toInt(),
      confirmedAt: json['confirmedAt'] == null
          ? null
          : DateTime.parse(json['confirmedAt'] as String),
      confirmationErrorCode: json['confirmationErrorCode'] as String?,
      loyaltyPolicyVersion: (json['loyaltyPolicyVersion'] as num?)?.toInt(),
      cancellationStatus: $enumDecodeNullable(
              _$SaleCancellationStatusEnumMap, json['cancellationStatus']) ??
          SaleCancellationStatus.active,
      cancelledAt: json['cancelledAt'] == null
          ? null
          : DateTime.parse(json['cancelledAt'] as String),
      cancelledByAppUserId: json['cancelledByAppUserId'] as String?,
      cancellationReason: json['cancellationReason'] as String?,
      replacementSaleId: json['replacementSaleId'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <SaleItem>[],
      synced: json['synced'] as bool? ?? false,
    );

Map<String, dynamic> _$$SaleImplToJson(_$SaleImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customerId': instance.customerId,
      'amount': instance.amount,
      'points': instance.points,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'confirmationStatus':
          _$SaleConfirmationStatusEnumMap[instance.confirmationStatus]!,
      'confirmedPoints': instance.confirmedPoints,
      'confirmedAt': instance.confirmedAt?.toIso8601String(),
      'confirmationErrorCode': instance.confirmationErrorCode,
      'loyaltyPolicyVersion': instance.loyaltyPolicyVersion,
      'cancellationStatus':
          _$SaleCancellationStatusEnumMap[instance.cancellationStatus]!,
      'cancelledAt': instance.cancelledAt?.toIso8601String(),
      'cancelledByAppUserId': instance.cancelledByAppUserId,
      'cancellationReason': instance.cancellationReason,
      'replacementSaleId': instance.replacementSaleId,
      'items': instance.items,
      'synced': instance.synced,
    };

const _$SaleConfirmationStatusEnumMap = {
  SaleConfirmationStatus.pending: 'pending',
  SaleConfirmationStatus.confirmed: 'confirmed',
  SaleConfirmationStatus.rejected: 'rejected',
  SaleConfirmationStatus.baselineRequired: 'baselineRequired',
};

const _$SaleCancellationStatusEnumMap = {
  SaleCancellationStatus.active: 'active',
  SaleCancellationStatus.cancelled: 'cancelled',
};
