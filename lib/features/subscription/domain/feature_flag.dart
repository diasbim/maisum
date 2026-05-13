import 'dart:convert';

class FeatureFlag {
  const FeatureFlag({
    required this.id,
    required this.merchantId,
    required this.flagKey,
    required this.isEnabled,
    required this.updatedAt,
    this.payload,
  });

  final String id;
  final String merchantId;
  final String flagKey;
  final bool isEnabled;
  final Map<String, dynamic>? payload;
  final DateTime updatedAt;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'flag_key': flagKey,
        'is_enabled': isEnabled ? 1 : 0,
        'payload': payload == null ? null : jsonEncode(payload),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

FeatureFlag featureFlagFromMap(Map<String, dynamic> map) => FeatureFlag(
      id: map['id'] as String,
      merchantId: map['merchant_id'] as String,
      flagKey: map['flag_key'] as String,
      isEnabled: (map['is_enabled'] as int? ?? 1) == 1,
      payload: _payloadFromRaw(map['payload']),
      updatedAt: _dateFromInt(map['updated_at']) ?? DateTime.now(),
    );

Map<String, dynamic>? _payloadFromRaw(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
  }
  return null;
}

DateTime? _dateFromInt(Object? raw) {
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  return null;
}
