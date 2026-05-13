import '../../database/app_database.dart';
import '../domain/notification_queue_item.dart';

class NotificationQueueDao {
  NotificationQueueDao(this._db);

  final AppDatabase _db;

  Future<void> insert(NotificationQueueItem item) async {
    final db = await _db.database;
    await db.insert('notification_queue', item.toDbMap());
  }

  Future<List<NotificationQueueItem>> getPending({int limit = 20}) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'notification_queue',
      where: 'status = ? AND scheduled_at <= ?',
      whereArgs: ['pending', now],
      orderBy: 'scheduled_at ASC',
      limit: limit,
    );
    return rows.map(NotificationQueueItem.fromMap).toList();
  }

  Future<void> markSent(String id) async {
    final db = await _db.database;
    await db.update(
      'notification_queue',
      {'status': 'sent'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reschedule(
    String id, {
    required DateTime nextAttempt,
    required int retryCount,
    String? lastError,
  }) async {
    final db = await _db.database;
    await db.update(
      'notification_queue',
      {
        'scheduled_at': nextAttempt.millisecondsSinceEpoch,
        'retry_count': retryCount,
        'last_error': lastError,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
