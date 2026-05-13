import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_item.freezed.dart';
part 'sync_item.g.dart';

@freezed
class SyncItem with _$SyncItem {
  const SyncItem._();

  const factory SyncItem({
    required String id,
    required String operation,
    required String entityType,
    required String entityId,
    required String payload,
    @Default(0) int retryCount,
    @Default('pending') String status,
    DateTime? nextAttemptAt,
    required DateTime createdAt,
  }) = _SyncItem;

  factory SyncItem.fromJson(Map<String, dynamic> json) =>
      _$SyncItemFromJson(json);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'operation': operation,
        'entity_type': entityType,
        'entity_id': entityId,
        'payload': payload,
        'retry_count': retryCount,
        'status': status,
        'next_attempt_at': nextAttemptAt?.millisecondsSinceEpoch ?? 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

SyncItem syncItemFromMap(Map<String, dynamic> map) => SyncItem(
      id: map['id'] as String,
      operation: map['operation'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      payload: map['payload'] as String,
      retryCount: map['retry_count'] as int? ?? 0,
      status: map['status'] as String? ?? 'pending',
      nextAttemptAt: (map['next_attempt_at'] as int? ?? 0) > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              map['next_attempt_at'] as int,
            )
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
