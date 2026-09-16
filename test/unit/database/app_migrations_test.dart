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

Future<bool> _tableExists(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}

Future<Set<String>> _indexes(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA index_list($table)');
  return rows.map((row) => row['name'] as String?).whereType<String>().toSet();
}

Future<String?> _indexSql(Database db, String indexName) async {
  final rows = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
    [indexName],
  );
  return rows.isEmpty ? null : rows.single['sql'] as String?;
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

  test('v28 adds nfc card uid cache with per-merchant uniqueness', () async {
    final db = await _openDb(version: 27);
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
    await db.insert('customers', {
      'id': 'c2',
      'merchant_id': 'm2',
      'name': 'Beatriz',
      'phone': '841234568',
      'total_points': 0,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
    });

    await AppMigrations.migrate(db, fromVersion: 27, toVersion: 28);

    expect(await _columns(db, 'customers'), contains('nfc_card_uid'));

    await db.update(
      'customers',
      {'nfc_card_uid': '04A22C9B'},
      where: 'id = ?',
      whereArgs: ['c1'],
    );
    // Same UID is allowed for a different merchant.
    await db.update(
      'customers',
      {'nfc_card_uid': '04A22C9B'},
      where: 'id = ?',
      whereArgs: ['c2'],
    );
    // A second customer in the same merchant reusing that UID must fail.
    await db.insert('customers', {
      'id': 'c3',
      'merchant_id': 'm1',
      'name': 'Carlos',
      'phone': '841234569',
      'total_points': 0,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
    });
    expect(
      () => db.update(
        'customers',
        {'nfc_card_uid': '04A22C9B'},
        where: 'id = ?',
        whereArgs: ['c3'],
      ),
      throwsA(anything),
    );
  });

  test('v29 adds return_bonuses for the Retention Engine (Bónus de Regresso)',
      () async {
    final db = await _openDb(version: 28);
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

    await AppMigrations.migrate(db, fromVersion: 28, toVersion: 29);

    final cols = await _columns(db, 'return_bonuses');
    expect(
      cols,
      containsAll(<String>[
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
      ]),
    );

    await db.insert('return_bonuses', {
      'id': 'b1',
      'merchant_id': 'm1',
      'customer_id': 'c1',
      'type': 'DISCOUNT',
      'value': 20,
      'status': 'ACTIVE',
      'issued_at': 1000,
      'expires_at': 2000,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 0,
    });
    final rows =
        await db.query('return_bonuses', where: 'id = ?', whereArgs: ['b1']);
    expect(rows.single['status'], 'ACTIVE');
  });

  test('v30 creates the affiliate data foundation on a fresh database',
      () async {
    final db = await _openDb(version: 30);

    for (final table in <String>[
      'affiliates',
      'affiliate_merchants',
      'affiliate_codes',
      'affiliate_code_lookup_cache',
      'affiliate_attributions',
      'affiliate_rewards',
      'affiliate_events',
      'affiliate_fraud_signals',
    ]) {
      expect(await _tableExists(db, table), isTrue, reason: table);
    }

    expect(
      await _columns(db, 'sales'),
      containsAll(<String>[
        'gross_amount',
        'referral_benefit_type',
        'referral_benefit_value',
        'referral_benefit_amount',
        'affiliate_code_id',
        'referral_status',
      ]),
    );
    expect(
      await _columns(db, 'sync_queue'),
      containsAll(<String>[
        'local_id',
        'idempotency_key',
        'last_sync_error',
      ]),
    );
    expect(
      await _indexes(db, 'affiliate_attributions'),
      contains('idx_affiliate_attributions_non_rejected_customer'),
    );
    expect(
      await _indexSql(
        db,
        'idx_affiliate_attributions_non_rejected_customer',
      ),
      contains("WHERE status <> 'REJECTED'"),
    );
    expect(
      await _indexes(db, 'affiliate_rewards'),
      contains('idx_affiliate_rewards_attribution_type'),
    );
    expect(
      await _indexes(db, 'sync_queue'),
      contains('idx_sync_queue_idempotency_key'),
    );

    final migrationLog = await db.query(
      'migration_log',
      where: 'version = ?',
      whereArgs: [30],
      limit: 1,
    );
    expect(migrationLog, hasLength(1));
  });

  test('v30 upgrades v29 data and preserves legacy sale and sync rows',
      () async {
    final db = await _openDb(version: 29);
    await db.insert('merchants', {
      'id': 'm1',
      'phone': '+258841234567',
      'merchant_name': 'Mais Um',
      'slug': 'mais-um',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });
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
    await db.insert('customers', {
      'id': 'c2',
      'merchant_id': 'm1',
      'name': 'Beatriz',
      'phone': '841234568',
      'total_points': 0,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
    });
    await db.insert('sales', {
      'id': 's1',
      'merchant_id': 'm1',
      'customer_id': 'c1',
      'amount': 250,
      'points': 2,
      'created_at': 10,
      'updated_at': 10,
      'confirmation_status': 'PENDING',
      'cancellation_status': 'ACTIVE',
      'synced': 0,
    });
    await db.insert('sync_queue', {
      'id': 'q1',
      'operation': 'create',
      'entity_type': 'sale',
      'entity_id': 's1',
      'payload': '{"id":"s1"}',
      'created_at': 11,
      'retry_count': 1,
      'status': 'failed',
      'merchant_id': 'm1',
      'device_id': 'device-1',
      'next_attempt_at': 0,
      'last_error': 'timeout',
    });

    await AppMigrations.migrate(db, fromVersion: 29, toVersion: 30);

    final sale =
        (await db.query('sales', where: 'id = ?', whereArgs: ['s1'])).single;
    expect(sale['amount'], 250.0);
    expect(sale['points'], 2);
    expect(sale['gross_amount'], isNull);
    expect(sale['affiliate_code_id'], isNull);
    expect(sale['referral_status'], isNull);

    final syncRow =
        (await db.query('sync_queue', where: 'id = ?', whereArgs: ['q1']))
            .single;
    expect(syncRow['entity_id'], 's1');
    expect(syncRow['status'], 'failed');
    expect(syncRow['last_error'], 'timeout');
    expect(syncRow['local_id'], 's1');
    expect(syncRow['idempotency_key'], 'q1');
    expect(syncRow['last_sync_error'], 'timeout');

    expect(
      await _indexes(db, 'sales'),
      containsAll(<String>[
        'idx_sales_affiliate_code',
        'idx_sales_referral_status',
      ]),
    );
  });

  test('v30 enforces affiliate uniqueness constraints and active attribution',
      () async {
    final db = await _openDb(version: 30);
    await db.insert('merchants', {
      'id': 'm1',
      'phone': '+258841234567',
      'merchant_name': 'Mais Um',
      'slug': 'mais-um',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });
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
      'amount': 300,
      'points': 3,
      'created_at': 10,
      'updated_at': 10,
      'confirmation_status': 'PENDING',
      'cancellation_status': 'ACTIVE',
      'synced': 0,
    });

    await db.insert('affiliates', {
      'id': 'a1',
      'phone': '+258841111111',
      'normalized_phone': '258841111111',
      'first_name': 'Ana',
      'last_name': 'Silva',
      'display_name': 'Ana Silva',
      'status': 'ACTIVE',
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
    });

    expect(
      () => db.insert('affiliates', {
        'id': 'a2',
        'phone': '+258841111111',
        'normalized_phone': '258841111111',
        'first_name': 'Outra',
        'display_name': 'Outra Pessoa',
        'status': 'ACTIVE',
        'created_at': 10,
        'updated_at': 10,
        'synced': 0,
      }),
      throwsA(anything),
    );

    await db.insert('affiliate_merchants', {
      'id': 'am1',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'status': 'ACTIVE',
      'linked_at': 10,
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
    });
    expect(
      () => db.insert('affiliate_merchants', {
        'id': 'am2',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'status': 'ACTIVE',
        'linked_at': 11,
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );

    await db.insert('affiliate_codes', {
      'id': 'code1',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'code': 'AFI-ANA-2345',
      'normalized_code': 'AFI-ANA-2345',
      'benefit_type': 'POINTS',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': 1,
      'status': 'ACTIVE',
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
    });
    expect(
      () => db.insert('affiliate_codes', {
        'id': 'code2',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'code': 'AFI-ANA-9876',
        'normalized_code': 'AFI-ANA-9876',
        'benefit_type': 'POINTS',
        'benefit_value': 25,
        'usage_count': 0,
        'first_visit_only': 1,
        'status': 'ACTIVE',
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );
    expect(
      () => db.insert('affiliate_codes', {
        'id': 'code3',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'code': 'AFI-ANA-2345',
        'normalized_code': 'AFI-ANA-2345',
        'benefit_type': 'POINTS',
        'benefit_value': 25,
        'usage_count': 0,
        'first_visit_only': 1,
        'status': 'DISABLED',
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );

    await db.insert('affiliate_attributions', {
      'id': 'attr1',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'affiliate_code_id': 'code1',
      'customer_id': 'c1',
      'qualifying_sale_id': 's1',
      'status': 'CONFIRMED',
      'attributed_at': 10,
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
    });
    expect(
      () => db.insert('affiliate_attributions', {
        'id': 'attr2',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'affiliate_code_id': 'code1',
        'customer_id': 'c1',
        'qualifying_sale_id': 's1',
        'status': 'CANCELLED',
        'attributed_at': 11,
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );
    expect(
      () => db.insert('affiliate_attributions', {
        'id': 'attr-invalid-status',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'affiliate_code_id': 'code1',
        'customer_id': 'c2',
        'status': 'ACTIVE',
        'attributed_at': 11,
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );
    await db.insert('affiliate_attributions', {
      'id': 'attr3',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'affiliate_code_id': 'code1',
      'customer_id': 'c1',
      'status': 'REJECTED',
      'rejection_code': 'CUSTOMER_ALREADY_REFERRED',
      'attributed_at': 12,
      'created_at': 12,
      'updated_at': 12,
      'synced': 0,
    });

    await db.insert('affiliate_rewards', {
      'id': 'reward1',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'attribution_id': 'attr1',
      'reward_type': 'FIRST_QUALIFYING_SALE',
      'value_type': 'POINTS',
      'reward_value': 50,
      'status': 'PENDING',
      'approval_required': 1,
      'source_sale_id': 's1',
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
    });
    expect(
      () => db.insert('affiliate_rewards', {
        'id': 'reward2',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'attribution_id': 'attr1',
        'reward_type': 'FIRST_QUALIFYING_SALE',
        'value_type': 'POINTS',
        'reward_value': 25,
        'status': 'APPROVED',
        'approval_required': 1,
        'source_sale_id': 's1',
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );
    expect(
      () => db.insert('affiliate_rewards', {
        'id': 'reward-invalid-type',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'attribution_id': 'attr1',
        'reward_type': 'FIRST_SALE',
        'value_type': 'AMOUNT',
        'reward_value': 25,
        'status': 'REJECTED',
        'approval_required': 1,
        'created_at': 11,
        'updated_at': 11,
        'synced': 0,
      }),
      throwsA(anything),
    );
    expect(
      () => db.insert('affiliate_events', {
        'id': 'event-invalid-type',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'event_type': 'ATTRIBUTION_CREATED',
        'attribution_id': 'attr1',
        'customer_id': 'c1',
        'occurred_at': 11,
        'created_at': 11,
        'schema_version': 1,
        'payload': '{}',
      }),
      throwsA(anything),
    );
    expect(
      () => db.insert('affiliate_fraud_signals', {
        'id': 'signal-invalid-type',
        'merchant_id': 'm1',
        'affiliate_id': 'a1',
        'signal_type': 'SYNC_REJECTED',
        'severity': 'MEDIUM',
        'attribution_id': 'attr1',
        'customer_id': 'c1',
        'created_at': 11,
        'metadata': '{}',
      }),
      throwsA(anything),
    );
  });

  test('v31 adds the offline referral columns without touching v30 data',
      () async {
    final db = await _openDb(version: 30);
    await db.insert('merchants', {
      'id': 'm1',
      'phone': '+258841234567',
      'merchant_name': 'Mais Um',
      'slug': 'mais-um',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });
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
      'amount': 250,
      'points': 2,
      'created_at': 10,
      'updated_at': 10,
      'confirmation_status': 'PENDING',
      'cancellation_status': 'ACTIVE',
      'gross_amount': 300,
      'referral_benefit_type': 'FIXED_AMOUNT',
      'referral_benefit_amount': 50,
      'affiliate_code_id': 'code-1',
      'referral_status': 'ATTRIBUTED',
      'synced': 1,
    });
    await db.insert('affiliates', {
      'id': 'a1',
      'phone': '+258841111111',
      'normalized_phone': '258841111111',
      'first_name': 'Ana',
      'display_name': 'Ana Silva',
      'status': 'ACTIVE',
      'created_at': 10,
      'updated_at': 10,
      'synced': 1,
    });
    await db.insert('affiliate_codes', {
      'id': 'code-1',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'code': 'AFI-ANA-2345',
      'normalized_code': 'AFI-ANA-2345',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': 1,
      'status': 'ACTIVE',
      'created_at': 10,
      'updated_at': 10,
      'synced': 1,
    });
    await db.insert('affiliate_code_lookup_cache', {
      'normalized_code': 'AFI-ANA-2345',
      'code_id': 'code-1',
      'merchant_id': 'm1',
      'affiliate_id': 'a1',
      'code': 'AFI-ANA-2345',
      'status': 'ACTIVE',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': 1,
      'cached_at': 900,
      'updated_at': 900,
    });

    await AppMigrations.migrate(db, fromVersion: 30, toVersion: 31);

    // v30 shipped; it is extended, never rewritten. Everything it stored is
    // still exactly where it was.
    final sale =
        (await db.query('sales', where: 'id = ?', whereArgs: ['s1'])).single;
    expect(sale['amount'], 250.0);
    expect(sale['gross_amount'], 300.0);
    expect(sale['referral_status'], 'ATTRIBUTED');
    expect(sale['referral_code_input'], isNull);
    expect(sale['referral_local_benefit_applied'], 0);

    expect(
      await _columns(db, 'sales'),
      containsAll(<String>[
        'referral_code_input',
        'affiliate_id',
        'referral_rejection_code',
        'referral_status_message',
        'referral_local_benefit_applied',
        'referral_idempotency_key',
      ]),
    );
    for (final table in <String>[
      'affiliates',
      'affiliate_merchants',
      'affiliate_codes',
    ]) {
      expect(
        await _columns(db, table),
        containsAll(<String>[
          'provisional',
          'local_id',
          'sync_status',
          'last_sync_error',
        ]),
        reason: table,
      );
    }
    expect(
      await _columns(db, 'affiliate_code_lookup_cache'),
      containsAll(<String>[
        'affiliate_display_name',
        'affiliate_first_name',
        'affiliate_status',
        'link_status',
        'refreshed_at',
      ]),
    );
    expect(
      await _columns(db, 'affiliate_attributions'),
      containsAll(<String>['idempotency_key', 'sync_status']),
    );
    expect(
      await _columns(db, 'affiliate_rewards'),
      contains('idempotency_key'),
    );

    // An existing cache row is backfilled rather than left with a null
    // refreshed_at, which would read as "never confirmed".
    final cached = (await db.query('affiliate_code_lookup_cache')).single;
    expect(cached['refreshed_at'], 900);
    expect(cached['affiliate_status'], 'ACTIVE');
    expect(cached['link_status'], 'ACTIVE');

    final affiliate =
        (await db.query('affiliates', where: 'id = ?', whereArgs: ['a1']))
            .single;
    expect(affiliate['provisional'], 0);
    expect(affiliate['sync_status'], isNull);

    final migrationLog = await db.query(
      'migration_log',
      where: 'version = ?',
      whereArgs: [31],
      limit: 1,
    );
    expect(migrationLog, hasLength(1));
  });

  test('v31 stores a locally decided referral and a provisional affiliate',
      () async {
    final db = await _openDb(version: 31);
    await db.insert('merchants', {
      'id': 'm1',
      'phone': '+258841234567',
      'merchant_name': 'Mais Um',
      'slug': 'mais-um',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('customers', {
      'id': 'c1',
      'merchant_id': 'm1',
      'name': 'Ana',
      'phone': '841234567',
      'total_points': 0,
      'created_at': 1,
      'updated_at': 1,
      'synced': 0,
    });

    await db.insert('sales', {
      'id': 'sale_offline',
      'merchant_id': 'm1',
      'customer_id': 'c1',
      'amount': 250,
      'points': 2,
      'created_at': 10,
      'updated_at': 10,
      'confirmation_status': 'PENDING',
      'cancellation_status': 'ACTIVE',
      'gross_amount': 300,
      'referral_benefit_type': 'FIXED_AMOUNT',
      'referral_benefit_value': 50,
      'referral_benefit_amount': 50,
      'referral_status': 'PENDING_SYNC',
      'referral_code_input': 'AFI-ANA-2345',
      'referral_local_benefit_applied': 1,
      'referral_idempotency_key': 'sale:till-1:local-1',
      'synced': 0,
    });
    final sale = (await db.query('sales')).single;
    expect(sale['referral_status'], 'PENDING_SYNC');
    expect(sale['referral_local_benefit_applied'], 1);

    await db.insert('affiliates', {
      'id': 'local_1',
      'phone': '+258849998888',
      'normalized_phone': '258849998888',
      'first_name': 'Beatriz',
      'display_name': 'Beatriz Cossa',
      'status': 'ACTIVE',
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
      'provisional': 1,
      'local_id': 'local-1',
      'sync_status': 'PENDING',
    });
    await db.insert('affiliate_codes', {
      'id': 'acl_local-1',
      'merchant_id': 'm1',
      'affiliate_id': 'local_1',
      'code': 'LOCAL-BEATRIZ-A1B2C3',
      'normalized_code': 'LOCAL-BEATRIZ-A1B2C3',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 40,
      'usage_count': 0,
      'first_visit_only': 1,
      'status': 'ACTIVE',
      'created_at': 10,
      'updated_at': 10,
      'synced': 0,
      'provisional': 1,
      'local_id': 'local-1',
      'sync_status': 'PENDING',
    });

    final provisional = await db.query(
      'affiliate_codes',
      where: 'provisional = ?',
      whereArgs: [1],
    );
    expect(provisional, hasLength(1));
    expect(provisional.single['code'], startsWith('LOCAL-'));
    // The global uniqueness the server owns is untouched by a local guess: a
    // provisional code is not in the AFI- namespace at all.
    expect(provisional.single['normalized_code'], isNot(startsWith('AFI-')));
  });
}
