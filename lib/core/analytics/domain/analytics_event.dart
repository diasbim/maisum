import 'dart:convert';

class AnalyticsEvent {
  const AnalyticsEvent({
    required this.id,
    required this.eventType,
    required this.occurredAt,
    this.source,
    this.deviceId,
    this.appVersion,
    this.properties,
    this.synced = false,
  });

  final String id;
  final String eventType;
  final DateTime occurredAt;
  final String? source;
  final String? deviceId;
  final String? appVersion;
  final Map<String, dynamic>? properties;
  final bool synced;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'event_type': eventType,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'source': source,
        'device_id': deviceId,
        'app_version': appVersion,
        'properties': properties == null ? null : _encode(properties!),
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toApiMap() => {
        'eventType': eventType,
        'occurredAt': occurredAt.toIso8601String(),
        'source': source,
        'deviceId': deviceId,
        'appVersion': appVersion,
        'properties': properties,
      };

  static AnalyticsEvent fromMap(Map<String, dynamic> map) => AnalyticsEvent(
        id: map['id'] as String,
        eventType: map['event_type'] as String,
        occurredAt:
            DateTime.fromMillisecondsSinceEpoch(map['occurred_at'] as int),
        source: map['source'] as String?,
        deviceId: map['device_id'] as String?,
        appVersion: map['app_version'] as String?,
        properties: map['properties'] == null
            ? null
            : _decode(map['properties'] as String),
        synced: (map['synced'] as int? ?? 0) == 1,
      );

  static String _encode(Map<String, dynamic> value) {
    return value.isEmpty ? '{}' : _jsonEncode(value);
  }

  static Map<String, dynamic> _decode(String raw) {
    if (raw.trim().isEmpty) return const {};
    final decoded = _jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

String _jsonEncode(Object value) => jsonEncode(value);

Object _jsonDecode(String value) => jsonDecode(value);
