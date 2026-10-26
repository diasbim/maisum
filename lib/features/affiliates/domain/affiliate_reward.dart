import 'affiliate_serialization.dart';

enum AffiliateRewardType {
  firstQualifyingSale('FIRST_QUALIFYING_SALE'),
  customerReturn('CUSTOMER_RETURN');

  const AffiliateRewardType(this.storageValue);

  final String storageValue;

  static AffiliateRewardType fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'FIRST_QUALIFYING_SALE':
        return AffiliateRewardType.firstQualifyingSale;
      case 'CUSTOMER_RETURN':
        return AffiliateRewardType.customerReturn;
    }
    throw FormatException('Invalid AffiliateRewardType value: $value');
  }
}

enum AffiliateRewardValueType {
  points('POINTS'),
  fixedAmount('FIXED_AMOUNT');

  const AffiliateRewardValueType(this.storageValue);

  final String storageValue;

  static AffiliateRewardValueType fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'POINTS':
        return AffiliateRewardValueType.points;
      case 'FIXED_AMOUNT':
        return AffiliateRewardValueType.fixedAmount;
    }
    throw FormatException('Invalid AffiliateRewardValueType value: $value');
  }
}

enum AffiliateRewardStatus {
  pending('PENDING'),
  approved('APPROVED'),
  cancelled('CANCELLED'),
  paid('PAID');

  const AffiliateRewardStatus(this.storageValue);

  final String storageValue;

  static AffiliateRewardStatus fromStorage(Object value) {
    final normalized = value.toString().trim().toUpperCase();
    switch (normalized) {
      case 'PENDING':
        return AffiliateRewardStatus.pending;
      case 'APPROVED':
        return AffiliateRewardStatus.approved;
      case 'CANCELLED':
        return AffiliateRewardStatus.cancelled;
      case 'PAID':
        return AffiliateRewardStatus.paid;
    }
    throw FormatException('Invalid AffiliateRewardStatus value: $value');
  }
}

class AffiliateReward {
  const AffiliateReward({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.attributionId,
    required this.rewardType,
    required this.valueType,
    required this.rewardValue,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.approvalRequired = true,
    this.sourceSaleId,
    this.approvedAt,
    this.approvedByAppUserId,
    this.cancelledAt,
    this.cancelledByAppUserId,
    this.cancellationReason,
    this.paidAt,
    this.paidByAppUserId,
    this.synced = false,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final String attributionId;
  final AffiliateRewardType rewardType;
  final AffiliateRewardValueType valueType;
  final double rewardValue;
  final AffiliateRewardStatus status;
  final bool approvalRequired;
  final String? sourceSaleId;
  final DateTime? approvedAt;
  final String? approvedByAppUserId;
  final DateTime? cancelledAt;
  final String? cancelledByAppUserId;
  final String? cancellationReason;
  final DateTime? paidAt;
  final String? paidByAppUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'attribution_id': attributionId,
        'reward_type': rewardType.storageValue,
        'value_type': valueType.storageValue,
        'reward_value': rewardValue,
        'status': status.storageValue,
        'approval_required': approvalRequired ? 1 : 0,
        'source_sale_id': sourceSaleId,
        'approved_at': approvedAt?.millisecondsSinceEpoch,
        'approved_by_app_user_id': approvedByAppUserId,
        'cancelled_at': cancelledAt?.millisecondsSinceEpoch,
        'cancelled_by_app_user_id': cancelledByAppUserId,
        'cancellation_reason': cancellationReason,
        'paid_at': paidAt?.millisecondsSinceEpoch,
        'paid_by_app_user_id': paidByAppUserId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toDbMap() => toMap();

  Map<String, dynamic> toJson() => toMap();

  factory AffiliateReward.fromMap(Map<String, dynamic> map) {
    return AffiliateReward(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      attributionId: readRequiredString(
        map,
        ['attribution_id', 'attributionId'],
      ),
      rewardType: readRequiredEnum(
        map,
        ['reward_type', 'rewardType'],
        AffiliateRewardType.fromStorage,
      ),
      valueType: readRequiredEnum(
        map,
        ['value_type', 'valueType'],
        AffiliateRewardValueType.fromStorage,
      ),
      rewardValue: readRequiredDouble(map, ['reward_value', 'rewardValue']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateRewardStatus.fromStorage,
      ),
      approvalRequired: readBool(
        map,
        ['approval_required', 'approvalRequired'],
        defaultValue: true,
      ),
      sourceSaleId: readNullableString(map, ['source_sale_id', 'sourceSaleId']),
      approvedAt: readNullableDateTime(map, ['approved_at', 'approvedAt']),
      approvedByAppUserId: readNullableString(
        map,
        ['approved_by_app_user_id', 'approvedByAppUserId'],
      ),
      cancelledAt: readNullableDateTime(map, ['cancelled_at', 'cancelledAt']),
      cancelledByAppUserId: readNullableString(
        map,
        ['cancelled_by_app_user_id', 'cancelledByAppUserId'],
      ),
      cancellationReason: readNullableString(
        map,
        ['cancellation_reason', 'cancellationReason'],
      ),
      paidAt: readNullableDateTime(map, ['paid_at', 'paidAt']),
      paidByAppUserId: readNullableString(
        map,
        ['paid_by_app_user_id', 'paidByAppUserId'],
      ),
      createdAt: readRequiredDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
      synced: readBool(map, ['synced']),
    );
  }

  factory AffiliateReward.fromJson(Map<String, dynamic> json) =>
      AffiliateReward.fromMap(json);
}
