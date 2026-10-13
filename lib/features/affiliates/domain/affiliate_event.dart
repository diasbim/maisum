import 'affiliate_serialization.dart';

enum AffiliateEventType {
  affiliateCreated('AFFILIATE_CREATED'),
  affiliateCodeCreated('AFFILIATE_CODE_CREATED'),
  referralCodeValidated('REFERRAL_CODE_VALIDATED'),
  referralAttributed('REFERRAL_ATTRIBUTED'),
  referralRejected('REFERRAL_REJECTED'),
  affiliateRewardCreated('AFFILIATE_REWARD_CREATED'),
  affiliateRewardApproved('AFFILIATE_REWARD_APPROVED'),
  affiliateRewardCancelled('AFFILIATE_REWARD_CANCELLED'),
  referredCustomerReturned('REFERRED_CUSTOMER_RETURNED');

  const AffiliateEventType(this.storageValue);

  final String storageValue;

  static AffiliateEventType fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'AFFILIATE_CREATED':
        return AffiliateEventType.affiliateCreated;
      case 'AFFILIATE_CODE_CREATED':
        return AffiliateEventType.affiliateCodeCreated;
      case 'REFERRAL_CODE_VALIDATED':
        return AffiliateEventType.referralCodeValidated;
      case 'REFERRAL_ATTRIBUTED':
        return AffiliateEventType.referralAttributed;
      case 'REFERRAL_REJECTED':
        return AffiliateEventType.referralRejected;
      case 'AFFILIATE_REWARD_CREATED':
        return AffiliateEventType.affiliateRewardCreated;
      case 'AFFILIATE_REWARD_APPROVED':
        return AffiliateEventType.affiliateRewardApproved;
      case 'AFFILIATE_REWARD_CANCELLED':
        return AffiliateEventType.affiliateRewardCancelled;
      case 'REFERRED_CUSTOMER_RETURNED':
        return AffiliateEventType.referredCustomerReturned;
    }
    throw FormatException('Invalid AffiliateEventType value: $value');
  }
}

enum AffiliateFraudSignalSeverity {
  low('LOW'),
  medium('MEDIUM'),
  high('HIGH');

  const AffiliateFraudSignalSeverity(this.storageValue);

  final String storageValue;

  static AffiliateFraudSignalSeverity fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'LOW':
        return AffiliateFraudSignalSeverity.low;
      case 'MEDIUM':
        return AffiliateFraudSignalSeverity.medium;
      case 'HIGH':
        return AffiliateFraudSignalSeverity.high;
    }
    throw FormatException('Invalid AffiliateFraudSignalSeverity value: $value');
  }
}

enum AffiliateFraudSignalType {
  offlineCodeRejected('OFFLINE_CODE_REJECTED'),
  validationBurst('VALIDATION_BURST'),
  selfReferralAttempt('SELF_REFERRAL_ATTEMPT'),
  duplicateAttributionAttempt('DUPLICATE_ATTRIBUTION_ATTEMPT');

  const AffiliateFraudSignalType(this.storageValue);

  final String storageValue;

  static AffiliateFraudSignalType fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'OFFLINE_CODE_REJECTED':
        return AffiliateFraudSignalType.offlineCodeRejected;
      case 'VALIDATION_BURST':
        return AffiliateFraudSignalType.validationBurst;
      case 'SELF_REFERRAL_ATTEMPT':
        return AffiliateFraudSignalType.selfReferralAttempt;
      case 'DUPLICATE_ATTRIBUTION_ATTEMPT':
        return AffiliateFraudSignalType.duplicateAttributionAttempt;
    }
    throw FormatException('Invalid AffiliateFraudSignalType value: $value');
  }
}

class AffiliateEvent {
  const AffiliateEvent({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.eventType,
    required this.occurredAt,
    required this.createdAt,
    this.attributionId,
    this.rewardId,
    this.saleId,
    this.customerId,
    this.payload,
    this.schemaVersion = 1,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final AffiliateEventType eventType;
  final String? attributionId;
  final String? rewardId;
  final String? saleId;
  final String? customerId;
  final Map<String, dynamic>? payload;
  final DateTime occurredAt;
  final DateTime createdAt;
  final int schemaVersion;

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'event_type': eventType.storageValue,
        'attribution_id': attributionId,
        'reward_id': rewardId,
        'sale_id': saleId,
        'customer_id': customerId,
        'payload': encodeNullableMap(payload),
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'schema_version': schemaVersion,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'event_type': eventType.storageValue,
        'attribution_id': attributionId,
        'reward_id': rewardId,
        'sale_id': saleId,
        'customer_id': customerId,
        'payload': payload,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'schema_version': schemaVersion,
      };

  factory AffiliateEvent.fromMap(Map<String, dynamic> map) {
    return AffiliateEvent(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      eventType: readRequiredEnum(
        map,
        ['event_type', 'eventType'],
        AffiliateEventType.fromStorage,
      ),
      attributionId: readNullableString(
        map,
        ['attribution_id', 'attributionId'],
      ),
      rewardId: readNullableString(map, ['reward_id', 'rewardId']),
      saleId: readNullableString(map, ['sale_id', 'saleId']),
      customerId: readNullableString(map, ['customer_id', 'customerId']),
      payload: readNullableMap(map, ['payload']),
      occurredAt: readRequiredDateTime(map, ['occurred_at', 'occurredAt']),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
      schemaVersion:
          readNullableInt(map, ['schema_version', 'schemaVersion']) ?? 1,
    );
  }

  factory AffiliateEvent.fromJson(Map<String, dynamic> json) =>
      AffiliateEvent.fromMap(json);
}

class AffiliateFraudSignal {
  const AffiliateFraudSignal({
    required this.id,
    required this.merchantId,
    required this.signalType,
    required this.severity,
    required this.createdAt,
    this.affiliateId,
    this.attributionId,
    this.rewardId,
    this.saleId,
    this.customerId,
    this.metadata,
  });

  final String id;
  final String merchantId;
  final String? affiliateId;
  final AffiliateFraudSignalType signalType;
  final AffiliateFraudSignalSeverity severity;
  final String? attributionId;
  final String? rewardId;
  final String? saleId;
  final String? customerId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'signal_type': signalType.storageValue,
        'severity': severity.storageValue,
        'attribution_id': attributionId,
        'reward_id': rewardId,
        'sale_id': saleId,
        'customer_id': customerId,
        'metadata': encodeNullableMap(metadata),
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'signal_type': signalType.storageValue,
        'severity': severity.storageValue,
        'attribution_id': attributionId,
        'reward_id': rewardId,
        'sale_id': saleId,
        'customer_id': customerId,
        'metadata': metadata,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory AffiliateFraudSignal.fromMap(Map<String, dynamic> map) {
    return AffiliateFraudSignal(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readNullableString(map, ['affiliate_id', 'affiliateId']),
      signalType: readRequiredEnum(
        map,
        ['signal_type', 'signalType'],
        AffiliateFraudSignalType.fromStorage,
      ),
      severity: readRequiredEnum(
        map,
        ['severity'],
        AffiliateFraudSignalSeverity.fromStorage,
      ),
      attributionId: readNullableString(
        map,
        ['attribution_id', 'attributionId'],
      ),
      rewardId: readNullableString(map, ['reward_id', 'rewardId']),
      saleId: readNullableString(map, ['sale_id', 'saleId']),
      customerId: readNullableString(map, ['customer_id', 'customerId']),
      metadata: readNullableMap(map, ['metadata']),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
    );
  }

  factory AffiliateFraudSignal.fromJson(Map<String, dynamic> json) =>
      AffiliateFraudSignal.fromMap(json);
}
