import 'dart:ffi';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/database/app_migrations.dart';

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
      version: AppMigrations.latestVersion,
      onCreate: (db, version) async {
        await AppMigrations.migrate(
          db,
          fromVersion: 0,
          toVersion: version,
        );
      },
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
