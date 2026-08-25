import '../../../core/database/app_database.dart';
import '../domain/loyalty_ledger_entry.dart';

class LoyaltyLedgerDao {
  LoyaltyLedgerDao(this._db, {required this.merchantId});

  LoyaltyLedgerDao.unscoped(this._db) : merchantId = null;

  final AppDatabase _db;
  final String? merchantId;

  Future<List<LoyaltyLedgerEntry>> getByCustomer(
    String customerId, {
    int limit = 100,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'loyalty_ledger',
      where: merchantId == null
          ? 'customer_id = ?'
          : 'merchant_id = ? AND customer_id = ?',
      whereArgs: merchantId == null
          ? <Object?>[customerId]
          : <Object?>[merchantId, customerId],
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(loyaltyLedgerEntryFromMap).toList();
  }

  Future<int?> getConfirmedBalance(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'loyalty_ledger',
      columns: <String>['balance_after'],
      where: merchantId == null
          ? 'customer_id = ?'
          : 'merchant_id = ? AND customer_id = ?',
      whereArgs: merchantId == null
          ? <Object?>[customerId]
          : <Object?>[merchantId, customerId],
      orderBy: 'occurred_at DESC, created_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.single['balance_after'] as num).toInt();
  }

  Future<CustomerLoyaltyBalance> getCustomerBalance(String customerId) async {
    final db = await _db.database;
    final customerRows = await db.query(
      'customers',
      columns: <String>['confirmed_points', 'total_points'],
      where: merchantId == null ? 'id = ?' : 'merchant_id = ? AND id = ?',
      whereArgs: merchantId == null
          ? <Object?>[customerId]
          : <Object?>[merchantId, customerId],
      limit: 1,
    );
    if (customerRows.isEmpty) {
      throw StateError('Customer not found in the active merchant');
    }
    final pendingRows = await db.rawQuery(
      merchantId == null
          ? "SELECT COALESCE(SUM(points), 0) AS pending_points FROM sales "
              "WHERE customer_id = ? AND confirmation_status = 'PENDING'"
          : "SELECT COALESCE(SUM(points), 0) AS pending_points FROM sales "
              "WHERE merchant_id = ? AND customer_id = ? "
              "AND confirmation_status = 'PENDING'",
      merchantId == null
          ? <Object?>[customerId]
          : <Object?>[merchantId, customerId],
    );
    final customer = customerRows.single;
    return CustomerLoyaltyBalance(
      confirmedPoints: (customer['confirmed_points'] as num?)?.toInt(),
      pendingPoints:
          (pendingRows.single['pending_points'] as num?)?.toInt() ?? 0,
      legacyPoints: (customer['total_points'] as num?)?.toInt() ?? 0,
    );
  }
}
