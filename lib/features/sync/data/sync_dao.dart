import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../domain/sync_item.dart';

class SyncQueueStats {
  const SyncQueueStats({
    required this.pendingTotal,
    required this.pendingReady,
    required this.failed,
    this.nextRetryAt,
  });

  final int pendingTotal;
  final int pendingReady;
  final int failed;
  final DateTime? nextRetryAt;
}

class SyncDao {
  SyncDao(this._db, {this.merchantId, this.deviceId});

  final AppDatabase _db;
  final String? merchantId;
  final String? deviceId;

  Future<void> enqueue(SyncItem item) async {
    final db = await _db.database;
    await db.insert('sync_queue', {
      ...item.toDbMap(),
      'merchant_id': merchantId,
      'device_id': deviceId,
    });
  }

  Future<List<SyncItem>> getPending() async {
    final db = await _db.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'sync_queue',
      where: merchantId == null
          ? 'status = ? AND retry_count < ? AND next_attempt_at <= ?'
          : 'merchant_id = ? AND status = ? AND retry_count < ? AND next_attempt_at <= ?',
      whereArgs: merchantId == null
          ? ['pending', AppConstants.maxSyncRetries, nowMs]
          : [merchantId, 'pending', AppConstants.maxSyncRetries, nowMs],
      orderBy: 'created_at ASC',
    );
    return rows.map(syncItemFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'status': 'synced', 'next_attempt_at': 0},
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<void> markFailed(String id) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'status': 'failed', 'next_attempt_at': 0},
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<void> incrementRetry(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      merchantId == null
          ? 'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?'
          : 'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE merchant_id = ? AND id = ?',
      merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<void> scheduleRetry(String id, DateTime nextAttempt) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'next_attempt_at': nextAttempt.millisecondsSinceEpoch},
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<int> getPendingCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) as count FROM sync_queue WHERE status = ? AND retry_count < ?'
          : 'SELECT COUNT(*) as count FROM sync_queue WHERE merchant_id = ? AND status = ? AND retry_count < ?',
      merchantId == null
          ? ['pending', AppConstants.maxSyncRetries]
          : [merchantId, 'pending', AppConstants.maxSyncRetries],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<int> getFailedCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) as count FROM sync_queue WHERE status = ?'
          : 'SELECT COUNT(*) as count FROM sync_queue WHERE merchant_id = ? AND status = ?',
      merchantId == null ? ['failed'] : [merchantId, 'failed'],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<SyncQueueStats> getStats() async {
    final db = await _db.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final args = <Object?>[
      'pending',
      AppConstants.maxSyncRetries,
      'pending',
      AppConstants.maxSyncRetries,
      nowMs,
      'failed',
      'pending',
      nowMs,
    ];

    final whereClause = merchantId == null ? '' : 'WHERE merchant_id = ?';
    final whereArgs = merchantId == null ? <Object?>[] : [merchantId];

    final rows = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN status = ? AND retry_count < ? THEN 1 ELSE 0 END) AS pending_total,
        SUM(CASE WHEN status = ? AND retry_count < ? AND next_attempt_at <= ? THEN 1 ELSE 0 END) AS pending_ready,
        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS failed,
        MIN(CASE WHEN status = ? AND retry_count > 0 AND next_attempt_at > ? THEN next_attempt_at ELSE NULL END) AS next_retry_at
      FROM sync_queue
      $whereClause
      ''',
      merchantId == null ? args : [...args, ...whereArgs],
    );

    final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};
    final pendingTotal = (row['pending_total'] as int?) ?? 0;
    final pendingReady = (row['pending_ready'] as int?) ?? 0;
    final failed = (row['failed'] as int?) ?? 0;
    final nextRetryRaw = row['next_retry_at'] as int?;

    return SyncQueueStats(
      pendingTotal: pendingTotal,
      pendingReady: pendingReady,
      failed: failed,
      nextRetryAt: nextRetryRaw == null || nextRetryRaw <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextRetryRaw),
    );
  }

  Future<List<SyncItem>> getAllItems() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_queue',
      where: merchantId == null
          ? 'status != ?'
          : 'merchant_id = ? AND status != ?',
      whereArgs: merchantId == null ? ['synced'] : [merchantId, 'synced'],
      orderBy: 'created_at DESC',
    );
    return rows.map(syncItemFromMap).toList();
  }

  Future<void> clearSynced() async {
    final db = await _db.database;
    await db.delete(
      'sync_queue',
      where:
          merchantId == null ? 'status = ?' : 'merchant_id = ? AND status = ?',
      whereArgs: merchantId == null ? ['synced'] : [merchantId, 'synced'],
    );
  }
}
