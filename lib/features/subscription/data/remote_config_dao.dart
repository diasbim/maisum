import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/remote_config.dart';

class RemoteConfigDao {
  RemoteConfigDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;

  Future<RemoteConfigEntry?> getConfig(String configKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'remote_config',
      where: _withMerchantScope('config_key = ?'),
      whereArgs: _withMerchantArgs([configKey]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return remoteConfigEntryFromMap(rows.first);
  }

  Future<List<RemoteConfigEntry>> getAllConfigs() async {
    final db = await _db.database;
    final rows = await db.query(
      'remote_config',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'config_key ASC',
    );
    return rows.map(remoteConfigEntryFromMap).toList();
  }

  Future<void> upsertConfig(RemoteConfigEntry config) async {
    final db = await _db.database;
    await db.insert(
      'remote_config',
      config.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
