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
    const MigrationStep(version: 2, name: 'baseline', up: _createV2Schema),
    const MigrationStep(version: 3, name: 'redemptions', up: _createV3Schema),
    const MigrationStep(
      version: 4,
      name: 'customer name index',
      up: _createV4Schema,
    ),
    const MigrationStep(
      version: 5,
      name: 'rewards updated_at + sync_state',
      up: _createV5Schema,
    ),
    const MigrationStep(
      version: 6,
      name: 'merchant scoping',
      up: _createV6Schema,
    ),
    const MigrationStep(
      version: 7,
      name: 'subscription + usage',
      up: _createV7Schema,
    ),
    const MigrationStep(version: 8, name: 'remote config', up: _createV8Schema),
    const MigrationStep(
      version: 9,
      name: 'merchant streak',
      up: _createV9Schema,
    ),
    const MigrationStep(
      version: 10,
      name: 'sync backoff',
      up: _createV10Schema,
    ),
    const MigrationStep(
      version: 12,
      name: 'analytics + notifications',
      up: _createV12Schema,
    ),
    const MigrationStep(
      version: 13,
      name: 'merchant backfill',
      up: _createV13Schema,
    ),
    const MigrationStep(
      version: 14,
      name: 'customer device id',
      up: _createV14Schema,
    ),
    const MigrationStep(
      version: 15,
      name: 'appointments + retention metrics',
      up: _createV15Schema,
    ),
    const MigrationStep(
      version: 16,
      name: 'customers phone scoped uniqueness',
      up: _createV16Schema,
    ),
    const MigrationStep(
      version: 17,
      name: 'appointments device id',
      up: _createV17Schema,
    ),
    const MigrationStep(
      version: 18,
      name: 'engage foundation tables',
      up: _createV18Schema,
    ),
    const MigrationStep(
      version: 19,
      name: 'staff lifecycle fields',
      up: _createV19Schema,
    ),
    const MigrationStep(
      version: 20,
      name: 'record authorship fields',
      up: _createV20Schema,
    ),
    const MigrationStep(
      version: 21,
      name: 'sync queue last_error',
      up: _createV21Schema,
    ),
    const MigrationStep(
      version: 22,
      name: 'merchant catalog + sale items',
      up: _createV22Schema,
    ),
    const MigrationStep(
      version: 23,
      name: 'general appointment details',
      up: _createV23Schema,
    ),
    const MigrationStep(
      version: 24,
      name: 'customer core projection',
      up: _createV24Schema,
    ),
    const MigrationStep(
      version: 25,
      name: 'loyalty ledger and confirmations',
      up: _createV25Schema,
    ),
    const MigrationStep(
      version: 26,
      name: 'customer app read cache',
      up: _createV26Schema,
    ),
    const MigrationStep(
      version: 27,
      name: 'customer archive and sale cancellation',
      up: _createV27Schema,
    ),
    const MigrationStep(
      version: 28,
      name: 'customer nfc card cache',
      up: _createV28Schema,
    ),
    const MigrationStep(
      version: 29,
      name: 'retention engine: return bonuses',
      up: _createV29Schema,
    ),
    const MigrationStep(
      version: 30,
      name: 'affiliates foundation',
      up: _createV30Schema,
    ),
    const MigrationStep(
      version: 31,
      name: 'affiliates offline queue projection',
      up: _createV31Schema,
    ),
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
          (step) => step.version > fromVersion && step.version <= toVersion,
        )
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
        conflictAlgorithm: ConflictAlgorithm.ignore);
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
      'confirmed_points',
      'archived_at',
      'archived_by_app_user_id',
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
      'updated_at',
      'confirmation_status',
      'confirmed_points',
      'confirmed_at',
      'confirmation_error_code',
      'loyalty_policy_version',
      'cancellation_status',
      'cancelled_at',
      'cancelled_by_app_user_id',
      'cancellation_reason',
      'replacement_sale_id',
      'gross_amount',
      'referral_benefit_type',
      'referral_benefit_value',
      'referral_benefit_amount',
      'affiliate_code_id',
      'referral_status',
      'referral_code_input',
      'affiliate_id',
      'referral_rejection_code',
      'referral_status_message',
      'referral_local_benefit_applied',
      'referral_idempotency_key',
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
      'last_error',
      'local_id',
      'idempotency_key',
      'last_sync_error',
    },
    'affiliates': {
      'id',
      'phone',
      'normalized_phone',
      'first_name',
      'last_name',
      'display_name',
      'status',
      'created_at',
      'updated_at',
      'synced',
      'provisional',
      'local_id',
      'sync_status',
      'last_sync_error',
    },
    'affiliate_merchants': {
      'id',
      'merchant_id',
      'affiliate_id',
      'status',
      'linked_at',
      'created_at',
      'updated_at',
      'synced',
      'provisional',
      'local_id',
      'sync_status',
      'last_sync_error',
    },
    'affiliate_codes': {
      'id',
      'merchant_id',
      'affiliate_id',
      'code',
      'normalized_code',
      'benefit_type',
      'benefit_value',
      'starts_at',
      'expires_at',
      'usage_limit',
      'usage_count',
      'first_visit_only',
      'status',
      'created_at',
      'updated_at',
      'synced',
      'provisional',
      'local_id',
      'sync_status',
      'last_sync_error',
    },
    'affiliate_code_lookup_cache': {
      'normalized_code',
      'code_id',
      'merchant_id',
      'affiliate_id',
      'code',
      'status',
      'benefit_type',
      'benefit_value',
      'starts_at',
      'expires_at',
      'usage_limit',
      'usage_count',
      'first_visit_only',
      'cached_at',
      'updated_at',
      'affiliate_display_name',
      'affiliate_first_name',
      'affiliate_status',
      'link_status',
      'refreshed_at',
    },
    'affiliate_attributions': {
      'id',
      'merchant_id',
      'affiliate_id',
      'affiliate_code_id',
      'customer_id',
      'qualifying_sale_id',
      'status',
      'rejection_code',
      'attributed_at',
      'first_sale_at',
      'created_at',
      'updated_at',
      'synced',
      'idempotency_key',
      'sync_status',
    },
    'affiliate_rewards': {
      'id',
      'merchant_id',
      'affiliate_id',
      'attribution_id',
      'reward_type',
      'value_type',
      'reward_value',
      'status',
      'approval_required',
      'source_sale_id',
      'approved_at',
      'approved_by_app_user_id',
      'cancelled_at',
      'cancelled_by_app_user_id',
      'cancellation_reason',
      'paid_at',
      'paid_by_app_user_id',
      'created_at',
      'updated_at',
      'synced',
      'idempotency_key',
    },
    'affiliate_events': {
      'id',
      'merchant_id',
      'affiliate_id',
      'event_type',
      'attribution_id',
      'reward_id',
      'sale_id',
      'customer_id',
      'payload',
      'occurred_at',
      'created_at',
      'schema_version',
    },
    'affiliate_fraud_signals': {
      'id',
      'merchant_id',
      'affiliate_id',
      'signal_type',
      'severity',
      'attribution_id',
      'reward_id',
      'sale_id',
      'customer_id',
      'metadata',
      'created_at',
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
      'device_id',
      'merchant_item_id',
      'staff_app_user_id',
      'duration_minutes',
      'notes',
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
    'return_bonuses': {
      'id',
      'merchant_id',
      'customer_id',
      'type',
      'value',
      'status',
      'issued_at',
      'expires_at',
      'source_sale_id',
      'redeemed_at',
      'redemption_sale_id',
      'created_at',
      'updated_at',
      'synced',
    },
    'customer_risk_scores': {
      'id',
      'merchant_id',
      'customer_id',
      'days_since_visit',
      'risk_level',
      'priority',
      'updated_at',
      'synced',
    },
    'recovery_tasks': {
      'id',
      'merchant_id',
      'customer_id',
      'priority',
      'status',
      'due_at',
      'notes',
      'created_at',
      'updated_at',
      'synced',
    },
    'recovery_actions': {
      'id',
      'merchant_id',
      'customer_id',
      'task_id',
      'action_type',
      'payload',
      'created_at',
      'updated_at',
      'synced',
    },
    'visit_reports': {
      'id',
      'merchant_id',
      'task_id',
      'customer_id',
      'result',
      'notes',
      'visited_at',
      'created_at',
      'updated_at',
      'synced',
    },
    'surveys': {
      'id',
      'merchant_id',
      'title',
      'description',
      'is_active',
      'created_at',
      'updated_at',
      'synced',
    },
    'survey_questions': {
      'id',
      'merchant_id',
      'survey_id',
      'question_text',
      'question_type',
      'sort_order',
      'is_required',
      'options_payload',
      'created_at',
      'updated_at',
      'synced',
    },
    'survey_responses': {
      'id',
      'merchant_id',
      'survey_id',
      'customer_id',
      'submitted_at',
      'channel',
      'created_at',
      'updated_at',
      'synced',
    },
    'survey_response_answers': {
      'id',
      'merchant_id',
      'response_id',
      'question_id',
      'answer_text',
      'answer_numeric',
      'answer_bool',
      'created_at',
      'updated_at',
      'synced',
    },
    'merchant_items': {
      'id',
      'merchant_id',
      'name',
      'type',
      'default_price',
      'is_active',
      'display_order',
      'created_at',
      'updated_at',
      'synced',
    },
    'sale_items': {
      'id',
      'merchant_id',
      'sale_id',
      'merchant_item_id',
      'name_snapshot',
      'type_snapshot',
      'quantity',
      'unit_price',
      'subtotal',
      'created_at',
      'updated_at',
      'synced',
    },
    'loyalty_ledger': {
      'id',
      'merchant_id',
      'customer_id',
      'entry_type',
      'points_delta',
      'source_type',
      'source_id',
      'policy_version',
      'occurred_at',
      'created_at',
      'balance_after',
    },
    'redemption_requests': {
      'id',
      'merchant_id',
      'customer_id',
      'reward_id',
      'points_required',
      'status',
      'created_at',
      'updated_at',
      'last_error',
    },
    'sync_tombstones': {
      'id',
      'merchant_id',
      'entity_type',
      'entity_id',
      'deleted_at',
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
      await _createV12Schema(txn);
      await _createV13Schema(txn);
      await _createV14Schema(txn);
      await _createV15Schema(txn);
      await _createV16Schema(txn);
      await _createV17Schema(txn);
      await _createV18Schema(txn);
      await _createV19Schema(txn);
      await _createV20Schema(txn);
      await _createV21Schema(txn);
      await _createV22Schema(txn);
      await _createV23Schema(txn);
      await _createV24Schema(txn);
      await _createV25Schema(txn);
      await _createV26Schema(txn);
      await _createV27Schema(txn);
      await _createV28Schema(txn);
      await _createV29Schema(txn);
      await _createV30Schema(txn);
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
      phone TEXT NOT NULL,
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
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(synced)',
  );
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
      status TEXT NOT NULL DEFAULT 'pending',
      last_error TEXT
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

Future<void> _createV16Schema(DatabaseExecutor db) async {
  final customerColumns = await db.rawQuery('PRAGMA table_info(customers)');
  if (customerColumns.isEmpty) {
    return;
  }

  await db.execute('PRAGMA foreign_keys = OFF');
  try {
    await db.execute('DROP TABLE IF EXISTS customers_new');
    await db.execute('''
      CREATE TABLE customers_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        total_points INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        merchant_id TEXT,
        device_id TEXT
      )
    ''');

    await db.execute('''
      INSERT INTO customers_new (
        id,
        name,
        phone,
        total_points,
        created_at,
        updated_at,
        synced,
        merchant_id,
        device_id
      )
      SELECT
        id,
        name,
        phone,
        total_points,
        created_at,
        updated_at,
        synced,
        merchant_id,
        device_id
      FROM customers
    ''');

    await db.execute('DROP TABLE customers');
    await db.execute('ALTER TABLE customers_new RENAME TO customers');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name_nocase ON customers(name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_merchant_id ON customers(merchant_id)',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_scope_phone ON customers(COALESCE(merchant_id, '__global__'), phone)",
    );
  } finally {
    await db.execute('PRAGMA foreign_keys = ON');
  }
}

Future<void> _createV17Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'appointments', 'device_id TEXT');
}

Future<void> _createV18Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS customer_risk_scores (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      days_since_visit INTEGER NOT NULL DEFAULT 0,
      risk_level TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_risk_scores_merchant_customer ON customer_risk_scores(merchant_id, customer_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customer_risk_scores_risk_priority ON customer_risk_scores(merchant_id, risk_level, priority)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customer_risk_scores_synced ON customer_risk_scores(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS recovery_tasks (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      priority TEXT NOT NULL,
      status TEXT NOT NULL,
      due_at INTEGER,
      notes TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_recovery_tasks_merchant_status_due ON recovery_tasks(merchant_id, status, due_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_recovery_tasks_merchant_priority ON recovery_tasks(merchant_id, priority, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_recovery_tasks_synced ON recovery_tasks(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS recovery_actions (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      task_id TEXT,
      action_type TEXT NOT NULL,
      payload TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (task_id) REFERENCES recovery_tasks(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_recovery_actions_merchant_customer ON recovery_actions(merchant_id, customer_id, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_recovery_actions_merchant_task ON recovery_actions(merchant_id, task_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_recovery_actions_synced ON recovery_actions(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS visit_reports (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      task_id TEXT,
      customer_id TEXT NOT NULL,
      result TEXT NOT NULL,
      notes TEXT,
      visited_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (task_id) REFERENCES recovery_tasks(id),
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_visit_reports_merchant_visited_at ON visit_reports(merchant_id, visited_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_visit_reports_merchant_result ON visit_reports(merchant_id, result, visited_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_visit_reports_synced ON visit_reports(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS surveys (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_surveys_merchant_active ON surveys(merchant_id, is_active, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_surveys_synced ON surveys(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS survey_questions (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      survey_id TEXT NOT NULL,
      question_text TEXT NOT NULL,
      question_type TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_required INTEGER NOT NULL DEFAULT 0,
      options_payload TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (survey_id) REFERENCES surveys(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_survey_questions_survey_order ON survey_questions(survey_id, sort_order)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_survey_questions_synced ON survey_questions(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS survey_responses (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      survey_id TEXT NOT NULL,
      customer_id TEXT,
      submitted_at INTEGER NOT NULL,
      channel TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (survey_id) REFERENCES surveys(id),
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_survey_responses_merchant_survey ON survey_responses(merchant_id, survey_id, submitted_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_survey_responses_synced ON survey_responses(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS survey_response_answers (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      response_id TEXT NOT NULL,
      question_id TEXT NOT NULL,
      answer_text TEXT,
      answer_numeric REAL,
      answer_bool INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (response_id) REFERENCES survey_responses(id),
      FOREIGN KEY (question_id) REFERENCES survey_questions(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_survey_response_answers_response ON survey_response_answers(response_id, question_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_survey_response_answers_synced ON survey_response_answers(merchant_id, synced)',
  );
}

Future<void> _createV19Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(
    db,
    'app_users',
    "status TEXT NOT NULL DEFAULT 'ACTIVE'",
  );
  await _addColumnIfMissing(db, 'app_users', 'invited_at INTEGER');
  await _addColumnIfMissing(db, 'app_users', 'accepted_at INTEGER');
  await _addColumnIfMissing(db, 'app_users', 'invited_by_app_user_id TEXT');
  await _addColumnIfMissing(db, 'app_users', 'deactivated_at INTEGER');

  await db.execute(
    "UPDATE app_users SET status = 'ACTIVE' WHERE status IS NULL OR status = ''",
  );
  await db.execute(
    'UPDATE app_users SET accepted_at = COALESCE(accepted_at, last_login_at, created_at)',
  );

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_app_users_merchant_status ON app_users(merchant_id, status)',
  );
}

Future<void> _createV20Schema(DatabaseExecutor db) async {
  const tables = [
    'sales',
    'appointments',
    'recovery_tasks',
    'recovery_actions',
    'visit_reports',
    'surveys',
    'survey_questions',
    'survey_responses',
    'survey_response_answers',
  ];

  for (final table in tables) {
    await _addColumnIfMissing(db, table, 'created_by_app_user_id TEXT');
    await _addColumnIfMissing(db, table, 'updated_by_app_user_id TEXT');
  }
}

Future<void> _createV21Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'sync_queue', 'last_error TEXT');
}

Future<void> _createV22Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_items (
      id TEXT PRIMARY KEY,
      merchant_id TEXT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      default_price REAL,
      is_active INTEGER NOT NULL DEFAULT 1,
      display_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      created_by_app_user_id TEXT,
      updated_by_app_user_id TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_items_scope_type ON merchant_items(merchant_id, type, is_active, display_order)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_items_synced ON merchant_items(merchant_id, synced)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS sale_items (
      id TEXT PRIMARY KEY,
      merchant_id TEXT,
      sale_id TEXT NOT NULL,
      merchant_item_id TEXT NOT NULL,
      name_snapshot TEXT NOT NULL,
      type_snapshot TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price REAL,
      subtotal REAL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      created_by_app_user_id TEXT,
      updated_by_app_user_id TEXT,
      FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
      FOREIGN KEY (merchant_item_id) REFERENCES merchant_items(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sale_items_synced ON sale_items(merchant_id, synced)',
  );
}

Future<void> _createV23Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'appointments', 'merchant_item_id TEXT');
  await _addColumnIfMissing(db, 'appointments', 'staff_app_user_id TEXT');
  await _addColumnIfMissing(db, 'appointments', 'duration_minutes INTEGER');
  await _addColumnIfMissing(db, 'appointments', 'notes TEXT');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_appointments_merchant_item ON appointments(merchant_id, merchant_item_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_appointments_staff_date ON appointments(merchant_id, staff_app_user_id, scheduled_date)',
  );
}

Future<void> _createV24Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'customers', 'canonical_customer_id TEXT');
  await _addColumnIfMissing(
    db,
    'customers',
    "account_state TEXT NOT NULL DEFAULT 'UNCLAIMED'",
  );
  await _addColumnIfMissing(
    db,
    'customers',
    "relationship_status TEXT NOT NULL DEFAULT 'ACTIVE'",
  );
  await _addColumnIfMissing(
    db,
    'customers',
    "lifecycle_stage TEXT NOT NULL DEFAULT 'NEW'",
  );
  await _addColumnIfMissing(
    db,
    'customers',
    "retention_status TEXT NOT NULL DEFAULT 'HEALTHY'",
  );
  await _addColumnIfMissing(db, 'customers', 'first_visit_at INTEGER');
  await _addColumnIfMissing(db, 'customers', 'last_visit_at INTEGER');
  await _addColumnIfMissing(
    db,
    'customers',
    'total_visits INTEGER NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(
    db,
    'customers',
    'total_spent REAL NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(
    db,
    'customers',
    'average_spend REAL NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(
    db,
    'customers',
    'average_visit_interval_days INTEGER',
  );
  await _addColumnIfMissing(
    db,
    'customers',
    "marketing_consent_status TEXT NOT NULL DEFAULT 'UNKNOWN'",
  );
  await _addColumnIfMissing(
    db,
    'customers',
    "whatsapp_consent_status TEXT NOT NULL DEFAULT 'UNKNOWN'",
  );
  await _addColumnIfMissing(
    db,
    'customers',
    'schema_version INTEGER NOT NULL DEFAULT 1',
  );

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_merchant_canonical '
    'ON customers(merchant_id, canonical_customer_id) '
    'WHERE canonical_customer_id IS NOT NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_merchant_lifecycle '
    'ON customers(merchant_id, lifecycle_stage, retention_status)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_merchant_last_visit '
    'ON customers(merchant_id, last_visit_at)',
  );
}

Future<void> _createV25Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'customers', 'confirmed_points INTEGER');
  await _addColumnIfMissing(
    db,
    'sales',
    'updated_at INTEGER NOT NULL DEFAULT 0',
  );
  await db.execute(
    'UPDATE sales SET updated_at = created_at '
    'WHERE updated_at = 0 OR updated_at IS NULL',
  );
  await _addColumnIfMissing(
    db,
    'sales',
    "confirmation_status TEXT NOT NULL DEFAULT 'PENDING'",
  );
  await _addColumnIfMissing(db, 'sales', 'confirmed_points INTEGER');
  await _addColumnIfMissing(db, 'sales', 'confirmed_at INTEGER');
  await _addColumnIfMissing(db, 'sales', 'confirmation_error_code TEXT');
  await _addColumnIfMissing(db, 'sales', 'loyalty_policy_version INTEGER');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS loyalty_ledger (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      points_delta INTEGER NOT NULL,
      source_type TEXT NOT NULL,
      source_id TEXT NOT NULL,
      policy_version INTEGER NOT NULL,
      occurred_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      balance_after INTEGER NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_loyalty_ledger_source '
    'ON loyalty_ledger(merchant_id, source_type, source_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_customer_time '
    'ON loyalty_ledger(merchant_id, customer_id, occurred_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_created '
    'ON loyalty_ledger(merchant_id, created_at, id)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS redemption_requests (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      reward_id TEXT NOT NULL,
      points_required INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'PENDING',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_error TEXT,
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (reward_id) REFERENCES rewards(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_redemption_requests_pending '
    'ON redemption_requests(merchant_id, customer_id, reward_id, status)',
  );
  await db.delete('sync_state', where: 'entity_type = ?', whereArgs: ['sale']);
}

Future<void> _createV26Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS customer_app_cache (
      account_id TEXT NOT NULL,
      cache_key TEXT NOT NULL,
      payload TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      last_successful_refresh_at INTEGER NOT NULL,
      PRIMARY KEY (account_id, cache_key)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customer_app_cache_account '
    'ON customer_app_cache(account_id, updated_at)',
  );
}

Future<void> _createV27Schema(DatabaseExecutor db) async {
  await _addColumnIfMissing(db, 'customers', 'archived_at INTEGER');
  await _addColumnIfMissing(
    db,
    'customers',
    'archived_by_app_user_id TEXT',
  );
  await _addColumnIfMissing(
    db,
    'sales',
    "cancellation_status TEXT NOT NULL DEFAULT 'ACTIVE'",
  );
  await _addColumnIfMissing(db, 'sales', 'cancelled_at INTEGER');
  await _addColumnIfMissing(
    db,
    'sales',
    'cancelled_by_app_user_id TEXT',
  );
  await _addColumnIfMissing(db, 'sales', 'cancellation_reason TEXT');
  await _addColumnIfMissing(db, 'sales', 'replacement_sale_id TEXT');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_customers_archive '
    'ON customers(merchant_id, archived_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_cancellation '
    'ON sales(merchant_id, cancellation_status, updated_at)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_tombstones (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      deleted_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_tombstones_entity '
    'ON sync_tombstones(merchant_id, entity_type, entity_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_tombstones_deleted '
    'ON sync_tombstones(merchant_id, deleted_at, id)',
  );
}

Future<void> _createV28Schema(DatabaseExecutor db) async {
  // Local read cache of the last NFC card UID resolved for a customer, so
  // repeat taps at the same merchant can be recognised quickly. The backend
  // (customer_nfc_cards collection) remains the source of truth for
  // link/resolve/revoke; this column only speeds up local lookups and must
  // never be trusted on its own for authorization decisions.
  await _addColumnIfMissing(db, 'customers', 'nfc_card_uid TEXT');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_nfc_card_uid '
    'ON customers(merchant_id, nfc_card_uid) '
    'WHERE nfc_card_uid IS NOT NULL',
  );
}

Future<void> _createV29Schema(DatabaseExecutor db) async {
  // Retention Engine (F1 Bónus de Regresso): server-issued, server-redeemed.
  // The client only reads a pulled-down cache for display; expiration and
  // redemption are always re-validated server-side (never trusted locally).
  await db.execute('''
    CREATE TABLE IF NOT EXISTS return_bonuses (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      type TEXT NOT NULL,
      value REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'ACTIVE',
      issued_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      source_sale_id TEXT,
      redeemed_at INTEGER,
      redemption_sale_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_return_bonuses_merchant_customer ON return_bonuses(merchant_id, customer_id, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_return_bonuses_merchant_status ON return_bonuses(merchant_id, status, expires_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_return_bonuses_synced ON return_bonuses(merchant_id, synced)',
  );
}

Future<void> _createV30Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliates (
      id TEXT PRIMARY KEY,
      phone TEXT NOT NULL,
      normalized_phone TEXT NOT NULL,
      first_name TEXT NOT NULL,
      last_name TEXT,
      display_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliates_normalized_phone '
    'ON affiliates(normalized_phone)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliates_status_updated '
    'ON affiliates(status, updated_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_merchants (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE')),
      linked_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_merchants_scope '
    'ON affiliate_merchants(merchant_id, affiliate_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_merchants_status '
    'ON affiliate_merchants(merchant_id, status, updated_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_codes (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT NOT NULL,
      code TEXT NOT NULL,
      normalized_code TEXT NOT NULL,
      benefit_type TEXT NOT NULL
        CHECK (benefit_type IN ('FIXED_AMOUNT', 'PERCENTAGE', 'POINTS')),
      benefit_value REAL NOT NULL,
      starts_at INTEGER,
      expires_at INTEGER,
      usage_limit INTEGER,
      usage_count INTEGER NOT NULL DEFAULT 0,
      first_visit_only INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'DISABLED')),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_codes_scope '
    'ON affiliate_codes(merchant_id, affiliate_id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_codes_normalized '
    'ON affiliate_codes(normalized_code)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_codes_status '
    'ON affiliate_codes(merchant_id, status, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_codes_affiliate '
    'ON affiliate_codes(merchant_id, affiliate_id, updated_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_code_lookup_cache (
      normalized_code TEXT PRIMARY KEY,
      code_id TEXT NOT NULL,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT NOT NULL,
      code TEXT NOT NULL,
      status TEXT NOT NULL
        CHECK (status IN ('ACTIVE', 'DISABLED')),
      benefit_type TEXT NOT NULL
        CHECK (benefit_type IN ('FIXED_AMOUNT', 'PERCENTAGE', 'POINTS')),
      benefit_value REAL NOT NULL,
      starts_at INTEGER,
      expires_at INTEGER,
      usage_limit INTEGER,
      usage_count INTEGER NOT NULL DEFAULT 0,
      first_visit_only INTEGER NOT NULL DEFAULT 1,
      cached_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (code_id) REFERENCES affiliate_codes(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_code_lookup_cache_scope '
    'ON affiliate_code_lookup_cache(merchant_id, code_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_code_lookup_cache_affiliate '
    'ON affiliate_code_lookup_cache(merchant_id, affiliate_id, updated_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_attributions (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT NOT NULL,
      affiliate_code_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      qualifying_sale_id TEXT,
      status TEXT NOT NULL DEFAULT 'CONFIRMED'
        CHECK (status IN ('CONFIRMED', 'REJECTED', 'CANCELLED')),
      rejection_code TEXT
        CHECK (
          rejection_code IS NULL OR rejection_code IN (
            'CODE_NOT_FOUND',
            'CODE_DISABLED',
            'CODE_NOT_STARTED',
            'CODE_EXPIRED',
            'CODE_USAGE_LIMIT_REACHED',
            'AFFILIATE_INACTIVE',
            'SELF_REFERRAL_NOT_ALLOWED',
            'CUSTOMER_NOT_ELIGIBLE',
            'CUSTOMER_ALREADY_REFERRED',
            'BENEFIT_INVALID'
          )
        ),
      attributed_at INTEGER NOT NULL,
      first_sale_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id),
      FOREIGN KEY (affiliate_code_id) REFERENCES affiliate_codes(id),
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (qualifying_sale_id) REFERENCES sales(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_attributions_non_rejected_customer '
    'ON affiliate_attributions(merchant_id, customer_id) '
    "WHERE status <> 'REJECTED'",
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_attributions_affiliate '
    'ON affiliate_attributions(merchant_id, affiliate_id, status, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_attributions_sale '
    'ON affiliate_attributions(merchant_id, qualifying_sale_id)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_rewards (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT NOT NULL,
      attribution_id TEXT NOT NULL,
      reward_type TEXT NOT NULL
        CHECK (reward_type IN ('FIRST_QUALIFYING_SALE', 'CUSTOMER_RETURN')),
      value_type TEXT NOT NULL
        CHECK (value_type IN ('POINTS', 'FIXED_AMOUNT')),
      reward_value REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'APPROVED', 'PAID', 'CANCELLED')),
      approval_required INTEGER NOT NULL DEFAULT 1,
      source_sale_id TEXT,
      approved_at INTEGER,
      approved_by_app_user_id TEXT,
      cancelled_at INTEGER,
      cancelled_by_app_user_id TEXT,
      cancellation_reason TEXT,
      paid_at INTEGER,
      paid_by_app_user_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id),
      FOREIGN KEY (attribution_id) REFERENCES affiliate_attributions(id),
      FOREIGN KEY (source_sale_id) REFERENCES sales(id)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_rewards_attribution_type '
    'ON affiliate_rewards(merchant_id, attribution_id, reward_type)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_rewards_status '
    'ON affiliate_rewards(merchant_id, status, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_rewards_affiliate '
    'ON affiliate_rewards(merchant_id, affiliate_id, reward_type, updated_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_events (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT NOT NULL,
      event_type TEXT NOT NULL
        CHECK (
          event_type IN (
            'AFFILIATE_CREATED',
            'AFFILIATE_CODE_CREATED',
            'REFERRAL_CODE_VALIDATED',
            'REFERRAL_ATTRIBUTED',
            'REFERRAL_REJECTED',
            'AFFILIATE_REWARD_CREATED',
            'AFFILIATE_REWARD_APPROVED',
            'AFFILIATE_REWARD_CANCELLED',
            'REFERRED_CUSTOMER_RETURNED'
          )
        ),
      attribution_id TEXT,
      reward_id TEXT,
      sale_id TEXT,
      customer_id TEXT,
      payload TEXT,
      occurred_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      schema_version INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id),
      FOREIGN KEY (attribution_id) REFERENCES affiliate_attributions(id),
      FOREIGN KEY (reward_id) REFERENCES affiliate_rewards(id),
      FOREIGN KEY (sale_id) REFERENCES sales(id),
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_events_occurred '
    'ON affiliate_events(merchant_id, occurred_at, id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_events_affiliate '
    'ON affiliate_events(merchant_id, affiliate_id, occurred_at, id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_events_type '
    'ON affiliate_events(merchant_id, event_type, occurred_at, id)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS affiliate_fraud_signals (
      id TEXT PRIMARY KEY,
      merchant_id TEXT NOT NULL,
      affiliate_id TEXT,
      signal_type TEXT NOT NULL
        CHECK (
          signal_type IN (
            'OFFLINE_CODE_REJECTED',
            'VALIDATION_BURST',
            'SELF_REFERRAL_ATTEMPT',
            'DUPLICATE_ATTRIBUTION_ATTEMPT'
          )
        ),
      severity TEXT NOT NULL
        CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH')),
      attribution_id TEXT,
      reward_id TEXT,
      sale_id TEXT,
      customer_id TEXT,
      metadata TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (affiliate_id) REFERENCES affiliates(id),
      FOREIGN KEY (attribution_id) REFERENCES affiliate_attributions(id),
      FOREIGN KEY (reward_id) REFERENCES affiliate_rewards(id),
      FOREIGN KEY (sale_id) REFERENCES sales(id),
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_fraud_signals_severity '
    'ON affiliate_fraud_signals(merchant_id, severity, created_at, id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_fraud_signals_affiliate '
    'ON affiliate_fraud_signals(merchant_id, affiliate_id, created_at, id)',
  );

  await _addColumnIfMissing(db, 'sales', 'gross_amount REAL');
  await _addColumnIfMissing(db, 'sales', 'referral_benefit_type TEXT');
  await _addColumnIfMissing(db, 'sales', 'referral_benefit_value REAL');
  await _addColumnIfMissing(db, 'sales', 'referral_benefit_amount REAL');
  await _addColumnIfMissing(db, 'sales', 'affiliate_code_id TEXT');
  await _addColumnIfMissing(db, 'sales', 'referral_status TEXT');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_affiliate_code '
    'ON sales(merchant_id, affiliate_code_id, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_referral_status '
    'ON sales(merchant_id, referral_status, updated_at)',
  );

  await _addColumnIfMissing(db, 'sync_queue', 'local_id TEXT');
  await _addColumnIfMissing(db, 'sync_queue', 'idempotency_key TEXT');
  await _addColumnIfMissing(db, 'sync_queue', 'last_sync_error TEXT');
  await db.execute(
    'UPDATE sync_queue SET local_id = entity_id '
    "WHERE local_id IS NULL OR local_id = ''",
  );
  await db.execute(
    'UPDATE sync_queue SET idempotency_key = id '
    "WHERE idempotency_key IS NULL OR idempotency_key = ''",
  );
  await db.execute(
    'UPDATE sync_queue SET last_sync_error = last_error '
    'WHERE last_sync_error IS NULL AND last_error IS NOT NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_queue_local_id '
    'ON sync_queue(merchant_id, entity_type, local_id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_queue_idempotency_key '
    'ON sync_queue(merchant_id, idempotency_key) '
    'WHERE idempotency_key IS NOT NULL',
  );
}

/// Offline referrals: what a till has decided on its own and not yet had
/// confirmed.
///
/// Purely additive over v30, which shipped and is not touched again. Every
/// column here answers one question the offline path asks and v30 cannot:
/// whether a row is a local guess awaiting the server (`provisional`,
/// `sync_status`, `last_sync_error`), who a cached code belongs to in words a
/// cashier can read (`affiliate_display_name` and the two statuses), and what
/// code a sale carried when the cache could not price it
/// (`referral_code_input`).
///
/// `referral_local_benefit_applied` is the one the server needs most: a
/// rejected code whose discount was already given to a customer standing at the
/// counter keeps that discount, and the only way to know a discount was given
/// is to have written down that it was.
Future<void> _createV31Schema(DatabaseExecutor db) async {
  // A provisional affiliate is one this device invented while offline. It is
  // real enough to appear in the list and be worked with, and never real
  // enough to share: the code it carries is local and the server has not
  // agreed to it yet.
  for (final table in <String>[
    'affiliates',
    'affiliate_merchants',
    'affiliate_codes',
  ]) {
    await _addColumnIfMissing(
      db,
      table,
      'provisional INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, table, 'local_id TEXT');
    await _addColumnIfMissing(db, table, 'sync_status TEXT');
    await _addColumnIfMissing(db, table, 'last_sync_error TEXT');
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliates_provisional '
    'ON affiliates(provisional, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_codes_provisional '
    'ON affiliate_codes(merchant_id, provisional, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_merchants_provisional '
    'ON affiliate_merchants(merchant_id, provisional, updated_at)',
  );

  // The cache the till prices an offline sale from. v30 stores the code's own
  // terms; these add the affiliate the cashier reads out and the two statuses
  // that make a code unusable even when the code itself is ACTIVE.
  await _addColumnIfMissing(
    db,
    'affiliate_code_lookup_cache',
    'affiliate_display_name TEXT',
  );
  await _addColumnIfMissing(
    db,
    'affiliate_code_lookup_cache',
    'affiliate_first_name TEXT',
  );
  await _addColumnIfMissing(
    db,
    'affiliate_code_lookup_cache',
    "affiliate_status TEXT NOT NULL DEFAULT 'ACTIVE'",
  );
  await _addColumnIfMissing(
    db,
    'affiliate_code_lookup_cache',
    "link_status TEXT NOT NULL DEFAULT 'ACTIVE'",
  );
  await _addColumnIfMissing(
    db,
    'affiliate_code_lookup_cache',
    'refreshed_at INTEGER',
  );
  await db.execute(
    'UPDATE affiliate_code_lookup_cache SET refreshed_at = cached_at '
    'WHERE refreshed_at IS NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_affiliate_code_lookup_cache_refreshed '
    'ON affiliate_code_lookup_cache(merchant_id, refreshed_at)',
  );

  // What a sale carried, as opposed to what it was worth. `affiliate_code_id`
  // is only filled when the cache could resolve the code; a code typed with no
  // cache entry is still kept, verbatim and normalised, because the server can
  // still attribute it and a discarded code is an affiliate never paid.
  await _addColumnIfMissing(db, 'sales', 'referral_code_input TEXT');
  await _addColumnIfMissing(db, 'sales', 'affiliate_id TEXT');
  await _addColumnIfMissing(db, 'sales', 'referral_rejection_code TEXT');
  await _addColumnIfMissing(db, 'sales', 'referral_status_message TEXT');
  await _addColumnIfMissing(
    db,
    'sales',
    'referral_local_benefit_applied INTEGER NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(db, 'sales', 'referral_idempotency_key TEXT');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sales_referral_code_input '
    'ON sales(merchant_id, referral_code_input, created_at)',
  );

  // The keys the prompt fixes, stored beside the rows they identify so a
  // replay of the same fact converges on the same record instead of a second
  // one. Derived values only: a phone reaches these columns already hashed.
  await _addColumnIfMissing(
    db,
    'affiliate_attributions',
    'idempotency_key TEXT',
  );
  await _addColumnIfMissing(db, 'affiliate_rewards', 'idempotency_key TEXT');
  await _addColumnIfMissing(db, 'affiliate_attributions', 'sync_status TEXT');
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
