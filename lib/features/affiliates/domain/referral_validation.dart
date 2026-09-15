import 'affiliate_code.dart';
import 'affiliate_serialization.dart';

enum ReferralValidationErrorCode {
  codeNotFound('CODE_NOT_FOUND'),
  codeDisabled('CODE_DISABLED'),
  codeNotStarted('CODE_NOT_STARTED'),
  codeExpired('CODE_EXPIRED'),
  codeUsageLimitReached('CODE_USAGE_LIMIT_REACHED'),
  affiliateInactive('AFFILIATE_INACTIVE'),
  selfReferralNotAllowed('SELF_REFERRAL_NOT_ALLOWED'),
  customerNotEligible('CUSTOMER_NOT_ELIGIBLE'),
  customerAlreadyReferred('CUSTOMER_ALREADY_REFERRED'),
  benefitInvalid('BENEFIT_INVALID');

  const ReferralValidationErrorCode(this.storageValue);

  final String storageValue;

  static ReferralValidationErrorCode fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    for (final error in ReferralValidationErrorCode.values) {
      if (error.storageValue == normalized) return error;
    }
    throw FormatException('Invalid ReferralValidationErrorCode value: $value');
  }
}

enum ReferralSaleStatus {
  pending('PENDING'),
  attributed('ATTRIBUTED'),
  rejected('REJECTED');

  const ReferralSaleStatus(this.storageValue);

  final String storageValue;

  static ReferralSaleStatus fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    for (final status in ReferralSaleStatus.values) {
      if (status.storageValue == normalized) return status;
    }
    throw FormatException('Invalid ReferralSaleStatus value: $value');
  }
}

class ReferralBenefitPreview {
  const ReferralBenefitPreview({
    required this.benefitType,
    required this.benefitValue,
    this.benefitAmount,
  });

  final ReferralBenefitType benefitType;
  final double benefitValue;
  final double? benefitAmount;

  Map<String, dynamic> toMap() => {
        'benefit_type': benefitType.storageValue,
        'benefit_value': benefitValue,
        'benefit_amount': benefitAmount,
      };

  Map<String, dynamic> toJson() => toMap();

  factory ReferralBenefitPreview.fromMap(Map<String, dynamic> map) {
    return ReferralBenefitPreview(
      benefitType: readRequiredEnum(
        map,
        ['benefit_type', 'benefitType'],
        ReferralBenefitType.fromStorage,
      ),
      benefitValue: readRequiredDouble(map, ['benefit_value', 'benefitValue']),
      benefitAmount:
          readNullableDouble(map, ['benefit_amount', 'benefitAmount']),
    );
  }

  factory ReferralBenefitPreview.fromJson(Map<String, dynamic> json) =>
      ReferralBenefitPreview.fromMap(json);
}

class ReferralValidationResult {
  const ReferralValidationResult({
    required this.isValid,
    required this.validatedAt,
    this.normalizedCode,
    this.affiliateCodeId,
    this.affiliateId,
    this.saleStatus,
    this.benefit,
    this.errorCode,
    this.statusText,
  });

  final bool isValid;
  final DateTime validatedAt;
  final String? normalizedCode;
  final String? affiliateCodeId;
  final String? affiliateId;
  final ReferralSaleStatus? saleStatus;
  final ReferralBenefitPreview? benefit;
  final ReferralValidationErrorCode? errorCode;
  final String? statusText;

  Map<String, dynamic> toMap() => {
        'is_valid': isValid ? 1 : 0,
        'validated_at': validatedAt.millisecondsSinceEpoch,
        'normalized_code': normalizedCode,
        'affiliate_code_id': affiliateCodeId,
        'affiliate_id': affiliateId,
        'sale_status': saleStatus?.storageValue,
        'benefit': benefit?.toMap(),
        'error_code': errorCode?.storageValue,
        'status_text': statusText,
      };

  Map<String, dynamic> toJson() => {
        'is_valid': isValid,
        'validated_at': validatedAt.millisecondsSinceEpoch,
        'normalized_code': normalizedCode,
        'affiliate_code_id': affiliateCodeId,
        'affiliate_id': affiliateId,
        'sale_status': saleStatus?.storageValue,
        'benefit': benefit?.toJson(),
        'error_code': errorCode?.storageValue,
        'status_text': statusText,
      };

  factory ReferralValidationResult.fromMap(Map<String, dynamic> map) {
    final benefitValue = readNullableMap(map, ['benefit']);
    final errorCode = readNullableEnum(
      map,
      ['error_code', 'errorCode'],
      ReferralValidationErrorCode.fromStorage,
    );
    return ReferralValidationResult(
      isValid: readBool(
        map,
        ['is_valid', 'isValid'],
        defaultValue: errorCode == null,
      ),
      validatedAt: readRequiredDateTime(map, ['validated_at', 'validatedAt']),
      normalizedCode: readNullableString(
        map,
        ['normalized_code', 'normalizedCode'],
      ),
      affiliateCodeId: readNullableString(
        map,
        ['affiliate_code_id', 'affiliateCodeId'],
      ),
      affiliateId: readNullableString(map, ['affiliate_id', 'affiliateId']),
      saleStatus: readNullableEnum(
        map,
        ['sale_status', 'saleStatus'],
        ReferralSaleStatus.fromStorage,
      ),
      benefit: benefitValue == null
          ? null
          : ReferralBenefitPreview.fromMap(benefitValue),
      errorCode: errorCode,
      statusText: readNullableString(map, ['status_text', 'statusText']),
    );
  }

  factory ReferralValidationResult.fromJson(Map<String, dynamic> json) =>
      ReferralValidationResult.fromMap(json);
}
