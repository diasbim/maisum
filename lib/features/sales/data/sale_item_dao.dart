import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/sale_item.dart';

class SaleItemDao {
  SaleItemDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<List<SaleItem>> saveItems({
    required String saleId,
    required List<SaleItemInput> items,
    String? appUserId,
  }) async {
    final db = await _db.database;
    return db.transaction(
      (txn) => insertItems(
        txn,
        saleId: saleId,
        items: items,
        appUserId: appUserId,
      ),
    );
  }

  Future<List<SaleItem>> insertItems(
    DatabaseExecutor db, {
    required String saleId,
    required List<SaleItemInput> items,
    DateTime? now,
    String? appUserId,
  }) async {
    if (items.isEmpty) return const <SaleItem>[];
    final timestamp = now ?? DateTime.now();
    final saved = <SaleItem>[];
    for (final input in items) {
      final quantity = input.quantity.clamp(1, 999).toInt();
      final saleItem = SaleItem(
        id: _uuid.v4(),
        merchantId: merchantId,
        saleId: saleId,
        merchantItemId: input.merchantItemId,
        nameSnapshot: input.nameSnapshot,
        typeSnapshot: input.typeSnapshot,
        quantity: quantity,
        unitPrice: input.unitPrice,
        subtotal: input.unitPrice == null ? null : input.unitPrice! * quantity,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await db.insert('sale_items', _row(saleItem, appUserId: appUserId));
      saved.add(saleItem);
    }
    return saved;
  }

  Future<List<SaleItem>> getSaleItems(String saleId) async {
    final db = await _db.database;
    final rows = await db.query(
      'sale_items',
      where: _withMerchantScope('sale_id = ?'),
      whereArgs: _withMerchantArgs([saleId]),
      orderBy: 'created_at ASC, name_snapshot COLLATE NOCASE ASC',
    );
    return rows.map(saleItemFromMap).toList();
  }

  Future<Map<String, List<SaleItem>>> getBySaleIds(List<String> saleIds) async {
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

  Future<void> deleteSaleItems(String saleId) async {
    final db = await _db.database;
    await db.delete(
      'sale_items',
      where: _withMerchantScope('sale_id = ?'),
      whereArgs: _withMerchantArgs([saleId]),
    );
  }

  Future<List<SaleItem>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query(
      'sale_items',
      where: _withMerchantScope('synced = 0'),
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'created_at ASC',
    );
    return rows.map(saleItemFromMap).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'sale_items',
      {'synced': 1},
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Map<String, dynamic> rowForSync(SaleItem item, {String? appUserId}) =>
      _row(item, appUserId: appUserId);

  Map<String, dynamic> _row(SaleItem item, {String? appUserId}) => {
        ...item.toDbMap(),
        'merchant_id': merchantId ?? item.merchantId,
        'created_by_app_user_id': appUserId,
        'updated_by_app_user_id': appUserId,
      };

  String _withMerchantScope(String clause) {
    if (merchantId == null) return clause;
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _withMerchantArgs(List<Object?> args) {
    if (merchantId == null) return args;
    return [merchantId, ...args];
  }
}
