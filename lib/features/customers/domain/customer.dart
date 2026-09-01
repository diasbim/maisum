import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

enum CustomerAccountState { unclaimed, claimed, blocked, deleted }

enum BusinessCustomerStatus { active, blocked, archived }

enum CustomerLifecycleStage {
  newCustomer,
  active,
  returning,
  regular,
  loyal,
  vip,
  advocate,
}

enum CustomerRetentionStatus { healthy, atRisk, inactive, lost }

enum CustomerConsentStatus { unknown, granted, denied, revoked }

extension CustomerAccountStateStorage on CustomerAccountState {
  String get storageValue => switch (this) {
        CustomerAccountState.unclaimed => 'UNCLAIMED',
        CustomerAccountState.claimed => 'CLAIMED',
        CustomerAccountState.blocked => 'BLOCKED',
        CustomerAccountState.deleted => 'DELETED',
      };
}

extension BusinessCustomerStatusStorage on BusinessCustomerStatus {
  String get storageValue => name.toUpperCase();
}

extension CustomerLifecycleStageStorage on CustomerLifecycleStage {
  String get storageValue => switch (this) {
        CustomerLifecycleStage.newCustomer => 'NEW',
        CustomerLifecycleStage.active => 'ACTIVE',
        CustomerLifecycleStage.returning => 'RETURNING',
        CustomerLifecycleStage.regular => 'REGULAR',
        CustomerLifecycleStage.loyal => 'LOYAL',
        CustomerLifecycleStage.vip => 'VIP',
        CustomerLifecycleStage.advocate => 'ADVOCATE',
      };
}

extension CustomerRetentionStatusStorage on CustomerRetentionStatus {
  String get storageValue => switch (this) {
        CustomerRetentionStatus.healthy => 'HEALTHY',
        CustomerRetentionStatus.atRisk => 'AT_RISK',
        CustomerRetentionStatus.inactive => 'INACTIVE',
        CustomerRetentionStatus.lost => 'LOST',
      };
}

extension CustomerConsentStatusStorage on CustomerConsentStatus {
  String get storageValue => name.toUpperCase();
}

@freezed
class Customer with _$Customer {
  const Customer._();

  const factory Customer({
    required String id,
    String? merchantId,
    String? canonicalCustomerId,
    required String name,
    required String phone,
    @Default(0) int totalPoints,
    int? confirmedPoints,
    @Default(CustomerAccountState.unclaimed) CustomerAccountState accountState,
    @Default(BusinessCustomerStatus.active)
    BusinessCustomerStatus relationshipStatus,
    @Default(CustomerLifecycleStage.newCustomer)
    CustomerLifecycleStage lifecycleStage,
    @Default(CustomerRetentionStatus.healthy)
    CustomerRetentionStatus retentionStatus,
    DateTime? firstVisitAt,
    DateTime? lastVisitAt,
    @Default(0) int totalVisits,
    @Default(0) double totalSpent,
    @Default(0) double averageSpend,
    int? averageVisitIntervalDays,
    @Default(CustomerConsentStatus.unknown)
    CustomerConsentStatus marketingConsentStatus,
    @Default(CustomerConsentStatus.unknown)
    CustomerConsentStatus whatsappConsentStatus,
    @Default(1) int schemaVersion,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? archivedAt,
    String? archivedByAppUserId,
    String? nfcCardUid,
    @Default(false) bool synced,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);

  bool get isArchived => archivedAt != null;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'canonical_customer_id': canonicalCustomerId,
        'name': name,
        'phone': phone,
        'total_points': totalPoints,
        'confirmed_points': confirmedPoints,
        'account_state': accountState.storageValue,
        'relationship_status': relationshipStatus.storageValue,
        'lifecycle_stage': lifecycleStage.storageValue,
        'retention_status': retentionStatus.storageValue,
        'first_visit_at': firstVisitAt?.millisecondsSinceEpoch,
        'last_visit_at': lastVisitAt?.millisecondsSinceEpoch,
        'total_visits': totalVisits,
        'total_spent': totalSpent,
        'average_spend': averageSpend,
        'average_visit_interval_days': averageVisitIntervalDays,
        'marketing_consent_status': marketingConsentStatus.storageValue,
        'whatsapp_consent_status': whatsappConsentStatus.storageValue,
        'schema_version': schemaVersion,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'archived_at': archivedAt?.millisecondsSinceEpoch,
        'archived_by_app_user_id': archivedByAppUserId,
        'nfc_card_uid': nfcCardUid,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toClientSyncMap() => {
        'id': id,
        'merchant_id': merchantId,
        'name': name,
        'phone': phone,
        'total_points': totalPoints,
        'marketing_consent_status': marketingConsentStatus.storageValue,
        'whatsapp_consent_status': whatsappConsentStatus.storageValue,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };
}

Customer customerFromMap(Map<String, dynamic> map) => Customer(
      id: map['id'] as String,
      merchantId: map['merchant_id'] as String?,
      canonicalCustomerId: map['canonical_customer_id'] as String?,
      name: map['name'] as String,
      phone: map['phone'] as String,
      totalPoints: map['total_points'] as int? ?? 0,
      confirmedPoints: (map['confirmed_points'] as num?)?.toInt(),
      accountState: _accountStateFromStorage(map['account_state']),
      relationshipStatus:
          _relationshipStatusFromStorage(map['relationship_status']),
      lifecycleStage: _lifecycleStageFromStorage(map['lifecycle_stage']),
      retentionStatus: _retentionStatusFromStorage(map['retention_status']),
      firstVisitAt: _dateFromStorage(map['first_visit_at']),
      lastVisitAt: _dateFromStorage(map['last_visit_at']),
      totalVisits: (map['total_visits'] as num?)?.toInt() ?? 0,
      totalSpent: (map['total_spent'] as num?)?.toDouble() ?? 0,
      averageSpend: (map['average_spend'] as num?)?.toDouble() ?? 0,
      averageVisitIntervalDays:
          (map['average_visit_interval_days'] as num?)?.toInt(),
      marketingConsentStatus:
          _consentStatusFromStorage(map['marketing_consent_status']),
      whatsappConsentStatus:
          _consentStatusFromStorage(map['whatsapp_consent_status']),
      schemaVersion: (map['schema_version'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      archivedAt: _dateFromStorage(map['archived_at']),
      archivedByAppUserId: map['archived_by_app_user_id'] as String?,
      nfcCardUid: map['nfc_card_uid'] as String?,
      synced: (map['synced'] as int? ?? 0) == 1,
    );

DateTime? _dateFromStorage(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

CustomerAccountState _accountStateFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'CLAIMED' => CustomerAccountState.claimed,
    'BLOCKED' => CustomerAccountState.blocked,
    'DELETED' => CustomerAccountState.deleted,
    _ => CustomerAccountState.unclaimed,
  };
}

BusinessCustomerStatus _relationshipStatusFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'BLOCKED' => BusinessCustomerStatus.blocked,
    'ARCHIVED' => BusinessCustomerStatus.archived,
    _ => BusinessCustomerStatus.active,
  };
}

CustomerLifecycleStage _lifecycleStageFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'ACTIVE' => CustomerLifecycleStage.active,
    'RETURNING' => CustomerLifecycleStage.returning,
    'REGULAR' => CustomerLifecycleStage.regular,
    'LOYAL' => CustomerLifecycleStage.loyal,
    'VIP' => CustomerLifecycleStage.vip,
    'ADVOCATE' => CustomerLifecycleStage.advocate,
    _ => CustomerLifecycleStage.newCustomer,
  };
}

CustomerRetentionStatus _retentionStatusFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'AT_RISK' => CustomerRetentionStatus.atRisk,
    'INACTIVE' => CustomerRetentionStatus.inactive,
    'LOST' => CustomerRetentionStatus.lost,
    _ => CustomerRetentionStatus.healthy,
  };
}

CustomerConsentStatus _consentStatusFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'GRANTED' => CustomerConsentStatus.granted,
    'DENIED' => CustomerConsentStatus.denied,
    'REVOKED' => CustomerConsentStatus.revoked,
    _ => CustomerConsentStatus.unknown,
  };
}
