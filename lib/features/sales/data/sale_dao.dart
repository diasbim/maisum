import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/sale.dart';

class SaleDao {
  SaleDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<Sale> create({
    required String customerId,
    required double amount,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final points = (amount / AppConstants.pointsPerMzn).floor();
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
          ? 'SELECT s.*, c.name as customer_name, c.phone as customer_phone '
                'FROM sales s '
                'LEFT JOIN customers c ON s.customer_id = c.id '
                'ORDER BY s.created_at DESC'
          : 'SELECT s.*, c.name as customer_name, c.phone as customer_phone '
                'FROM sales s '
                'LEFT JOIN customers c ON s.customer_id = c.id '
                'WHERE s.merchant_id = ? '
                'ORDER BY s.created_at DESC',
      merchantId == null ? const [] : [merchantId],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
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
