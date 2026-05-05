import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createV2Schema(db);
    await _createV3Schema(db);
    await _createV4Schema(db);
    await _createV5Schema(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migrate v1 → v2: recreate tables with new column names
      await db.execute('DROP TABLE IF EXISTS sales');
      await db.execute('DROP TABLE IF EXISTS customers');
      await _createV2Schema(db);
    }
    if (oldVersion < 3) {
      await _createV3Schema(db);
    }
    if (oldVersion < 4) {
      await _createV4Schema(db);
    }
    if (oldVersion < 5) {
      await _createV5Schema(db);
    }
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
    await db
        .execute('CREATE INDEX idx_sales_customer_id ON sales(customer_id)');
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

  Future<void> _createV3Schema(Database db) async {
    await db.execute('''
      CREATE TABLE redemptions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        reward_id TEXT NOT NULL,
        points_spent INTEGER NOT NULL,
        redeemed_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (reward_id) REFERENCES rewards(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_redemptions_customer_id ON redemptions(customer_id)');
    await db
        .execute('CREATE INDEX idx_redemptions_synced ON redemptions(synced)');
  }

  Future<void> _createV4Schema(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name_nocase ON customers(name COLLATE NOCASE)',
    );
  }

  Future<void> _createV5Schema(Database db) async {
    await db.execute(
      'ALTER TABLE rewards ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'UPDATE rewards SET updated_at = created_at WHERE updated_at = 0 OR updated_at IS NULL',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        entity_type TEXT PRIMARY KEY,
        last_value INTEGER,
        last_doc_id TEXT
      )
    ''');
  }

  // Injects a pre-opened database; used only in tests to avoid platform channels.
  void useForTest(Database db) => _db = db;

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
