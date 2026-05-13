import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import 'app_migrations.dart';

const _tag = 'DB';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), AppConstants.dbName);
    await AppMigrations.migrate(db, fromVersion: 0, toVersion: version);
    await _createV4Schema(db);
    await _createV5Schema(db);
    await _createV6Schema(db);
    try {
      await AppMigrations.migrate(
        db,
        fromVersion: oldVersion,
        toVersion: newVersion,
      );
    } catch (e, st) {
      Log.e(_tag, 'Migration failed. Attempting repair.', e, st);
      await AppMigrations.verifySchema(db);
      try {
        await AppMigrations.migrate(
          db,
          fromVersion: oldVersion,
          toVersion: newVersion,
        );
      } catch (retryError, retryStack) {
        Log.e(_tag, 'Migration retry failed.', retryError, retryStack);
        rethrow;
      }
    }
      await _createV10Schema(db);

  Future<void> _onOpen(Database db) async {
    try {
      await AppMigrations.verifySchema(db);
    } catch (e, st) {
      Log.e(_tag, 'Schema verification failed.', e, st);
      rethrow;
    }
  }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String columnDefinition,
  ) async {
    final columnName = columnDefinition.split(' ').first;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = columns.any((column) => column['name'] == columnName);
    if (!hasColumn) {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    }
  }

  // Injects a pre-opened database; used only in tests to avoid platform channels.
  void useForTest(Database db) => _db = db;

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
