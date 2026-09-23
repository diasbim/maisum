import 'affiliate_serialization.dart';

enum ReferralBenefitType {
  percentage('PERCENTAGE'),
  fixedAmount('FIXED_AMOUNT'),
  points('POINTS');

  const ReferralBenefitType(this.storageValue);

  final String storageValue;

  static ReferralBenefitType fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'PERCENTAGE':
        return ReferralBenefitType.percentage;
      case 'FIXED_AMOUNT':
        return ReferralBenefitType.fixedAmount;
      case 'POINTS':
        return ReferralBenefitType.points;
    }
    throw FormatException('Invalid ReferralBenefitType value: $value');
  }
}

enum AffiliateCodeStatus {
  active('ACTIVE'),
  disabled('DISABLED');

  const AffiliateCodeStatus(this.storageValue);

  final String storageValue;

  static AffiliateCodeStatus fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'ACTIVE':
        return AffiliateCodeStatus.active;
      case 'DISABLED':
        return AffiliateCodeStatus.disabled;
    }
    throw FormatException('Invalid AffiliateCodeStatus value: $value');
  }
}

class AffiliateCode {
  const AffiliateCode({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.code,
    required this.normalizedCode,
    required this.benefitType,
    required this.benefitValue,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.startsAt,
    this.expiresAt,
    this.usageLimit,
    this.usageCount = 0,
    this.firstVisitOnly = true,
    this.synced = false,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final String code;
  final String normalizedCode;
  final ReferralBenefitType benefitType;
  final double benefitValue;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? usageLimit;
  final int usageCount;
  final bool firstVisitOnly;
  final AffiliateCodeStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  bool get isActive => status == AffiliateCodeStatus.active;

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'code': code,
        'normalized_code': normalizedCode,
        'benefit_type': benefitType.storageValue,
        'benefit_value': benefitValue,
        'starts_at': startsAt?.millisecondsSinceEpoch,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
        'usage_limit': usageLimit,
        'usage_count': usageCount,
        'first_visit_only': firstVisitOnly ? 1 : 0,
        'status': status.storageValue,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => toMap();

  factory AffiliateCode.fromMap(Map<String, dynamic> map) {
    return AffiliateCode(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      code: readRequiredString(map, ['code']),
      normalizedCode: readRequiredString(
        map,
        ['normalized_code', 'normalizedCode'],
      ),
      benefitType: readRequiredEnum(
        map,
        ['benefit_type', 'benefitType'],
        ReferralBenefitType.fromStorage,
      ),
      benefitValue: readRequiredDouble(map, ['benefit_value', 'benefitValue']),
      startsAt: readNullableDateTime(map, ['starts_at', 'startsAt']),
      expiresAt: readNullableDateTime(map, ['expires_at', 'expiresAt']),
      usageLimit: readNullableInt(map, ['usage_limit', 'usageLimit']),
      usageCount: readNullableInt(map, ['usage_count', 'usageCount']) ?? 0,
      firstVisitOnly: readBool(
        map,
        ['first_visit_only', 'firstVisitOnly'],
        defaultValue: true,
      ),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateCodeStatus.fromStorage,
      ),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
      synced: readBool(map, ['synced']),
    );
  }

  factory AffiliateCode.fromJson(Map<String, dynamic> json) =>
      AffiliateCode.fromMap(json);
}

class AffiliateCodeLookupCache {
  const AffiliateCodeLookupCache({
    required this.normalizedCode,
    required this.codeId,
    required this.merchantId,
    required this.affiliateId,
    required this.code,
    required this.status,
    required this.benefitType,
    required this.benefitValue,
    required this.cachedAt,
    required this.updatedAt,
    this.startsAt,
    this.expiresAt,
    this.usageLimit,
    this.usageCount = 0,
    this.firstVisitOnly = true,
    this.affiliateDisplayName,
    this.affiliateFirstName,
    this.affiliateStatus = 'ACTIVE',
    this.linkStatus = 'ACTIVE',
    this.refreshedAt,
  });

  final String normalizedCode;
  final String codeId;
  final String merchantId;
  final String affiliateId;
  final String code;
  final AffiliateCodeStatus status;
  final ReferralBenefitType benefitType;
  final double benefitValue;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? usageLimit;
  final int usageCount;
  final bool firstVisitOnly;
  final DateTime cachedAt;
  final DateTime updatedAt;

  /// The affiliate as a cashier would say it, cached alongside the terms.
  ///
  /// Without it an offline preview could only show an identifier, and "código
  /// válido, afiliado ac_9f3b…" is not something anyone can read back to a
  /// customer.
  final String? affiliateDisplayName;
  final String? affiliateFirstName;

  /// The two statuses that make an ACTIVE code unusable anyway: a suspended
  /// affiliate, or one no longer linked to this business.
  final String affiliateStatus;
  final String linkStatus;

  /// When this row was last confirmed by a sync, as opposed to when it was
  /// first written.
  final DateTime? refreshedAt;

  Map<String, dynamic> toMap() => {
        'normalized_code': normalizedCode,
        'code_id': codeId,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'code': code,
        'status': status.storageValue,
        'benefit_type': benefitType.storageValue,
        'benefit_value': benefitValue,
        'starts_at': startsAt?.millisecondsSinceEpoch,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
        'usage_limit': usageLimit,
        'usage_count': usageCount,
        'first_visit_only': firstVisitOnly ? 1 : 0,
        'cached_at': cachedAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'affiliate_display_name': affiliateDisplayName,
        'affiliate_first_name': affiliateFirstName,
        'affiliate_status': affiliateStatus,
        'link_status': linkStatus,
        'refreshed_at': (refreshedAt ?? cachedAt).millisecondsSinceEpoch,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => toMap();

  factory AffiliateCodeLookupCache.fromMap(Map<String, dynamic> map) {
    return AffiliateCodeLookupCache(
      normalizedCode: readRequiredString(
        map,
        ['normalized_code', 'normalizedCode'],
      ),
      codeId: readRequiredString(map, ['code_id', 'codeId']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      code: readRequiredString(map, ['code']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateCodeStatus.fromStorage,
      ),
      benefitType: readRequiredEnum(
        map,
        ['benefit_type', 'benefitType'],
        ReferralBenefitType.fromStorage,
      ),
      benefitValue: readRequiredDouble(map, ['benefit_value', 'benefitValue']),
      startsAt: readNullableDateTime(map, ['starts_at', 'startsAt']),
      expiresAt: readNullableDateTime(map, ['expires_at', 'expiresAt']),
      usageLimit: readNullableInt(map, ['usage_limit', 'usageLimit']),
      usageCount: readNullableInt(map, ['usage_count', 'usageCount']) ?? 0,
      firstVisitOnly: readBool(
        map,
        ['first_visit_only', 'firstVisitOnly'],
        defaultValue: true,
      ),
      cachedAt: readRequiredDateTime(map, ['cached_at', 'cachedAt']),
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
      affiliateDisplayName: readNullableString(
        map,
        ['affiliate_display_name', 'affiliateDisplayName'],
      ),
      affiliateFirstName: readNullableString(
        map,
        ['affiliate_first_name', 'affiliateFirstName'],
      ),
      affiliateStatus: readNullableString(
            map,
            ['affiliate_status', 'affiliateStatus'],
          ) ??
          'ACTIVE',
      linkStatus:
          readNullableString(map, ['link_status', 'linkStatus']) ?? 'ACTIVE',
      refreshedAt: readNullableDateTime(map, ['refreshed_at', 'refreshedAt']),
    );
  }

  factory AffiliateCodeLookupCache.fromJson(Map<String, dynamic> json) =>
      AffiliateCodeLookupCache.fromMap(json);
}
