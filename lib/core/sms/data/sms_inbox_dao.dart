import 'package:sqflite/sqflite.dart';

import '../../database/app_database.dart';
import '../domain/sms_envelope.dart';

class SmsInboxEntry {
  const SmsInboxEntry({required this.id, required this.envelope});

  final String id;
  final SmsEnvelope envelope;
}

class SmsInboxDao {
  SmsInboxDao(this._db);

  final AppDatabase _db;

  Future<void> insert(SmsEnvelope envelope, {required String id}) async {
    final db = await _db.database;
    await db.insert(
      'sms_inbox',
      {
        'id': id,
        'address': envelope.address,
        'body': envelope.body,
        'received_at':
            (envelope.receivedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'processed': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<SmsInboxEntry>> getPending({int limit = 20}) async {
    final db = await _db.database;
    final rows = await db.query(
      'sms_inbox',
      where: 'processed = 0',
      orderBy: 'received_at DESC',
      limit: limit,
    );

    return rows
        .map(
          (row) => SmsInboxEntry(
            id: row['id'] as String,
            envelope: SmsEnvelope(
              body: row['body'] as String,
              address: row['address'] as String?,
              receivedAt: DateTime.fromMillisecondsSinceEpoch(
                row['received_at'] as int,
              ),
            ),
          ),
        )
        .toList();
  }

  Future<void> markProcessed(String id) async {
    final db = await _db.database;
    await db.delete(
      'sms_inbox',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
