class Entitlement {
  const Entitlement({
    required this.id,
    required this.merchantId,
    required this.featureKey,
    required this.isEnabled,
    required this.updatedAt,
    this.limitValue,
    this.unit,
  });

  final String id;
  final String merchantId;
  final String featureKey;
  final bool isEnabled;
  final int? limitValue;
  final String? unit;
  final DateTime updatedAt;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'feature_key': featureKey,
        'is_enabled': isEnabled ? 1 : 0,
        'limit_value': limitValue,
        'unit': unit,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

Entitlement entitlementFromMap(Map<String, dynamic> map) => Entitlement(
      id: map['id'] as String,
      merchantId: map['merchant_id'] as String,
      featureKey: map['feature_key'] as String,
      isEnabled: (map['is_enabled'] as int? ?? 1) == 1,
      limitValue: map['limit_value'] as int?,
      unit: map['unit'] as String?,
      updatedAt: _dateFromInt(map['updated_at']) ?? DateTime.now(),
    );

DateTime? _dateFromInt(Object? raw) {
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  return null;
}
