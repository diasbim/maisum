import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/return_bonus.dart';

class ReturnBonusDao {
  ReturnBonusDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;

  /// The single active bonus for a customer, if any (spec: max 1 active
  /// bonus per customer per merchant, enforced authoritatively server-side).
  Future<ReturnBonus?> getActiveForCustomer(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'return_bonuses',
      where: merchantId == null
          ? "customer_id = ? AND status = 'ACTIVE'"
          : "merchant_id = ? AND customer_id = ? AND status = 'ACTIVE'",
      whereArgs: merchantId == null ? [customerId] : [merchantId, customerId],
      orderBy: 'issued_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReturnBonus.fromMap(rows.first);
  }

  Future<List<ReturnBonus>> getAllForCustomer(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'return_bonuses',
      where: merchantId == null ? 'customer_id = ?' : 'merchant_id = ? AND customer_id = ?',
      whereArgs: merchantId == null ? [customerId] : [merchantId, customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ReturnBonus.fromMap).toList();
  }

  /// Applies the server's authoritative response after a redeem call so the
  /// UI reflects it immediately, without waiting for the next sync pull.
  Future<void> applyServerBonus(ReturnBonus bonus) async {
    final db = await _db.database;
    await db.insert(
      'return_bonuses',
      {...bonus.toDbMap(), 'merchant_id': merchantId, 'synced': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
