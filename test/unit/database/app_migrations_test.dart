import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:maisum/core/database/app_migrations.dart';

Future<Database> _openDb({required int version}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, createdVersion) async {
        await AppMigrations.migrate(
          db,
          fromVersion: 0,
          toVersion: createdVersion,
        );
      },
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String?).whereType<String>().toSet();
}

void main() {
  test('migrates v13 to v14 and preserves data', () async {
    final db = await _openDb(version: 13);
    await db.insert('customers', {
      'id': 'c1',
      'name': 'Ana',
      'phone': '841234567',
      'total_points': 12,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
      'merchant_id': 'm1',
    });

    await AppMigrations.migrate(db, fromVersion: 13, toVersion: 14);

    final cols = await _columns(db, 'customers');
    expect(cols.contains('device_id'), isTrue);

    final rows =
        await db.query('customers', where: 'id = ?', whereArgs: ['c1']);
    expect(rows.single['name'], 'Ana');
  });

  test('verifySchema repairs missing columns', () async {
    final db = await _openDb(version: 13);

    await AppMigrations.verifySchema(db);

    final cols = await _columns(db, 'customers');
    expect(cols.contains('device_id'), isTrue);
  });
}
