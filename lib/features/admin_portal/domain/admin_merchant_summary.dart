class AdminMerchantSummary {
  const AdminMerchantSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
    required this.updatedAt,
    required this.staffCount,
    required this.activeStaffCount,
    required this.usageBalanceCount,
    this.planCode,
    this.planName,
    this.subscriptionStatus,
    this.lastOperationalUpdateAt,
  });

  final String id;
  final String name;
  final String phone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? planCode;
  final String? planName;
  final String? subscriptionStatus;
  final int staffCount;
  final int activeStaffCount;
  final int usageBalanceCount;
  final DateTime? lastOperationalUpdateAt;

  factory AdminMerchantSummary.fromJson(Map<String, dynamic> json) {
    return AdminMerchantSummary(
      id: _readString(json, 'id') ?? '',
      name: _readString(json, 'name') ?? 'Merchant',
      phone: _readString(json, 'phone') ?? '',
      createdAt: _readDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDate(json['updated_at']) ?? DateTime.now(),
      planCode: _readString(json, 'plan_code'),
      planName: _readString(json, 'plan_name'),
      subscriptionStatus: _readString(json, 'subscription_status'),
      staffCount: _readInt(json['staff_count']),
      activeStaffCount: _readInt(json['active_staff_count']),
      usageBalanceCount: _readInt(json['usage_balance_count']),
      lastOperationalUpdateAt: _readDate(json['last_operational_update_at']),
    );
  }
}

class AdminMerchantDetail {
  const AdminMerchantDetail({
    required this.summary,
    required this.entitlementCount,
    required this.featureFlagCount,
    required this.remoteConfigCount,
    required this.usageEventCount,
    required this.usageUsedTotal,
    this.planVersion,
    this.pricingVersion,
    this.trialEndsAt,
    this.graceEndsAt,
    this.periodStart,
    this.periodEnd,
    this.subscriptionUpdatedAt,
    this.lastStaffLoginAt,
    this.usageUpdatedAt,
    this.lastUsageEventAt,
  });

  final AdminMerchantSummary summary;
  final int? planVersion;
  final int? pricingVersion;
  final DateTime? trialEndsAt;
  final DateTime? graceEndsAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? subscriptionUpdatedAt;
  final DateTime? lastStaffLoginAt;
  final DateTime? usageUpdatedAt;
  final DateTime? lastUsageEventAt;
  final int entitlementCount;
  final int featureFlagCount;
  final int remoteConfigCount;
  final int usageEventCount;
  final int usageUsedTotal;

  factory AdminMerchantDetail.fromJson(Map<String, dynamic> json) {
    return AdminMerchantDetail(
      summary: AdminMerchantSummary.fromJson(json),
      planVersion: _readNullableInt(json['plan_version']),
      pricingVersion: _readNullableInt(json['pricing_version']),
      trialEndsAt: _readDate(json['trial_ends_at']),
      graceEndsAt: _readDate(json['grace_ends_at']),
      periodStart: _readDate(json['period_start']),
      periodEnd: _readDate(json['period_end']),
      subscriptionUpdatedAt: _readDate(json['subscription_updated_at']),
      lastStaffLoginAt: _readDate(json['last_staff_login_at']),
      usageUpdatedAt: _readDate(json['usage_updated_at']),
      lastUsageEventAt: _readDate(json['last_usage_event_at']),
      entitlementCount: _readInt(json['entitlement_count']),
      featureFlagCount: _readInt(json['feature_flag_count']),
      remoteConfigCount: _readInt(json['remote_config_count']),
      usageEventCount: _readInt(json['usage_event_count']),
      usageUsedTotal: _readInt(json['usage_used_total']),
    );
  }
}

String? _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

int? _readNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

DateTime? _readDate(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.round());
  }
  if (value is String) {
    final millis = int.tryParse(value.trim());
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.tryParse(value);
  }
  return null;
}
