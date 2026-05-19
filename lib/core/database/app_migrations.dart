import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';

const _tag = 'DB';

typedef MigrationFn = Future<void> Function(DatabaseExecutor db);

class MigrationStep {
  const MigrationStep({
    required this.version,
    required this.name,
    required this.up,
  });

  final int version;
  final String name;
  final MigrationFn up;
}

class AppMigrations {
  static const int latestVersion = AppConstants.dbVersion;

  static final List<MigrationStep> steps = <MigrationStep>[
    MigrationStep(version: 2, name: 'baseline', up: _createV2Schema),
    MigrationStep(version: 3, name: 'redemptions', up: _createV3Schema),
    MigrationStep(version: 4, name: 'customer name index', up: _createV4Schema),
    MigrationStep(
        version: 5,
        name: 'rewards updated_at + sync_state',
        up: _createV5Schema),
    MigrationStep(version: 6, name: 'merchant scoping', up: _createV6Schema),
    MigrationStep(
        version: 7, name: 'subscription + usage', up: _createV7Schema),
    MigrationStep(version: 8, name: 'remote config', up: _createV8Schema),
    MigrationStep(version: 9, name: 'merchant streak', up: _createV9Schema),
    MigrationStep(version: 10, name: 'sync backoff', up: _createV10Schema),
    MigrationStep(version: 11, name: 'sms inbox', up: _createV11Schema),
    MigrationStep(
        version: 12, name: 'analytics + notifications', up: _createV12Schema),
    MigrationStep(version: 13, name: 'merchant backfill', up: _createV13Schema),
    MigrationStep(
        version: 14, name: 'customer device id', up: _createV14Schema),
    MigrationStep(
        version: 15,
        name: 'appointments + retention metrics',
        up: _createV15Schema),
  ];

  static Future<void> migrate(
    Database db, {
    required int fromVersion,
    required int toVersion,
  }) async {
    if (fromVersion >= toVersion) return;
    final runner = _MigrationRunner(steps);
    await runner.run(db, fromVersion: fromVersion, toVersion: toVersion);
  }

  static Future<void> verifySchema(Database db) async {
    final verifier = _SchemaVerifier();
    final needsRepair = await verifier.needsRepair(db);
    if (!needsRepair) return;
    Log.w(_tag, 'Schema verification failed. Running repair.');
    await verifier.repair(db);
  }
}

class _MigrationRunner {
  const _MigrationRunner(this.steps);

  final List<MigrationStep> steps;

  Future<void> run(
    Database db, {
    required int fromVersion,
    required int toVersion,
  }) async {
    final pending = steps
        .where(
            (step) => step.version > fromVersion && step.version <= toVersion)
        .toList()
      ..sort((a, b) => a.version.compareTo(b.version));

    if (pending.isEmpty) return;

    await db.transaction((txn) async {
      await _ensureMigrationLog(txn);
      for (final step in pending) {
        final applied = await _isApplied(txn, step.version);
        if (applied) {
          Log.d(_tag, 'Skipping migration v${step.version} (already applied)');
          continue;
        }
        Log.i(_tag, 'Applying migration v${step.version}: ${step.name}');
        await step.up(txn);
        await _recordApplied(txn, step);
      }
    });
  }

  Future<void> _ensureMigrationLog(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_log (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at INTEGER NOT NULL
      )
    ''');
  }

  Future<bool> _isApplied(DatabaseExecutor db, int version) async {
    final rows = await db.query(
      'migration_log',
      columns: ['version'],
      where: 'version = ?',
      whereArgs: [version],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _recordApplied(DatabaseExecutor db, MigrationStep step) async {
    await db.insert(
      'migration_log',
      {
        'version': step.version,
        'name': step.name,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

class _SchemaVerifier {
  static const Map<String, Set<String>> _criticalColumns = {
    'customers': {
      'id',
      'name',
      'phone',
      'total_points',
      'created_at',
      'updated_at',
      'synced',
      'merchant_id',
      'device_id',
    },
    'sales': {
      'id',
      'customer_id',
      'amount',
      'points',
      'created_at',
      'synced',
      'merchant_id',
      'device_id',
    },
    'rewards': {
      'id',
      'name',
      'points_required',
      'description',
      'active',
      'created_at',
      'updated_at',
      'synced',
      'merchant_id',
    },
    'redemptions': {
      'id',
      'customer_id',
      'reward_id',
      'points_spent',
      'redeemed_at',
      'synced',
      'merchant_id',
    },
    'sync_queue': {
      'id',
      'operation',
      'entity_type',
      'entity_id',
      'payload',
      'created_at',
      'retry_count',
      'status',
      'merchant_id',
      'device_id',
      'next_attempt_at',
    },
    'sync_state': {'entity_type', 'last_value', 'last_doc_id'},
    'appointments': {
      'id',
      'merchant_id',
      'customer_id',
      'scheduled_date',
      'status',
      'source',
      'reminder_sent',
      'created_at',
      'updated_at',
      'synced',
    },
    'retention_metrics': {
      'id',
      'merchant_id',
      'customer_id',
      'last_visit_at',
      'days_inactive',
      'risk_level',
      'total_visits',
      'average_visit_interval',
      'total_spent',
      'is_recurring',
      'recovered',
      'updated_at',
      'synced',
    },
  };

  Future<bool> needsRepair(Database db) async {
    for (final entry in _criticalColumns.entries) {
      final exists = await _tableExists(db, entry.key);
      if (!exists) {
        return true;
      }
      final columns = await _columnsFor(db, entry.key);
      for (final required in entry.value) {
        if (!columns.contains(required)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> repair(Database db) async {
    await db.transaction((txn) async {
      await _createV2Schema(txn);
      await _createV3Schema(txn);
      await _createV4Schema(txn);
      await _createV5Schema(txn);
      await _createV6Schema(txn);
      await _createV7Schema(txn);
      await _createV8Schema(txn);
      await _createV9Schema(txn);
      await _createV10Schema(txn);
      await _createV11Schema(txn);
      await _createV12Schema(txn);
      await _createV13Schema(txn);
      await _createV14Schema(txn);
      await _createV15Schema(txn);
    });
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> _columnsFor(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();
  }
}

Future<void> _createV2Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT UNIQUE NOT NULL,
      total_points INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS sales (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      amount REAL NOT NULL,
      points INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_customer_id ON sales(customer_id)',
  );
  await db
      .execute('CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(synced)');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS rewards (
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
    CREATE TABLE IF NOT EXISTS sync_queue (
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
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_status ON sync_queue(status)',
  );
}

Future<void> _createV3Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS redemptions (
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
    'CREATE INDEX IF NOT EXISTS idx_redemptions_customer_id ON redemptions(customer_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_redemptions_synced ON redemptions(synced)',
  );
}

Future<void> _createV4Schema(DatabaseExecutor db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_name_nocase ON customers(name COLLATE NOCASE)',
  );
}

Future<void> _createV5Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(
    db,
    'rewards',
    'updated_at INTEGER NOT NULL DEFAULT 0',
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

Future<void> _createV6Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchants (
      id TEXT PRIMARY KEY,
      phone TEXT NOT NULL UNIQUE,
      merchant_name TEXT NOT NULL DEFAULT 'Minha Loja',
      slug TEXT NOT NULL UNIQUE,
      subscription_status TEXT NOT NULL DEFAULT 'TRIAL',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS app_users (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      phone TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'OWNER',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_login_at INTEGER,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_app_users_merchant_id ON app_users(merchant_id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_merchant_phone ON app_users(merchant_id, phone)',
  );

  await _addColumnIfMissing(db, 'customers', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sales', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sales', 'device_id TEXT');
  await _addColumnIfMissing(db, 'rewards', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'redemptions', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sync_queue', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sync_queue', 'device_id TEXT');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_merchant_id ON customers(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_merchant_id ON sales(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_rewards_merchant_id ON rewards(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_redemptions_merchant_id ON redemptions(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_queue_merchant_status ON sync_queue(merchant_id, status)',
  );
}

Future<void> _createV7Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS subscription_state (
      merchant_id TEXT PRIMARY KEY,
      plan_code TEXT NOT NULL,
      plan_name TEXT NOT NULL,
      plan_version INTEGER NOT NULL DEFAULT 1,
      pricing_version INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'TRIAL',
      trial_ends_at INTEGER,
      grace_ends_at INTEGER,
      period_start INTEGER,
      period_end INTEGER,
      updated_at INTEGER NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS entitlements (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      feature_key TEXT NOT NULL,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      limit_value INTEGER,
      unit TEXT,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_entitlements_merchant_feature ON entitlements(merchant_id, feature_key)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS feature_flags (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      flag_key TEXT NOT NULL,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      payload TEXT,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_feature_flags_merchant_flag ON feature_flags(merchant_id, flag_key)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS usage_events (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      metric_key TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      occurred_at INTEGER NOT NULL,
      source TEXT,
      metadata TEXT,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_usage_events_metric ON usage_events(merchant_id, metric_key, occurred_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_usage_events_synced ON usage_events(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS usage_balances (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      metric_key TEXT NOT NULL,
      window_start INTEGER NOT NULL,
      window_end INTEGER NOT NULL,
      used INTEGER NOT NULL DEFAULT 0,
      limit_value INTEGER,
      soft_limit INTEGER NOT NULL DEFAULT 1,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_balances_window ON usage_balances(merchant_id, metric_key, window_start, window_end)',
  );
}

Future<void> _createV8Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS remote_config (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      config_key TEXT NOT NULL,
      payload TEXT,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_config_merchant_key ON remote_config(merchant_id, config_key)',
  );
}

Future<void> _createV9Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(
    db,
    'merchants',
    'streak_days INTEGER NOT NULL DEFAULT 0',
  );
}

Future<void> _createV10Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(
    db,
    'sync_queue',
    'next_attempt_at INTEGER NOT NULL DEFAULT 0',
  );
}

Future<void> _createV11Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_inbox (
      id TEXT PRIMARY KEY,
      address TEXT,
      body TEXT NOT NULL,
      received_at INTEGER NOT NULL,
      processed INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sms_inbox_processed ON sms_inbox(processed, received_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_transactions (
      id TEXT PRIMARY KEY,
      provider TEXT NOT NULL,
      transaction_id TEXT,
      amount REAL NOT NULL,
      phone TEXT,
      received_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sms_transactions_provider ON sms_transactions(provider, transaction_id)',
  );
}

Future<void> _createV12Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS analytics_events (
      id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      occurred_at INTEGER NOT NULL,
      source TEXT,
      device_id TEXT,
      app_version TEXT,
      properties TEXT,
      synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_analytics_events_synced ON analytics_events(synced, occurred_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS notification_queue (
      id TEXT PRIMARY KEY,
      channel TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      scheduled_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_notification_queue_status ON notification_queue(status, scheduled_at)',
  );
}

Future<void> _createV13Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'customers', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sales', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sales', 'device_id TEXT');
  await _addColumnIfMissing(db, 'rewards', 'merchant_id TEXT');
  await _addColumnIfMissing(
    db,
    'rewards',
    'updated_at INTEGER NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(db, 'redemptions', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sync_queue', 'merchant_id TEXT');
  await _addColumnIfMissing(db, 'sync_queue', 'device_id TEXT');
  await _addColumnIfMissing(
    db,
    'sync_queue',
    'next_attempt_at INTEGER NOT NULL DEFAULT 0',
  );

  await db.execute(
    'UPDATE rewards SET updated_at = created_at WHERE updated_at = 0 OR updated_at IS NULL',
  );

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_merchant_id ON customers(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_merchant_id ON sales(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_rewards_merchant_id ON rewards(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_redemptions_merchant_id ON redemptions(merchant_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_queue_merchant_status ON sync_queue(merchant_id, status)',
  );
}

Future<void> _createV14Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'customers', 'device_id TEXT');
}

Future<void> _createV15Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS appointments (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      scheduled_date INTEGER NOT NULL,
      status TEXT NOT NULL,
      source TEXT NOT NULL,
      reminder_sent INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_appointments_merchant_date ON appointments(merchant_id, scheduled_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_appointments_merchant_status ON appointments(merchant_id, status, scheduled_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_appointments_synced ON appointments(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS retention_metrics (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      last_visit_at INTEGER,
      days_inactive INTEGER NOT NULL DEFAULT 0,
      risk_level TEXT NOT NULL,
      total_visits INTEGER NOT NULL DEFAULT 0,
      average_visit_interval INTEGER,
      total_spent REAL NOT NULL DEFAULT 0,
      is_recurring INTEGER NOT NULL DEFAULT 0,
      recovered INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_retention_metrics_merchant_risk ON retention_metrics(merchant_id, risk_level, days_inactive)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_retention_metrics_merchant_last_visit ON retention_metrics(merchant_id, last_visit_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_retention_metrics_synced ON retention_metrics(merchant_id, synced)',
  );
}

Future<void> _addColumnIfMissing(
  DatabaseExecutor db,
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
