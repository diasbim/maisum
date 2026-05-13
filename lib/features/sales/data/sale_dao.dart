import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/points_calculator.dart';
import '../domain/sale.dart';

class SaleDao {
  SaleDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();
  static const _points = PointsCalculator();

  Future<Sale> create({
    required String customerId,
    required double amount,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final points = _points.calculate(amount);
    final sale = Sale(
      id: _uuid.v4(),
      customerId: customerId,
      amount: amount,
      points: points,
      createdAt: now,
    );
    await db.insert('sales', {...sale.toDbMap(), 'merchant_id': merchantId});
    return sale;
  }

  Future<List<Sale>> getByCustomer(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'sales',
      where: _withMerchantScope('customer_id = ?'),
      whereArgs: _withMerchantArgs([customerId]),
      orderBy: 'created_at DESC',
    );
    return rows.map(saleFromMap).toList();
  }

  Future<List<Sale>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query(
      'sales',
      where: _withMerchantScope('synced = 0'),
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'created_at ASC',
    );
    return rows.map(saleFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'sales',
      {'synced': 1},
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<List<Map<String, dynamic>>> getAllWithCustomer() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT s.*, c.name as customer_name, c.phone as customer_phone, '
              'c.total_points as customer_total_points '
              'FROM sales s '
              'LEFT JOIN customers c ON s.customer_id = c.id '
              'ORDER BY s.created_at DESC'
          : 'SELECT s.*, c.name as customer_name, c.phone as customer_phone, '
              'c.total_points as customer_total_points '
              'FROM sales s '
              'LEFT JOIN customers c ON s.customer_id = c.id '
              'WHERE s.merchant_id = ? '
              'ORDER BY s.created_at DESC',
      merchantId == null ? const [] : [merchantId],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<Map<String, dynamic>?> getLatestWithCustomer() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT s.*, c.name as customer_name, c.phone as customer_phone, '
              'c.total_points as customer_total_points '
              'FROM sales s '
              'LEFT JOIN customers c ON s.customer_id = c.id '
              'ORDER BY s.created_at DESC LIMIT 1'
          : 'SELECT s.*, c.name as customer_name, c.phone as customer_phone, '
              'c.total_points as customer_total_points '
              'FROM sales s '
              'LEFT JOIN customers c ON s.customer_id = c.id '
              'WHERE s.merchant_id = ? '
              'ORDER BY s.created_at DESC LIMIT 1',
      merchantId == null ? const [] : [merchantId],
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>> getTodayStats() async {
    final db = await _db.database;
    final startOfDay = DateTime.now().copyWith(
      hour: 0,
      minute: 0,
      second: 0,
      millisecond: 0,
    );
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) as count, COALESCE(SUM(points), 0) as total_points '
              'FROM sales WHERE created_at >= ?'
          : 'SELECT COUNT(*) as count, COALESCE(SUM(points), 0) as total_points '
              'FROM sales WHERE merchant_id = ? AND created_at >= ?',
      merchantId == null
          ? [startOfDay.millisecondsSinceEpoch]
          : [merchantId, startOfDay.millisecondsSinceEpoch],
    );
    final row = rows.first;
    return {
      'count': row['count'] as int? ?? 0,
      'total_points': row['total_points'] as int? ?? 0,
    };
  }

  Future<List<DateTime>> getSaleDays({int days = 30}) async {
    final db = await _db.database;
    final start = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT DISTINCT date(created_at / 1000, "unixepoch") as day '
              'FROM sales WHERE created_at >= ? '
              'ORDER BY day DESC'
          : 'SELECT DISTINCT date(created_at / 1000, "unixepoch") as day '
              'FROM sales WHERE merchant_id = ? AND created_at >= ? '
              'ORDER BY day DESC',
      merchantId == null
          ? [start.millisecondsSinceEpoch]
          : [merchantId, start.millisecondsSinceEpoch],
    );

    return rows
        .map((row) => row['day'] as String?)
        .where((value) => value != null && value.isNotEmpty)
        .map((value) => DateTime.parse(value!))
        .toList();
  }

  Future<int> getReturningCustomersCount({int days = 30}) async {
    final db = await _db.database;
    final start = DateTime.now().subtract(Duration(days: days));
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) as count FROM ('
              'SELECT customer_id FROM sales '
              'WHERE created_at >= ? '
              'GROUP BY customer_id HAVING COUNT(*) >= 2'
              ')'
          : 'SELECT COUNT(*) as count FROM ('
              'SELECT customer_id FROM sales '
              'WHERE merchant_id = ? AND created_at >= ? '
              'GROUP BY customer_id HAVING COUNT(*) >= 2'
              ')',
      merchantId == null
          ? [start.millisecondsSinceEpoch]
          : [merchantId, start.millisecondsSinceEpoch],
    );
    return rows.first['count'] as int? ?? 0;
  }

  Future<int?> getLastSaleAmount() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT amount FROM sales ORDER BY created_at DESC LIMIT 1'
          : 'SELECT amount FROM sales WHERE merchant_id = ? '
              'ORDER BY created_at DESC LIMIT 1',
      merchantId == null ? const [] : [merchantId],
    );
    if (rows.isEmpty) return null;
    final amount = rows.first['amount'] as num?;
    if (amount == null) return null;
    return amount.round();
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
