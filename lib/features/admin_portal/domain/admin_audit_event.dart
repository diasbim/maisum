class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.targetType,
    required this.createdAt,
    required this.details,
    this.targetId,
    this.merchantId,
    this.actorAppUserId,
    this.actorFirebaseUid,
    this.actorRole,
  });

  final String id;
  final String action;
  final String targetType;
  final String? targetId;
  final String? merchantId;
  final String? actorAppUserId;
  final String? actorFirebaseUid;
  final String? actorRole;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) {
    return AdminAuditEvent(
      id: _readString(json, 'id') ?? '',
      action: _readString(json, 'action') ?? 'admin.event',
      targetType: _readString(json, 'target_type') ?? 'unknown',
      targetId: _readString(json, 'target_id'),
      merchantId: _readString(json, 'merchant_id'),
      actorAppUserId: _readString(json, 'actor_app_user_id'),
      actorFirebaseUid: _readString(json, 'actor_firebase_uid'),
      actorRole: _readString(json, 'actor_role'),
      details: _readMap(json['details']),
      createdAt: _readDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

String? _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
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
