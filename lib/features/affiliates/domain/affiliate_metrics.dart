import 'affiliate_serialization.dart';

class AffiliateMetrics {
  const AffiliateMetrics({
    required this.affiliateId,
    required this.merchantId,
    required this.totalCodes,
    required this.activeCodes,
    required this.totalAttributions,
    required this.activeAttributions,
    required this.pendingRewards,
    required this.approvedRewards,
    required this.rejectedAttributions,
    required this.totalUsageCount,
    required this.approvedRewardPoints,
    required this.approvedRewardAmount,
    required this.conversionRate,
    required this.updatedAt,
  });

  final String affiliateId;
  final String merchantId;
  final int totalCodes;
  final int activeCodes;
  final int totalAttributions;
  final int activeAttributions;
  final int pendingRewards;
  final int approvedRewards;
  final int rejectedAttributions;
  final int totalUsageCount;
  final int approvedRewardPoints;
  final double approvedRewardAmount;
  final double conversionRate;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'affiliate_id': affiliateId,
        'merchant_id': merchantId,
        'total_codes': totalCodes,
        'active_codes': activeCodes,
        'total_attributions': totalAttributions,
        'active_attributions': activeAttributions,
        'pending_rewards': pendingRewards,
        'approved_rewards': approvedRewards,
        'rejected_attributions': rejectedAttributions,
        'total_usage_count': totalUsageCount,
        'approved_reward_points': approvedRewardPoints,
        'approved_reward_amount': approvedRewardAmount,
        'conversion_rate': conversionRate,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toJson() => toMap();

  factory AffiliateMetrics.fromMap(Map<String, dynamic> map) {
    return AffiliateMetrics(
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      totalCodes: readNullableInt(map, ['total_codes', 'totalCodes']) ?? 0,
      activeCodes: readNullableInt(map, ['active_codes', 'activeCodes']) ?? 0,
      totalAttributions:
          readNullableInt(map, ['total_attributions', 'totalAttributions']) ??
              0,
      activeAttributions:
          readNullableInt(map, ['active_attributions', 'activeAttributions']) ??
              0,
      pendingRewards:
          readNullableInt(map, ['pending_rewards', 'pendingRewards']) ?? 0,
      approvedRewards:
          readNullableInt(map, ['approved_rewards', 'approvedRewards']) ?? 0,
      rejectedAttributions: readNullableInt(
            map,
            ['rejected_attributions', 'rejectedAttributions'],
          ) ??
          0,
      totalUsageCount:
          readNullableInt(map, ['total_usage_count', 'totalUsageCount']) ?? 0,
      approvedRewardPoints: readNullableInt(
            map,
            ['approved_reward_points', 'approvedRewardPoints'],
          ) ??
          0,
      approvedRewardAmount: readNullableDouble(
            map,
            ['approved_reward_amount', 'approvedRewardAmount'],
          ) ??
          0,
      conversionRate:
          readNullableDouble(map, ['conversion_rate', 'conversionRate']) ?? 0,
      updatedAt: readRequiredDateTime(map, ['updated_at', 'updatedAt']),
    );
  }

  factory AffiliateMetrics.fromJson(Map<String, dynamic> json) =>
      AffiliateMetrics.fromMap(json);
}
