import 'dart:convert';

class UsageEvent {
  const UsageEvent({
    required this.id,
    required this.merchantId,
    required this.metricKey,
    required this.quantity,
    required this.occurredAt,
    this.source,
    this.metadata,
    this.synced = false,
  });

  final String id;
  final String merchantId;
  final String metricKey;
  final int quantity;
  final DateTime occurredAt;
  final String? source;
  final Map<String, dynamic>? metadata;
  final bool synced;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'metric_key': metricKey,
        'quantity': quantity,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'source': source,
        'metadata': metadata == null ? null : jsonEncode(metadata),
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toSyncPayload() => {
        'id': id,
        'merchant_id': merchantId,
        'metric_key': metricKey,
        'quantity': quantity,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'source': source,
        'metadata': metadata,
      };
}

UsageEvent usageEventFromMap(Map<String, dynamic> map) => UsageEvent(
      id: map['id'] as String,
      merchantId: map['merchant_id'] as String,
      metricKey: map['metric_key'] as String,
      quantity: map['quantity'] as int? ?? 1,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        map['occurred_at'] as int,
      ),
      source: map['source'] as String?,
      metadata: _decodeMetadata(map['metadata']),
      synced: (map['synced'] as int? ?? 0) == 1,
    );

Map<String, dynamic>? _decodeMetadata(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
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
