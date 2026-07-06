import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/merchant_item.dart';

class MerchantCatalogDao {
  MerchantCatalogDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<List<MerchantItem>> getServices() => _getByType(
        MerchantItemType.service,
      );

  Future<List<MerchantItem>> getProducts() => _getByType(
        MerchantItemType.product,
      );

  Future<List<MerchantItem>> getActiveItems() async {
    final db = await _db.database;
    final rows = await db.query(
      'merchant_items',
      where: _withMerchantScope('is_active = 1'),
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'type ASC, display_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(merchantItemFromMap).toList();
  }

  Future<MerchantItem?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'merchant_items',
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return merchantItemFromMap(rows.first);
  }

  Future<MerchantItem> create({
    required String name,
    required MerchantItemType type,
    double? defaultPrice,
    bool isActive = true,
    String? appUserId,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final item = MerchantItem(
        id: _uuid.v4(),
        merchantId: merchantId,
        name: name,
        type: type,
        defaultPrice: defaultPrice,
        isActive: isActive,
        displayOrder: await _nextDisplayOrder(txn, type),
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('merchant_items', _row(item, appUserId: appUserId));
      return item;
    });
  }

  Future<MerchantItem?> update(
    String id, {
    String? name,
    Object? defaultPrice = _keep,
    bool? isActive,
    int? displayOrder,
    String? appUserId,
  }) async {
    final existing = await getById(id);
    if (existing == null) return null;
    final updated = existing.copyWith(
      name: name,
      defaultPrice: defaultPrice,
      isActive: isActive,
      displayOrder: displayOrder,
      updatedAt: DateTime.now(),
      synced: false,
    );
    final db = await _db.database;
    await db.update(
      'merchant_items',
      _row(updated, appUserId: appUserId),
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
    return updated;
  }

  Future<bool> delete(String id) async {
    final db = await _db.database;
    final countRows = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) AS count FROM sale_items WHERE merchant_item_id = ?'
          : 'SELECT COUNT(*) AS count FROM sale_items WHERE merchant_id = ? AND merchant_item_id = ?',
      merchantId == null ? [id] : [merchantId, id],
    );
    final usageCount = countRows.first['count'] as int? ?? 0;
    if (usageCount > 0) return false;

    final deleted = await db.delete(
      'merchant_items',
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
    return deleted > 0;
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'merchant_items',
      {'synced': 1},
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<List<MerchantItem>> _getByType(MerchantItemType type) async {
    final db = await _db.database;
    final rows = await db.query(
      'merchant_items',
      where: _withMerchantScope('type = ?'),
      whereArgs: _withMerchantArgs([type.dbValue]),
      orderBy: 'display_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(merchantItemFromMap).toList();
  }

  Future<int> _nextDisplayOrder(
    DatabaseExecutor db,
    MerchantItemType type,
  ) async {
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT COALESCE(MAX(display_order), -1) AS max_order FROM merchant_items WHERE type = ?'
          : 'SELECT COALESCE(MAX(display_order), -1) AS max_order FROM merchant_items WHERE merchant_id = ? AND type = ?',
      merchantId == null ? [type.dbValue] : [merchantId, type.dbValue],
    );
    final maxOrder = rows.first['max_order'] as int? ?? -1;
    return maxOrder + 1;
  }

  Map<String, dynamic> _row(MerchantItem item, {String? appUserId}) => {
        ...item.toDbMap(),
        'merchant_id': merchantId ?? item.merchantId,
        'updated_by_app_user_id': appUserId,
        'created_by_app_user_id': appUserId,
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

const _keep = Object();
