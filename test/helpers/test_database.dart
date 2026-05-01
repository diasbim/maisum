import 'dart:ffi';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:loyalty_app/core/database/app_database.dart';

/// Creates an isolated in-memory SQLite database and injects it into
/// [AppDatabase.instance] for the duration of a test.
///
/// Call [setUpTestDatabase] in `setUp` and [tearDownTestDatabase] in `tearDown`.
Future<Database> setUpTestDatabase() async {
  _overrideSqliteOnWindows();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) => _createV2Schema(db),
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );

  AppDatabase.instance.useForTest(db);
  return db;
}

Future<void> tearDownTestDatabase() => AppDatabase.instance.close();

// sqlite3 2.x does not auto-download its DLL; we point it at an existing one.
// Override SQLITE3_LIBRARY env var to use a different path.
void _overrideSqliteOnWindows() {
  if (!Platform.isWindows) return;
  final path = Platform.environment['SQLITE3_LIBRARY'] ??
      r'C:\Users\X200078\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\DLLs\sqlite3.dll';
  sqlite_open.open.overrideFor(
    sqlite_open.OperatingSystem.windows,
    () => DynamicLibrary.open(path),
  );
}

Future<void> _createV2Schema(Database db) async {
  await db.execute('''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT UNIQUE NOT NULL,
      total_points INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('CREATE INDEX idx_customers_phone ON customers(phone)');

  await db.execute('''
    CREATE TABLE sales (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      amount REAL NOT NULL,
      points INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute('CREATE INDEX idx_sales_customer_id ON sales(customer_id)');
  await db.execute('CREATE INDEX idx_sales_synced ON sales(synced)');
  await db.execute('CREATE INDEX idx_sales_created_at ON sales(created_at)');

  await db.execute('''
    CREATE TABLE rewards (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      points_required INTEGER NOT NULL,
      description TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE sync_queue (
      id TEXT PRIMARY KEY,
      operation TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      retry_count INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute('CREATE INDEX idx_sync_status ON sync_queue(status)');
}
