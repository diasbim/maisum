class AdminPlanCatalogItem {
  const AdminPlanCatalogItem({
    required this.planCode,
    required this.version,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.prices,
    required this.features,
  });

  final String planCode;
  final int version;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AdminPlanPrice> prices;
  final List<AdminPlanFeature> features;

  factory AdminPlanCatalogItem.fromJson(Map<String, dynamic> json) {
    return AdminPlanCatalogItem(
      planCode: _readString(json, 'plan_code') ?? '',
      version: _readInt(json['version']),
      name: _readString(json, 'name') ?? 'Plan',
      isActive: _readBool(json['is_active']) ?? false,
      createdAt: _readDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDate(json['updated_at']) ?? DateTime.now(),
      prices: _readMapList(json['prices'])
          .map(AdminPlanPrice.fromJson)
          .toList(growable: false),
      features: _readMapList(json['features'])
          .map(AdminPlanFeature.fromJson)
          .toList(growable: false),
    );
  }
}

class AdminPlanPrice {
  const AdminPlanPrice({
    required this.pricingVersion,
    required this.currency,
    required this.amount,
    required this.billingPeriod,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int pricingVersion;
  final String currency;
  final int amount;
  final String billingPeriod;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AdminPlanPrice.fromJson(Map<String, dynamic> json) {
    return AdminPlanPrice(
      pricingVersion: _readInt(json['pricing_version']),
      currency: _readString(json, 'currency') ?? 'MZN',
      amount: _readInt(json['amount']),
      billingPeriod: _readString(json, 'billing_period') ?? 'monthly',
      isActive: _readBool(json['is_active']) ?? false,
      createdAt: _readDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDate(json['updated_at']) ?? DateTime.now(),
    );
  }
}

class AdminPlanFeature {
  const AdminPlanFeature({
    required this.featureKey,
    required this.isEnabled,
    required this.updatedAt,
    this.limitValue,
    this.unit,
  });

  final String featureKey;
  final bool isEnabled;
  final int? limitValue;
  final String? unit;
  final DateTime updatedAt;

  factory AdminPlanFeature.fromJson(Map<String, dynamic> json) {
    return AdminPlanFeature(
      featureKey: _readString(json, 'feature_key') ?? '',
      isEnabled: _readBool(json['is_enabled']) ?? false,
      limitValue: _readNullableInt(json['limit_value']),
      unit: _readString(json, 'unit'),
      updatedAt: _readDate(json['updated_at']) ?? DateTime.now(),
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

bool? _readBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
}

DateTime? _readDate(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.round());
  if (value is String) {
    final millis = int.tryParse(value.trim());
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.tryParse(value);
  }
  return null;
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is List) {
    return value.whereType<Map>().map((row) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }).toList(growable: false);
  }
  return const [];
}
