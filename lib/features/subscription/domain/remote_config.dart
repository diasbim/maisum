import 'dart:convert';

class RemoteConfigEntry {
  const RemoteConfigEntry({
    required this.id,
    required this.merchantId,
    required this.configKey,
    required this.updatedAt,
    this.payload,
  });

  final String id;
  final String merchantId;
  final String configKey;
  final Map<String, dynamic>? payload;
  final DateTime updatedAt;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'config_key': configKey,
        'payload': payload == null ? null : jsonEncode(payload),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

RemoteConfigEntry remoteConfigEntryFromMap(Map<String, dynamic> map) {
  return RemoteConfigEntry(
    id: map['id'] as String,
    merchantId: map['merchant_id'] as String,
    configKey: map['config_key'] as String,
    payload: _payloadFromRaw(map['payload']),
    updatedAt: _dateFromInt(map['updated_at']) ?? DateTime.now(),
  );
}

Map<String, dynamic>? _payloadFromRaw(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
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
