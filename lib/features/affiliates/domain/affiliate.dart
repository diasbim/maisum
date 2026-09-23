import 'affiliate_serialization.dart';

enum AffiliateStatus {
  active('ACTIVE'),
  inactive('INACTIVE'),
  suspended('SUSPENDED');

  const AffiliateStatus(this.storageValue);

  final String storageValue;

  static AffiliateStatus fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'ACTIVE':
        return AffiliateStatus.active;
      case 'INACTIVE':
        return AffiliateStatus.inactive;
      case 'SUSPENDED':
        return AffiliateStatus.suspended;
    }
    throw FormatException('Invalid AffiliateStatus value: $value');
  }
}

enum AffiliateMerchantStatus {
  active('ACTIVE'),
  inactive('INACTIVE');

  const AffiliateMerchantStatus(this.storageValue);

  final String storageValue;

  static AffiliateMerchantStatus fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'ACTIVE':
        return AffiliateMerchantStatus.active;
      case 'INACTIVE':
        return AffiliateMerchantStatus.inactive;
    }
    throw FormatException('Invalid AffiliateMerchantStatus value: $value');
  }
}

class Affiliate {
  const Affiliate({
    required this.id,
    required this.phone,
    required this.normalizedPhone,
    required this.firstName,
    this.lastName,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String phone;
  final String normalizedPhone;
  final String firstName;
  final String? lastName;
  final String displayName;
  final AffiliateStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  bool get isActive => status == AffiliateStatus.active;

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone': phone,
        'normalized_phone': normalizedPhone,
        'first_name': firstName,
        'last_name': lastName,
        'display_name': displayName,
        'status': status.storageValue,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => toMap();

  factory Affiliate.fromMap(Map<String, dynamic> map) {
    return Affiliate(
      id: readRequiredString(map, ['id']),
      phone: readRequiredString(map, ['phone']),
      normalizedPhone: readRequiredString(
        map,
        ['normalized_phone', 'normalizedPhone'],
      ),
      firstName: readRequiredString(map, ['first_name', 'firstName']),
      lastName: readNullableString(map, ['last_name', 'lastName']),
      displayName: readRequiredString(map, ['display_name', 'displayName']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateStatus.fromStorage,
      ),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
      synced: readBool(map, ['synced']),
    );
  }

  factory Affiliate.fromJson(Map<String, dynamic> json) =>
      Affiliate.fromMap(json);
}

class AffiliateMerchantLink {
  const AffiliateMerchantLink({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.status,
    required this.linkedAt,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final AffiliateMerchantStatus status;
  final DateTime linkedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  bool get isActive => status == AffiliateMerchantStatus.active;

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'status': status.storageValue,
        'linked_at': linkedAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => toMap();

  factory AffiliateMerchantLink.fromMap(Map<String, dynamic> map) {
    return AffiliateMerchantLink(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateMerchantStatus.fromStorage,
      ),
      linkedAt: readRequiredDateTime(map, ['linked_at', 'linkedAt']),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
      synced: readBool(map, ['synced']),
    );
  }

  factory AffiliateMerchantLink.fromJson(Map<String, dynamic> json) =>
      AffiliateMerchantLink.fromMap(json);
}
