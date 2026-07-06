import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/sale_item.dart';
import 'sale_item_dao.dart';

class SaleItemRepository {
  SaleItemRepository(this._dao, this._syncDao, {this.appUserId});

  final SaleItemDao _dao;
  final SyncDao _syncDao;
  final String? appUserId;
  static const _uuid = Uuid();

  Future<List<SaleItem>> saveItems({
    required String saleId,
    required List<SaleItemInput> items,
  }) async {
    final saved = await _dao.saveItems(
      saleId: saleId,
      items: items,
      appUserId: appUserId,
    );
    for (final item in saved) {
      await _enqueue('create', item);
    }
    return saved;
  }

  Future<List<SaleItem>> getSaleItems(String saleId) =>
      _dao.getSaleItems(saleId);

  Future<void> deleteSaleItems(String saleId) async {
    final existing = await _dao.getSaleItems(saleId);
    await _dao.deleteSaleItems(saleId);
    for (final item in existing) {
      await _syncDao.enqueue(
        SyncItem(
          id: _uuid.v4(),
          operation: 'delete',
          entityType: 'sale_item',
          entityId: item.id,
          payload: jsonEncode({'id': item.id, 'merchant_id': item.merchantId}),
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> syncPending() async {
    final pending = await _dao.getUnsynced();
    for (final item in pending) {
      await _enqueue('create', item);
    }
  }

  Future<void> _enqueue(String operation, SaleItem item) {
    return _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: operation,
        entityType: 'sale_item',
        entityId: item.id,
        payload: jsonEncode(_dao.rowForSync(item, appUserId: appUserId)),
        createdAt: DateTime.now(),
      ),
    );
  }
}
