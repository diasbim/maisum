import '../../../core/database/app_database.dart';
import '../domain/usage_event.dart';

class UsageEventDao {
  UsageEventDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;

  Future<void> insert(UsageEvent event) async {
    final db = await _db.database;
    await db.insert('usage_events', event.toDbMap());
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'usage_events',
      {'synced': 1},
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<int> getPendingCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) as count FROM usage_events WHERE synced = 0'
          : 'SELECT COUNT(*) as count FROM usage_events WHERE merchant_id = ? AND synced = 0',
      merchantId == null ? const [] : [merchantId],
    );
    return result.first['count'] as int? ?? 0;
  }

  String _withMerchantScope(String clause) {
    if (merchantId == null) {
      return clause;
    }
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _withMerchantArgs(List<Object?> args) {
    if (merchantId == null) {
      return args;
    }
    return [merchantId, ...args];
  }
}
