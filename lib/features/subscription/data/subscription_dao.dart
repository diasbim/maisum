import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/entitlement.dart';
import '../domain/feature_flag.dart';
import '../domain/subscription_state.dart';
import '../domain/usage_balance.dart';

class SubscriptionDao {
  SubscriptionDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;

  Future<SubscriptionState?> getSubscriptionState() async {
    final db = await _db.database;
    final rows = await db.query(
      'subscription_state',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return subscriptionStateFromMap(rows.first);
  }

  Future<void> upsertSubscriptionState(SubscriptionState state) async {
    final db = await _db.database;
    await db.insert(
      'subscription_state',
      state.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Entitlement?> getEntitlement(String featureKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'entitlements',
      where: _withMerchantScope('feature_key = ?'),
      whereArgs: _withMerchantArgs([featureKey]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return entitlementFromMap(rows.first);
  }

  Future<List<Entitlement>> getEntitlements() async {
    final db = await _db.database;
    final rows = await db.query(
      'entitlements',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'feature_key ASC',
    );
    return rows.map(entitlementFromMap).toList();
  }

  Future<void> upsertEntitlement(Entitlement entitlement) async {
    final db = await _db.database;
    await db.insert(
      'entitlements',
      entitlement.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<FeatureFlag?> getFeatureFlag(String flagKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'feature_flags',
      where: _withMerchantScope('flag_key = ?'),
      whereArgs: _withMerchantArgs([flagKey]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return featureFlagFromMap(rows.first);
  }

  Future<void> upsertFeatureFlag(FeatureFlag flag) async {
    final db = await _db.database;
    await db.insert(
      'feature_flags',
      flag.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FeatureFlag>> getFeatureFlags() async {
    final db = await _db.database;
    final rows = await db.query(
      'feature_flags',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'flag_key ASC',
    );
    return rows.map(featureFlagFromMap).toList();
  }

  Future<UsageBalance?> getUsageBalance({
    required String metricKey,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'usage_balances',
      where: _withMerchantScope(
        'metric_key = ? AND window_start = ? AND window_end = ?',
      ),
      whereArgs: _withMerchantArgs([
        metricKey,
        windowStart.millisecondsSinceEpoch,
        windowEnd.millisecondsSinceEpoch,
      ]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return usageBalanceFromMap(rows.first);
  }

  Future<void> upsertUsageBalance(UsageBalance balance) async {
    final db = await _db.database;
    await db.insert(
      'usage_balances',
      balance.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<UsageBalance>> getUsageBalances({
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (merchantId != null) {
      where.add('merchant_id = ?');
      args.add(merchantId);
    }
    if (windowStart != null && windowEnd != null) {
      where.add('window_start = ?');
      where.add('window_end = ?');
      args.add(windowStart.millisecondsSinceEpoch);
      args.add(windowEnd.millisecondsSinceEpoch);
    }

    final rows = await db.query(
      'usage_balances',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'metric_key ASC',
    );
    return rows.map(usageBalanceFromMap).toList();
  }

  String _withMerchantScope(String clause) {
    if (merchantId == null) {
      return clause;
    }
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _withMerchantArgs(List<Object?> args) {
    if (merchantId == null) {
      return args;
    }
    return [merchantId, ...args];
  }
}
