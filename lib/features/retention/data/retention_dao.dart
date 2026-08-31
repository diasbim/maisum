import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../business_profile/domain/business_profile.dart';
import '../domain/retention_metric.dart';

class RetentionDao {
  RetentionDao(
    this._db, {
    this.merchantId,
    this.retentionDefaults = BusinessProfiles.genericRetention,
  });

  final AppDatabase _db;
  final String? merchantId;
  final BusinessRetentionDefaults retentionDefaults;

  Future<List<RecurringCustomerSummary>> getRecurringCustomers({
    int limit = 50,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT c.id AS customer_id, c.name, c.total_visits, c.last_visit_at,
                   c.average_visit_interval_days AS average_visit_interval,
                   c.total_spent
            FROM customers c
            WHERE c.archived_at IS NULL
              AND c.lifecycle_stage IN (
              'RETURNING', 'REGULAR', 'LOYAL', 'VIP', 'ADVOCATE'
            )
            ORDER BY c.total_visits DESC, c.total_spent DESC
            LIMIT ?
          '''
          : '''
            SELECT c.id AS customer_id, c.name, c.total_visits, c.last_visit_at,
                   c.average_visit_interval_days AS average_visit_interval,
                   c.total_spent
            FROM customers c
            WHERE c.merchant_id = ?
              AND c.archived_at IS NULL
              AND c.lifecycle_stage IN (
                'RETURNING', 'REGULAR', 'LOYAL', 'VIP', 'ADVOCATE'
              )
            ORDER BY c.total_visits DESC, c.total_spent DESC
            LIMIT ?
          ''',
      merchantId == null ? [limit] : [merchantId, limit],
    );

    return rows
        .map(
          (row) => RecurringCustomerSummary(
            customerId: row['customer_id'] as String,
            name: (row['name'] as String?) ?? 'Cliente',
            totalVisits: (row['total_visits'] as num?)?.toInt() ?? 0,
            lastVisitAt: _toDate(row['last_visit_at']),
            averageVisitInterval:
                (row['average_visit_interval'] as num?)?.toInt() ?? 0,
            totalSpent: (row['total_spent'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  Future<List<InactiveCustomerSummary>> getInactiveCustomers({
    int limit = 50,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT c.id AS customer_id, c.name, c.last_visit_at,
                   c.retention_status, c.total_visits, c.total_spent
            FROM customers c
            WHERE c.archived_at IS NULL
              AND c.retention_status IN ('AT_RISK', 'INACTIVE', 'LOST')
            ORDER BY c.last_visit_at ASC, c.total_spent DESC
            LIMIT ?
          '''
          : '''
            SELECT c.id AS customer_id, c.name, c.last_visit_at,
                   c.retention_status, c.total_visits, c.total_spent
            FROM customers c
            WHERE c.merchant_id = ?
              AND c.archived_at IS NULL
              AND c.retention_status IN ('AT_RISK', 'INACTIVE', 'LOST')
            ORDER BY c.last_visit_at ASC, c.total_spent DESC
            LIMIT ?
          ''',
      merchantId == null ? [limit] : [merchantId, limit],
    );

    return rows.map(
      (row) {
        final visits = (row['total_visits'] as num?)?.toInt() ?? 0;
        final totalSpent = (row['total_spent'] as num?)?.toDouble() ?? 0;
        final lastVisitAt = _toDate(row['last_visit_at']);
        final retentionStatus =
            (row['retention_status'] as String?)?.toUpperCase();
        return InactiveCustomerSummary(
          customerId: row['customer_id'] as String,
          name: (row['name'] as String?) ?? 'Cliente',
          daysInactive: _daysInactive(lastVisitAt, DateTime.now()),
          lastVisitAt: lastVisitAt,
          averageTicket: visits <= 0 ? 0 : (totalSpent / visits),
          riskLevel: switch (retentionStatus) {
            'AT_RISK' => RetentionRiskLevel.attention,
            'INACTIVE' => RetentionRiskLevel.risk,
            'LOST' => RetentionRiskLevel.lost,
            _ => RetentionRiskLevel.active,
          },
        );
      },
    ).toList();
  }

  Future<List<RetentionMetric>> calculateRetention({DateTime? now}) async {
    final db = await _db.database;
    final nowDate = now ?? DateTime.now();

    final existingRows = await db.query(
      'retention_metrics',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
    );
    final existingByCustomer = <String, RetentionMetric>{
      for (final row in existingRows)
        (row['customer_id'] as String): RetentionMetric.fromJson(row),
    };

    final aggregates = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT c.id AS customer_id,
                   MAX(s.created_at) AS last_visit_at,
                   MIN(s.created_at) AS first_visit_at,
                   COUNT(s.id) AS total_visits,
                   COALESCE(SUM(s.amount), 0) AS total_spent
            FROM customers c
            LEFT JOIN sales s
              ON s.customer_id = c.id
             AND s.cancellation_status = 'ACTIVE'
            WHERE c.archived_at IS NULL
            GROUP BY c.id
          '''
          : '''
            SELECT c.id AS customer_id,
                   MAX(s.created_at) AS last_visit_at,
                   MIN(s.created_at) AS first_visit_at,
                   COUNT(s.id) AS total_visits,
                   COALESCE(SUM(s.amount), 0) AS total_spent
            FROM customers c
            LEFT JOIN sales s
              ON s.customer_id = c.id
             AND s.merchant_id = c.merchant_id
             AND s.cancellation_status = 'ACTIVE'
            WHERE c.merchant_id = ? AND c.archived_at IS NULL
            GROUP BY c.id
          ''',
      merchantId == null ? const [] : [merchantId],
    );

    final metrics = <RetentionMetric>[];
    for (final row in aggregates) {
      final customerId = row['customer_id'] as String;
      final lastVisitAt = _toDate(row['last_visit_at']);
      final firstVisitAt = _toDate(row['first_visit_at']);
      final totalVisits = (row['total_visits'] as num?)?.toInt() ?? 0;
      final totalSpent = (row['total_spent'] as num?)?.toDouble() ?? 0;
      final daysInactive = _daysInactive(lastVisitAt, nowDate);
      final riskLevel = _riskLevelForDays(daysInactive);
      final averageVisitInterval = _averageIntervalDays(
        firstVisitAt: firstVisitAt,
        lastVisitAt: lastVisitAt,
        totalVisits: totalVisits,
      );
      final previous = existingByCustomer[customerId];
      final recovered = previous != null &&
          (previous.riskLevel == RetentionRiskLevel.risk ||
              previous.riskLevel == RetentionRiskLevel.lost) &&
          (riskLevel == RetentionRiskLevel.active ||
              riskLevel == RetentionRiskLevel.attention);

      final id = merchantId == null ? customerId : '${merchantId}_$customerId';
      final metric = RetentionMetric(
        id: id,
        customerId: customerId,
        lastVisitAt: lastVisitAt,
        daysInactive: daysInactive,
        riskLevel: riskLevel,
        totalVisits: totalVisits,
        averageVisitInterval: averageVisitInterval,
        totalSpent: totalSpent,
        isRecurring: totalVisits >= 2,
        recovered: recovered,
        updatedAt: nowDate,
        synced: false,
      );
      await upsertMetric(metric);
      metrics.add(metric);
    }

    return metrics;
  }

  Future<RetentionMetric?> updateCustomerRisk({
    required String customerId,
    required String riskLevel,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'retention_metrics',
      where: merchantId == null
          ? 'customer_id = ?'
          : 'merchant_id = ? AND customer_id = ?',
      whereArgs: merchantId == null ? [customerId] : [merchantId, customerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final existing = RetentionMetric.fromJson(rows.first);
    final updated = existing.copyWith(
      riskLevel: riskLevel,
      updatedAt: DateTime.now(),
      synced: false,
    );
    await upsertMetric(updated);
    return updated;
  }

  Future<void> upsertMetric(RetentionMetric metric) async {
    final db = await _db.database;
    await db.insert(
      'retention_metrics',
      {
        ...metric.toJson(),
        'merchant_id': merchantId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  DateTime? _toDate(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return null;
  }

  int _daysInactive(DateTime? lastVisitAt, DateTime nowDate) {
    if (lastVisitAt == null) return 999;
    final start =
        DateTime(lastVisitAt.year, lastVisitAt.month, lastVisitAt.day);
    final end = DateTime(nowDate.year, nowDate.month, nowDate.day);
    return end.difference(start).inDays;
  }

  int _averageIntervalDays({
    required DateTime? firstVisitAt,
    required DateTime? lastVisitAt,
    required int totalVisits,
  }) {
    if (firstVisitAt == null || lastVisitAt == null || totalVisits <= 1) {
      return 0;
    }
    final spanDays = lastVisitAt.difference(firstVisitAt).inDays;
    if (spanDays <= 0) return 0;
    return (spanDays / (totalVisits - 1)).round();
  }

  String _riskLevelForDays(int days) {
    if (days <= retentionDefaults.activeDays) {
      return RetentionRiskLevel.active;
    }
    if (days <= retentionDefaults.attentionDays) {
      return RetentionRiskLevel.attention;
    }
    if (days <= retentionDefaults.riskDays) return RetentionRiskLevel.risk;
    return RetentionRiskLevel.lost;
  }
}
