import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../domain/sync_item.dart';

class SyncDao {
  SyncDao(this._db);

  final AppDatabase _db;

  Future<void> enqueue(SyncItem item) async {
    final db = await _db.database;
    await db.insert('sync_queue', item.toDbMap());
  }

  Future<List<SyncItem>> getPending() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_queue',
      where: 'status = ? AND retry_count < ?',
      whereArgs: ['pending', AppConstants.maxSyncRetries],
      orderBy: 'created_at ASC',
    );
    return rows.map(syncItemFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(String id) async {
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'status': 'failed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementRetry(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  Future<int> getPendingCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue WHERE status = ? AND retry_count < ?',
      ['pending', AppConstants.maxSyncRetries],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<SyncItem>> getAllItems() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_queue',
      where: 'status != ?',
      whereArgs: ['synced'],
      orderBy: 'created_at DESC',
    );
    return rows.map(syncItemFromMap).toList();
  }

  Future<void> clearSynced() async {
    final db = await _db.database;
    await db.delete('sync_queue', where: 'status = ?', whereArgs: ['synced']);
  }
}
