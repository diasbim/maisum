import '../../database/app_database.dart';
import '../domain/analytics_event.dart';

class AnalyticsEventDao {
  AnalyticsEventDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;

  Future<void> insert(AnalyticsEvent event) async {
    final db = await _db.database;
    await db.insert('analytics_events', event.toDbMap());
  }

  Future<List<AnalyticsEvent>> getPending({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'analytics_events',
      where: 'synced = 0',
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return rows.map(AnalyticsEvent.fromMap).toList();
  }

  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE analytics_events SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }
}
