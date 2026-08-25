// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CustomerImpl _$$CustomerImplFromJson(Map<String, dynamic> json) =>
    _$CustomerImpl(
      id: json['id'] as String,
      merchantId: json['merchantId'] as String?,
      canonicalCustomerId: json['canonicalCustomerId'] as String?,
      name: json['name'] as String,
      phone: json['phone'] as String,
      totalPoints: (json['totalPoints'] as num?)?.toInt() ?? 0,
      confirmedPoints: (json['confirmedPoints'] as num?)?.toInt(),
      accountState: $enumDecodeNullable(
              _$CustomerAccountStateEnumMap, json['accountState']) ??
          CustomerAccountState.unclaimed,
      relationshipStatus: $enumDecodeNullable(
              _$BusinessCustomerStatusEnumMap, json['relationshipStatus']) ??
          BusinessCustomerStatus.active,
      lifecycleStage: $enumDecodeNullable(
              _$CustomerLifecycleStageEnumMap, json['lifecycleStage']) ??
          CustomerLifecycleStage.newCustomer,
      retentionStatus: $enumDecodeNullable(
              _$CustomerRetentionStatusEnumMap, json['retentionStatus']) ??
          CustomerRetentionStatus.healthy,
      firstVisitAt: json['firstVisitAt'] == null
          ? null
          : DateTime.parse(json['firstVisitAt'] as String),
      lastVisitAt: json['lastVisitAt'] == null
          ? null
          : DateTime.parse(json['lastVisitAt'] as String),
      totalVisits: (json['totalVisits'] as num?)?.toInt() ?? 0,
      totalSpent: (json['totalSpent'] as num?)?.toDouble() ?? 0,
      averageSpend: (json['averageSpend'] as num?)?.toDouble() ?? 0,
      averageVisitIntervalDays:
          (json['averageVisitIntervalDays'] as num?)?.toInt(),
      marketingConsentStatus: $enumDecodeNullable(
              _$CustomerConsentStatusEnumMap, json['marketingConsentStatus']) ??
          CustomerConsentStatus.unknown,
      whatsappConsentStatus: $enumDecodeNullable(
              _$CustomerConsentStatusEnumMap, json['whatsappConsentStatus']) ??
          CustomerConsentStatus.unknown,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      synced: json['synced'] as bool? ?? false,
    );

Map<String, dynamic> _$$CustomerImplToJson(_$CustomerImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'merchantId': instance.merchantId,
      'canonicalCustomerId': instance.canonicalCustomerId,
      'name': instance.name,
      'phone': instance.phone,
      'totalPoints': instance.totalPoints,
      'confirmedPoints': instance.confirmedPoints,
      'accountState': _$CustomerAccountStateEnumMap[instance.accountState]!,
      'relationshipStatus':
          _$BusinessCustomerStatusEnumMap[instance.relationshipStatus]!,
      'lifecycleStage':
          _$CustomerLifecycleStageEnumMap[instance.lifecycleStage]!,
      'retentionStatus':
          _$CustomerRetentionStatusEnumMap[instance.retentionStatus]!,
      'firstVisitAt': instance.firstVisitAt?.toIso8601String(),
      'lastVisitAt': instance.lastVisitAt?.toIso8601String(),
      'totalVisits': instance.totalVisits,
      'totalSpent': instance.totalSpent,
      'averageSpend': instance.averageSpend,
      'averageVisitIntervalDays': instance.averageVisitIntervalDays,
      'marketingConsentStatus':
          _$CustomerConsentStatusEnumMap[instance.marketingConsentStatus]!,
      'whatsappConsentStatus':
          _$CustomerConsentStatusEnumMap[instance.whatsappConsentStatus]!,
      'schemaVersion': instance.schemaVersion,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'synced': instance.synced,
    };

const _$CustomerAccountStateEnumMap = {
  CustomerAccountState.unclaimed: 'unclaimed',
  CustomerAccountState.claimed: 'claimed',
  CustomerAccountState.blocked: 'blocked',
  CustomerAccountState.deleted: 'deleted',
};

const _$BusinessCustomerStatusEnumMap = {
  BusinessCustomerStatus.active: 'active',
  BusinessCustomerStatus.blocked: 'blocked',
  BusinessCustomerStatus.archived: 'archived',
};

const _$CustomerLifecycleStageEnumMap = {
  CustomerLifecycleStage.newCustomer: 'newCustomer',
  CustomerLifecycleStage.active: 'active',
  CustomerLifecycleStage.returning: 'returning',
  CustomerLifecycleStage.regular: 'regular',
  CustomerLifecycleStage.loyal: 'loyal',
  CustomerLifecycleStage.vip: 'vip',
  CustomerLifecycleStage.advocate: 'advocate',
};

const _$CustomerRetentionStatusEnumMap = {
  CustomerRetentionStatus.healthy: 'healthy',
  CustomerRetentionStatus.atRisk: 'atRisk',
  CustomerRetentionStatus.inactive: 'inactive',
  CustomerRetentionStatus.lost: 'lost',
};

const _$CustomerConsentStatusEnumMap = {
  CustomerConsentStatus.unknown: 'unknown',
  CustomerConsentStatus.granted: 'granted',
  CustomerConsentStatus.denied: 'denied',
  CustomerConsentStatus.revoked: 'revoked',
};
