import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../domain/sync_item.dart';

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
    final rows = await db.query(
      'sync_queue',
      where: merchantId == null
          ? 'status = ? AND retry_count < ?'
          : 'merchant_id = ? AND status = ? AND retry_count < ?',
      whereArgs: merchantId == null
          ? ['pending', AppConstants.maxSyncRetries]
          : [merchantId, 'pending', AppConstants.maxSyncRetries],
      orderBy: 'created_at ASC',
    );
    return rows.map(syncItemFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'status': 'synced'},
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null ? [id] : [merchantId, id],
    );
  }

  Future<void> markFailed(String id) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'status': 'failed'},
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
      where: merchantId == null
          ? 'status = ?'
          : 'merchant_id = ? AND status = ?',
      whereArgs: merchantId == null ? ['synced'] : [merchantId, 'synced'],
    );
  }
}
