class UsageQuotaSummary {
  const UsageQuotaSummary({
    required this.metricKey,
    required this.used,
    required this.resetAt,
    this.limit,
    this.softLimit = true,
  });

  final String metricKey;
  final int used;
  final int? limit;
  final DateTime resetAt;
  final bool softLimit;

  bool get isUnlimited => limit == null;

  int? get remaining => limit == null ? null : (limit! - used).clamp(0, limit!);
}
