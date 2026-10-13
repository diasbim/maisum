// `@JsonKey` on a Freezed constructor parameter is how a converter is attached
// to a field; the analyzer reads the annotation on the parameter and warns,
// while the generator puts it exactly where it belongs. The warning is about
// where the annotation is written, not about what it does.
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../affiliates/domain/affiliate_code.dart';
import '../../affiliates/domain/referral_validation.dart';
import 'sale_item.dart';

part 'sale.freezed.dart';
part 'sale.g.dart';

enum SaleConfirmationStatus { pending, confirmed, rejected, baselineRequired }

enum SaleCancellationStatus { active, cancelled }

extension SaleConfirmationStatusStorage on SaleConfirmationStatus {
  String get storageValue => switch (this) {
        SaleConfirmationStatus.pending => 'PENDING',
        SaleConfirmationStatus.confirmed => 'CONFIRMED',
        SaleConfirmationStatus.rejected => 'REJECTED',
        SaleConfirmationStatus.baselineRequired => 'BASELINE_REQUIRED',
      };
}

extension SaleCancellationStatusStorage on SaleCancellationStatus {
  String get storageValue => name.toUpperCase();
}

@freezed
class Sale with _$Sale {
  const Sale._();

  const factory Sale({
    required String id,
    required String customerId,
    required double amount,
    required int points,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(SaleConfirmationStatus.pending)
    SaleConfirmationStatus confirmationStatus,
    int? confirmedPoints,
    DateTime? confirmedAt,
    String? confirmationErrorCode,
    int? loyaltyPolicyVersion,
    @Default(SaleCancellationStatus.active)
    SaleCancellationStatus cancellationStatus,
    DateTime? cancelledAt,
    String? cancelledByAppUserId,
    String? cancellationReason,
    String? replacementSaleId,

    /// What the sale was before a referral discount, and what the code did.
    ///
    /// All nullable and all absent on an ordinary sale, which is the point: a
    /// sale with no code reads and writes exactly as it did before these
    /// existed, in JSON and in SQLite alike. Every one of them is written by
    /// the server — `firestore.rules` refuses a client that tries — so they
    /// arrive by projection and are never sent back up.
    @JsonKey(
      fromJson: _referralBenefitTypeFromJson,
      toJson: _referralBenefitTypeToJson,
    )
    ReferralBenefitType? referralBenefitType,
    double? grossAmount,
    double? referralBenefitValue,
    double? referralBenefitAmount,
    String? affiliateCodeId,
    @JsonKey(
      fromJson: _referralSaleStatusFromJson,
      toJson: _referralSaleStatusToJson,
    )
    ReferralSaleStatus? referralStatus,
    @Default(<SaleItem>[]) List<SaleItem> items,
    @Default(false) bool synced,
  }) = _Sale;

  factory Sale.fromJson(Map<String, dynamic> json) => _$SaleFromJson(json);

  bool get isCancelled =>
      cancellationStatus == SaleCancellationStatus.cancelled;

  /// A sale a code was applied to. The discount, if any, is already in [amount].
  bool get isReferred => affiliateCodeId != null;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'customer_id': customerId,
        'amount': amount,
        'points': points,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
        'confirmation_status': confirmationStatus.storageValue,
        'confirmed_points': confirmedPoints,
        'confirmed_at': confirmedAt?.millisecondsSinceEpoch,
        'confirmation_error_code': confirmationErrorCode,
        'loyalty_policy_version': loyaltyPolicyVersion,
        'cancellation_status': cancellationStatus.storageValue,
        'cancelled_at': cancelledAt?.millisecondsSinceEpoch,
        'cancelled_by_app_user_id': cancelledByAppUserId,
        'cancellation_reason': cancellationReason,
        'replacement_sale_id': replacementSaleId,
        'gross_amount': grossAmount,
        'referral_benefit_type': referralBenefitType?.storageValue,
        'referral_benefit_value': referralBenefitValue,
        'referral_benefit_amount': referralBenefitAmount,
        'affiliate_code_id': affiliateCodeId,
        'referral_status': referralStatus?.storageValue,
        'synced': synced ? 1 : 0,
      };

  /// What the till may send up, which is still only what it has always sent.
  ///
  /// The referral fields are deliberately absent: they are decided by the
  /// `/merchant/referral-sales/commit` transaction, and a sale that carried
  /// them here would be asking the server to trust a discount the till chose.
  Map<String, dynamic> toClientSyncMap() => {
        'id': id,
        'customer_id': customerId,
        'amount': amount,
        'points': points,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
      };
}

Sale saleFromMap(Map<String, dynamic> map) => Sale(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      points: map['points'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['updated_at'] as num).toInt(),
            ),
      confirmationStatus:
          _saleConfirmationStatusFromStorage(map['confirmation_status']),
      confirmedPoints: (map['confirmed_points'] as num?)?.toInt(),
      confirmedAt: map['confirmed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['confirmed_at'] as num).toInt(),
            ),
      confirmationErrorCode: map['confirmation_error_code'] as String?,
      loyaltyPolicyVersion: (map['loyalty_policy_version'] as num?)?.toInt(),
      cancellationStatus:
          _saleCancellationStatusFromStorage(map['cancellation_status']),
      cancelledAt: map['cancelled_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['cancelled_at'] as num).toInt(),
            ),
      cancelledByAppUserId: map['cancelled_by_app_user_id'] as String?,
      cancellationReason: map['cancellation_reason'] as String?,
      replacementSaleId: map['replacement_sale_id'] as String?,
      grossAmount: (map['gross_amount'] as num?)?.toDouble(),
      referralBenefitType:
          _referralBenefitTypeFromJson(map['referral_benefit_type']),
      referralBenefitValue: (map['referral_benefit_value'] as num?)?.toDouble(),
      referralBenefitAmount:
          (map['referral_benefit_amount'] as num?)?.toDouble(),
      affiliateCodeId: map['affiliate_code_id'] as String?,
      referralStatus: _referralSaleStatusFromJson(map['referral_status']),
      items: saleItemsFromValue(map['items']),
      synced: (map['synced'] as int? ?? 0) == 1,
    );

/// Referral enums, read leniently and written strictly.
///
/// A value the server adds later must not crash a till that has not been
/// updated, so anything unrecognised reads as absent — the sale is still a
/// sale. Writing goes the other way and always emits the stored spelling.
ReferralBenefitType? _referralBenefitTypeFromJson(Object? value) {
  if (value == null) return null;
  try {
    return ReferralBenefitType.fromStorage(value);
  } on FormatException {
    return null;
  }
}

String? _referralBenefitTypeToJson(ReferralBenefitType? value) =>
    value?.storageValue;

ReferralSaleStatus? _referralSaleStatusFromJson(Object? value) {
  if (value == null) return null;
  try {
    return ReferralSaleStatus.fromStorage(value);
  } on FormatException {
    return null;
  }
}

String? _referralSaleStatusToJson(ReferralSaleStatus? value) =>
    value?.storageValue;

SaleConfirmationStatus _saleConfirmationStatusFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'CONFIRMED' => SaleConfirmationStatus.confirmed,
    'REJECTED' => SaleConfirmationStatus.rejected,
    'BASELINE_REQUIRED' => SaleConfirmationStatus.baselineRequired,
    _ => SaleConfirmationStatus.pending,
  };
}

SaleCancellationStatus _saleCancellationStatusFromStorage(Object? value) {
  return value?.toString().toUpperCase() == 'CANCELLED'
      ? SaleCancellationStatus.cancelled
      : SaleCancellationStatus.active;
}
