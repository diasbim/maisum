import 'dart:convert';

class NotificationQueueItem {
  const NotificationQueueItem({
    required this.id,
    required this.channel,
    required this.payload,
    required this.status,
    required this.scheduledAt,
    required this.createdAt,
    required this.retryCount,
    this.lastError,
  });

  final String id;
  final String channel;
  final Map<String, dynamic> payload;
  final String status;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'channel': channel,
        'payload': jsonEncode(payload),
        'status': status,
        'scheduled_at': scheduledAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'retry_count': retryCount,
        'last_error': lastError,
      };

  static NotificationQueueItem fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as String? ?? '{}';
    return NotificationQueueItem(
      id: map['id'] as String,
      channel: map['channel'] as String,
      payload: jsonDecode(payload) as Map<String, dynamic>,
      status: map['status'] as String,
      scheduledAt:
          DateTime.fromMillisecondsSinceEpoch(map['scheduled_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      retryCount: map['retry_count'] as int? ?? 0,
      lastError: map['last_error'] as String?,
    );
  }
}
