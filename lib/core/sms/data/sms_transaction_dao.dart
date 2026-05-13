import 'package:sqflite/sqflite.dart';

import '../../database/app_database.dart';

class SmsTransactionDao {
  SmsTransactionDao(this._db);

  final AppDatabase _db;

  Future<bool> exists(String hash) async {
    final db = await _db.database;
    final rows = await db.query(
      'sms_transactions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> insert({
    required String hash,
    required String provider,
    String? transactionId,
    required double amount,
    String? phone,
    required DateTime receivedAt,
  }) async {
    final db = await _db.database;
    await db.insert(
      'sms_transactions',
      {
        'id': hash,
        'provider': provider,
        'transaction_id': transactionId,
        'amount': amount,
        'phone': phone,
        'received_at': receivedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
