import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class CustomerCacheEntry {
  const CustomerCacheEntry({
    required this.payload,
    required this.updatedAt,
    required this.lastSuccessfulRefreshAt,
  });

  final Map<String, dynamic> payload;
  final DateTime updatedAt;
  final DateTime lastSuccessfulRefreshAt;
}

class CustomerCacheDao {
  CustomerCacheDao(this._database);
  final AppDatabase _database;

  Future<CustomerCacheEntry?> read(String accountId, String key) async {
    final db = await _database.database;
    final rows = await db.query(
      'customer_app_cache',
      where: 'account_id = ? AND cache_key = ?',
      whereArgs: [accountId, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CustomerCacheEntry(
      payload: (jsonDecode(row['payload']! as String) as Map)
          .cast<String, dynamic>(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      lastSuccessfulRefreshAt: DateTime.fromMillisecondsSinceEpoch(
        row['last_successful_refresh_at']! as int,
      ),
    );
  }

  Future<void> write(
      String accountId, String key, Map<String, dynamic> payload) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _database.database;
    await db.insert(
        'customer_app_cache',
        {
          'account_id': accountId,
          'cache_key': key,
          'payload': jsonEncode(payload),
          'updated_at': now,
          'last_successful_refresh_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAccount(String accountId) async {
    final db = await _database.database;
    await db.delete(
      'customer_app_cache',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  Future<void> clearTransactionalData(String accountId) async {
    final db = await _database.database;
    await db.delete(
      'customer_app_cache',
      where:
          'account_id = ? AND (cache_key IN (?, ?, ?, ?) OR cache_key LIKE ?)',
      whereArgs: [
        accountId,
        'home',
        'businesses',
        'rewards',
        'activity',
        'business:%',
      ],
    );
  }

  Future<void> clear(String accountId, String key) async {
    final db = await _database.database;
    await db.delete(
      'customer_app_cache',
      where: 'account_id = ? AND cache_key = ?',
      whereArgs: [accountId, key],
    );
  }
}
