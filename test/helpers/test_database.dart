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

/// A database on disk, so a test can close it and open it again.
///
/// The in-memory database above is faster and is what almost every test should
/// use, but it cannot answer the one question an offline feature has to answer:
/// does a queued operation survive the app being killed? A file is the only
/// honest way to ask that, and an operation held only in memory is one a crash
/// turns into an affiliate who is never paid.
Future<Database> setUpFileTestDatabase() async {
  _overrideSqliteOnWindows();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final directory = Directory('.dart_tool/test_databases')
    ..createSync(recursive: true);
  // Absolute, because sqflite_common_ffi resolves a relative path under its own
  // databases directory — the file would then be written somewhere the teardown
  // is not looking, and every run would leave one behind.
  _filePath = '${directory.absolute.path}'
      '/test_${DateTime.now().microsecondsSinceEpoch}_${_fileCounter++}.db';
  return _openFileTestDatabase();
}

/// Closes the database and opens the same file again, as a restart would.
Future<Database> reopenFileTestDatabase() async {
  await AppDatabase.instance.close();
  return _openFileTestDatabase();
}

Future<void> tearDownFileTestDatabase() async {
  await AppDatabase.instance.close();
  final path = _filePath;
  _filePath = null;
  if (path == null) return;
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
}

String? _filePath;
int _fileCounter = 0;

Future<Database> _openFileTestDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(
    _filePath!,
    options: OpenDatabaseOptions(
      version: AppMigrations.latestVersion,
      singleInstance: false,
      onCreate: (db, version) async {
        await AppMigrations.migrate(db, fromVersion: 0, toVersion: version);
      },
      onUpgrade: (db, from, to) async {
        await AppMigrations.migrate(db, fromVersion: from, toVersion: to);
      },
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  AppDatabase.instance.useForTest(db);
  return db;
}

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
