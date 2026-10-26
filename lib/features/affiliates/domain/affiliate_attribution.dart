import 'affiliate_serialization.dart';
import 'referral_validation.dart';

enum AffiliateAttributionStatus {
  confirmed('CONFIRMED'),
  rejected('REJECTED'),
  cancelled('CANCELLED');

  const AffiliateAttributionStatus(this.storageValue);

  final String storageValue;

  static AffiliateAttributionStatus fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'CONFIRMED':
        return AffiliateAttributionStatus.confirmed;
      case 'REJECTED':
        return AffiliateAttributionStatus.rejected;
      case 'CANCELLED':
        return AffiliateAttributionStatus.cancelled;
    }
    throw FormatException('Invalid AffiliateAttributionStatus value: $value');
  }
}

class AffiliateAttribution {
  const AffiliateAttribution({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.affiliateCodeId,
    required this.customerId,
    required this.status,
    required this.attributedAt,
    required this.createdAt,
    required this.updatedAt,
    this.qualifyingSaleId,
    this.firstSaleAt,
    this.rejectionCode,
    this.synced = false,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final String affiliateCodeId;
  final String customerId;
  final String? qualifyingSaleId;
  final AffiliateAttributionStatus status;
  final ReferralValidationErrorCode? rejectionCode;
  final DateTime attributedAt;
  final DateTime? firstSaleAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  bool get isActive => status == AffiliateAttributionStatus.confirmed;

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'affiliate_code_id': affiliateCodeId,
        'customer_id': customerId,
        'qualifying_sale_id': qualifyingSaleId,
        'status': status.storageValue,
        'rejection_code': rejectionCode?.storageValue,
        'attributed_at': attributedAt.millisecondsSinceEpoch,
        'first_sale_at': firstSaleAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => toMap();

  factory AffiliateAttribution.fromMap(Map<String, dynamic> map) {
    return AffiliateAttribution(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      affiliateCodeId: readRequiredString(
        map,
        ['affiliate_code_id', 'affiliateCodeId'],
      ),
      customerId: readRequiredString(map, ['customer_id', 'customerId']),
      qualifyingSaleId: readNullableString(
        map,
        ['qualifying_sale_id', 'qualifyingSaleId'],
      ),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateAttributionStatus.fromStorage,
      ),
      rejectionCode: readNullableEnum(
        map,
        ['rejection_code', 'rejectionCode'],
        ReferralValidationErrorCode.fromStorage,
      ),
      attributedAt: readRequiredDateTime(
        map,
        ['attributed_at', 'attributedAt'],
      ),
      firstSaleAt: readNullableDateTime(map, ['first_sale_at', 'firstSaleAt']),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
      synced: readBool(map, ['synced']),
    );
  }

  factory AffiliateAttribution.fromJson(Map<String, dynamic> json) =>
      AffiliateAttribution.fromMap(json);
}
