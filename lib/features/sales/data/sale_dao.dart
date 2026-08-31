import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/points_calculator.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';

class SaleDao {
  SaleDao(
    this._db, {
    this.merchantId,
    int pointsPerMzn = 100,
  }) : _points = PointsCalculator(pointsPerMzn: pointsPerMzn);

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();
  final PointsCalculator _points;

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
    final sales = rows.map(saleFromMap).toList();
    return _attachItemsToSales(sales);
  }

  Future<Sale?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'sales',
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final sale = saleFromMap(rows.first);
    final withItems = await _attachItemsToSales([sale]);
    return withItems.first;
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
    return _attachItemsToRows(
        rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Future<Map<String, dynamic>?> getLatestWithCustomer() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT s.*, c.name as customer_name, c.phone as customer_phone, '
              'c.total_points as customer_total_points '
              'FROM sales s '
              'LEFT JOIN customers c ON s.customer_id = c.id '
              "WHERE s.cancellation_status = 'ACTIVE' "
              'AND c.archived_at IS NULL '
              'ORDER BY s.created_at DESC LIMIT 1'
          : 'SELECT s.*, c.name as customer_name, c.phone as customer_phone, '
              'c.total_points as customer_total_points '
              'FROM sales s '
              'LEFT JOIN customers c ON s.customer_id = c.id '
              "WHERE s.merchant_id = ? "
              "AND s.cancellation_status = 'ACTIVE' "
              'AND c.archived_at IS NULL '
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
              "FROM sales WHERE cancellation_status = 'ACTIVE' "
              'AND created_at >= ?'
          : 'SELECT COUNT(*) as count, COALESCE(SUM(points), 0) as total_points '
              "FROM sales WHERE merchant_id = ? "
              "AND cancellation_status = 'ACTIVE' AND created_at >= ?",
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
              "FROM sales WHERE cancellation_status = 'ACTIVE' "
              'AND created_at >= ? '
              'ORDER BY day DESC'
          : 'SELECT DISTINCT date(created_at / 1000, "unixepoch") as day '
              "FROM sales WHERE merchant_id = ? "
              "AND cancellation_status = 'ACTIVE' AND created_at >= ? "
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
              "WHERE cancellation_status = 'ACTIVE' AND created_at >= ? "
              'GROUP BY customer_id HAVING COUNT(*) >= 2'
              ')'
          : 'SELECT COUNT(*) as count FROM ('
              'SELECT customer_id FROM sales '
              "WHERE merchant_id = ? AND cancellation_status = 'ACTIVE' "
              'AND created_at >= ? '
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
          ? "SELECT amount FROM sales WHERE cancellation_status = 'ACTIVE' "
              'ORDER BY created_at DESC LIMIT 1'
          : "SELECT amount FROM sales WHERE merchant_id = ? "
              "AND cancellation_status = 'ACTIVE' "
              'ORDER BY created_at DESC LIMIT 1',
      merchantId == null ? const [] : [merchantId],
    );
    if (rows.isEmpty) return null;
    final amount = rows.first['amount'] as num?;
    if (amount == null) return null;
    return amount.round();
  }

  Future<List<Sale>> _attachItemsToSales(List<Sale> sales) async {
    if (sales.isEmpty) return sales;
    final grouped =
        await _itemsBySaleIds(sales.map((sale) => sale.id).toList());
    return sales
        .map((sale) => sale.copyWith(items: grouped[sale.id] ?? const []))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _attachItemsToRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    final saleIds = rows.map((row) => row['id'] as String).toList();
    final grouped = await _itemsBySaleIds(saleIds);
    return rows.map((row) {
      final saleItems = grouped[row['id']] ?? const <SaleItem>[];
      return {
        ...row,
        'items': saleItems.map((item) => item.toDbMap()).toList(),
      };
    }).toList();
  }

  Future<Map<String, List<SaleItem>>> _itemsBySaleIds(
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const <String, List<SaleItem>>{};
    final db = await _db.database;
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final rows = await db.query(
      'sale_items',
      where: _withMerchantScope('sale_id IN ($placeholders)'),
      whereArgs: _withMerchantArgs(saleIds),
      orderBy: 'created_at ASC, name_snapshot COLLATE NOCASE ASC',
    );
    final grouped = <String, List<SaleItem>>{};
    for (final row in rows) {
      final item = saleItemFromMap(row);
      grouped.putIfAbsent(item.saleId, () => <SaleItem>[]).add(item);
    }
    return grouped;
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
