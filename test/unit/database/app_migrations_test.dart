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
      singleInstance: false,
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

    final syncQueueCols = await _columns(db, 'sync_queue');
    expect(syncQueueCols.contains('last_error'), isTrue);
  });

  test('v23 adds general appointment details', () async {
    final db = await _openDb(version: 22);

    await AppMigrations.migrate(db, fromVersion: 22, toVersion: 23);

    final cols = await _columns(db, 'appointments');
    expect(cols, contains('merchant_item_id'));
    expect(cols, contains('staff_app_user_id'));
    expect(cols, contains('duration_minutes'));
    expect(cols, contains('notes'));
  });

  test('v24 adds Customer Core projection and preserves customers', () async {
    final db = await _openDb(version: 23);
    await db.insert('customers', {
      'id': 'c1',
      'merchant_id': 'm1',
      'name': 'Ana',
      'phone': '841234567',
      'total_points': 12,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
    });

    await AppMigrations.migrate(db, fromVersion: 23, toVersion: 24);

    final cols = await _columns(db, 'customers');
    expect(
      cols,
      containsAll(<String>[
        'canonical_customer_id',
        'account_state',
        'relationship_status',
        'lifecycle_stage',
        'retention_status',
        'first_visit_at',
        'last_visit_at',
        'total_visits',
        'total_spent',
        'average_spend',
        'average_visit_interval_days',
        'marketing_consent_status',
        'whatsapp_consent_status',
        'schema_version',
      ]),
    );

    final row = (await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: ['c1'],
    ))
        .single;
    expect(row['name'], 'Ana');
    expect(row['account_state'], 'UNCLAIMED');
    expect(row['lifecycle_stage'], 'NEW');
    expect(row['retention_status'], 'HEALTHY');
    expect(row['total_visits'], 0);
  });

  test('v25 adds loyalty ledger and confirmation projections', () async {
    final db = await _openDb(version: 24);
    await db.insert('customers', {
      'id': 'c1',
      'merchant_id': 'm1',
      'name': 'Ana',
      'phone': '841234567',
      'total_points': 12,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
    });
    await db.insert('sales', {
      'id': 's1',
      'merchant_id': 'm1',
      'customer_id': 'c1',
      'amount': 200,
      'points': 2,
      'created_at': 10,
      'synced': 0,
    });

    await AppMigrations.migrate(db, fromVersion: 24, toVersion: 25);

    expect(
      await _columns(db, 'customers'),
      contains('confirmed_points'),
    );
    expect(
      await _columns(db, 'sales'),
      containsAll(<String>[
        'updated_at',
        'confirmation_status',
        'confirmed_points',
        'confirmed_at',
        'confirmation_error_code',
        'loyalty_policy_version',
      ]),
    );
    expect(
      await _columns(db, 'loyalty_ledger'),
      containsAll(<String>[
        'customer_id',
        'entry_type',
        'points_delta',
        'source_type',
        'source_id',
        'balance_after',
      ]),
    );
    expect(
      await _columns(db, 'redemption_requests'),
      containsAll(<String>[
        'customer_id',
        'reward_id',
        'points_required',
        'status',
        'last_error',
      ]),
    );

    final sale = (await db.query('sales')).single;
    expect(sale['updated_at'], 10);
    expect(sale['confirmation_status'], 'PENDING');
  });

  test('v26 adds customer app cache partition', () async {
    final db = await _openDb(version: 25);
    await AppMigrations.migrate(db, fromVersion: 25, toVersion: 26);

    expect(
      await _columns(db, 'customer_app_cache'),
      containsAll(<String>[
        'account_id',
        'cache_key',
        'payload',
        'updated_at',
        'last_successful_refresh_at',
      ]),
    );
  });

  test('v27 adds customer archive, sale cancellation and tombstones', () async {
    final db = await _openDb(version: 26);
    await AppMigrations.migrate(db, fromVersion: 26, toVersion: 27);

    expect(
      await _columns(db, 'customers'),
      containsAll(<String>[
        'archived_at',
        'archived_by_app_user_id',
      ]),
    );
    expect(
      await _columns(db, 'sales'),
      containsAll(<String>[
        'cancellation_status',
        'cancelled_at',
        'cancelled_by_app_user_id',
        'cancellation_reason',
        'replacement_sale_id',
      ]),
    );
    expect(
      await _columns(db, 'sync_tombstones'),
      containsAll(<String>[
        'id',
        'merchant_id',
        'entity_type',
        'entity_id',
        'deleted_at',
      ]),
    );
  });
}
