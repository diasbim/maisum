class UsageBalance {
  const UsageBalance({
    required this.id,
    required this.merchantId,
    required this.metricKey,
    required this.windowStart,
    required this.windowEnd,
    required this.used,
    required this.updatedAt,
    this.limitValue,
    this.softLimit = true,
  });

  final String id;
  final String merchantId;
  final String metricKey;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int used;
  final int? limitValue;
  final bool softLimit;
  final DateTime updatedAt;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'metric_key': metricKey,
        'window_start': windowStart.millisecondsSinceEpoch,
        'window_end': windowEnd.millisecondsSinceEpoch,
        'used': used,
        'limit_value': limitValue,
        'soft_limit': softLimit ? 1 : 0,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

UsageBalance usageBalanceFromMap(Map<String, dynamic> map) => UsageBalance(
      id: map['id'] as String,
      merchantId: map['merchant_id'] as String,
      metricKey: map['metric_key'] as String,
      windowStart: DateTime.fromMillisecondsSinceEpoch(
        (map['window_start'] as int? ?? 0),
      ),
      windowEnd: DateTime.fromMillisecondsSinceEpoch(
        (map['window_end'] as int? ?? 0),
      ),
      used: map['used'] as int? ?? 0,
      limitValue: map['limit_value'] as int?,
      softLimit: (map['soft_limit'] as int? ?? 1) == 1,
      updatedAt: _dateFromInt(map['updated_at']) ?? DateTime.now(),
    );

DateTime? _dateFromInt(Object? raw) {
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  return null;
}
