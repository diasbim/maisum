import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/merchant_item.dart';
import 'merchant_catalog_dao.dart';

class MerchantCatalogRepository {
  MerchantCatalogRepository(
    this._dao,
    this._syncDao, {
    this.appUserId,
  });

  final MerchantCatalogDao _dao;
  final SyncDao _syncDao;
  final String? appUserId;
  static const _uuid = Uuid();

  Future<List<MerchantItem>> getServices() => _dao.getServices();

  Future<List<MerchantItem>> getProducts() => _dao.getProducts();

  Future<List<MerchantItem>> getActiveItems() => _dao.getActiveItems();

  Future<MerchantItem> save({
    required String name,
    required MerchantItemType type,
    double? defaultPrice,
    bool isActive = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Nome obrigatorio.');
    final item = await _dao.create(
      name: trimmedName,
      type: type,
      defaultPrice: defaultPrice,
      isActive: isActive,
      appUserId: appUserId,
    );
    await _enqueue('create', item);
    return item;
  }

  Future<MerchantItem?> update(
    String id, {
    String? name,
    Object? defaultPrice = _keep,
    bool? isActive,
    int? displayOrder,
  }) async {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isEmpty) {
      throw ArgumentError('Nome obrigatorio.');
    }
    final item = await _dao.update(
      id,
      name: trimmedName,
      defaultPrice: defaultPrice,
      isActive: isActive,
      displayOrder: displayOrder,
      appUserId: appUserId,
    );
    if (item != null) await _enqueue('update', item);
    return item;
  }

  Future<bool> delete(String id) async {
    final existing = await _dao.getById(id);
    final deleted = await _dao.delete(id);
    if (!deleted || existing == null) return deleted;
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'delete',
        entityType: 'merchant_item',
        entityId: id,
        payload: jsonEncode({
          'id': id,
          'merchant_id': _dao.merchantId,
        }),
        createdAt: DateTime.now(),
      ),
    );
    return true;
  }

  Future<void> _enqueue(String operation, MerchantItem item) {
    return _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: operation,
        entityType: 'merchant_item',
        entityId: item.id,
        payload: jsonEncode({
          ...item.toDbMap(),
          'merchant_id': _dao.merchantId,
          'created_by_app_user_id': appUserId,
          'updated_by_app_user_id': appUserId,
        }),
        createdAt: DateTime.now(),
      ),
    );
  }
}

const _keep = Object();
