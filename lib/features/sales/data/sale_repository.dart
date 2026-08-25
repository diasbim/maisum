import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/utils/points_calculator.dart';
import '../../../core/database/app_database.dart';
import '../../customers/domain/customer.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';
import 'sale_dao.dart';
import 'sale_item_dao.dart';
import '../../sync/domain/sync_item.dart';

class SaleRepository {
  SaleRepository(
    AppDatabase database,
    this._saleDao, {
    this.merchantId,
    this.deviceId,
    this.appUserId,
    SaleItemDao? saleItemDao,
    int pointsPerMzn = 100,
  })  : _database = database,
        _points = PointsCalculator(pointsPerMzn: pointsPerMzn),
        _saleItemDao =
            saleItemDao ?? SaleItemDao(database, merchantId: merchantId);

  final AppDatabase _database;

  final SaleDao _saleDao;
  final SaleItemDao _saleItemDao;
  final String? merchantId;
  final String? deviceId;
  final String? appUserId;
  static const _uuid = Uuid();
  final PointsCalculator _points;

  Future<Sale> createSale({
    required String customerId,
    required double amount,
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final points = _points.calculate(amount);
      final sale = Sale(
        id: _uuid.v4(),
        customerId: customerId,
        amount: amount,
        points: points,
        createdAt: now,
      );

      await txn.insert('sales', _saleRow(sale));
      var saleWithItems = sale;

      final customerRows = await txn.query(
        'customers',
        where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
        whereArgs: merchantId == null ? [customerId] : [customerId, merchantId],
        limit: 1,
      );

      if (customerRows.isNotEmpty) {
        final customer = customerFromMap(customerRows.first);
        final newTotal = customer.totalPoints + sale.points;
        final updatedCustomer = customer.copyWith(
          totalPoints: newTotal,
          updatedAt: now,
          synced: false,
        );

        await txn.update(
          'customers',
          {...updatedCustomer.toDbMap(), 'merchant_id': merchantId},
          where: merchantId == null ? 'id = ?' : 'id = ? AND merchant_id = ?',
          whereArgs:
              merchantId == null ? [customerId] : [customerId, merchantId],
        );

        await txn.insert(
          'sync_queue',
          _syncQueueRow(
            SyncItem(
              id: _uuid.v4(),
              operation: 'update',
              entityType: 'customer',
              entityId: customerId,
              payload: jsonEncode({
                ...updatedCustomer.toClientSyncMap(),
                'merchant_id': merchantId,
              }),
              createdAt: now,
            ),
          ),
        );
      }

      await txn.insert(
        'sync_queue',
        _syncQueueRow(
          SyncItem(
            id: _uuid.v4(),
            operation: 'create',
            entityType: 'sale',
            entityId: sale.id,
            payload: jsonEncode(_saleSyncRow(sale)),
            createdAt: now,
          ),
        ),
      );

      if (items.isNotEmpty) {
        final saleItems = await _saleItemDao.insertItems(
          txn,
          saleId: sale.id,
          items: items,
          now: now,
          appUserId: appUserId,
        );
        saleWithItems = sale.copyWith(items: saleItems);
        for (final saleItem in saleItems) {
          await txn.insert(
            'sync_queue',
            _syncQueueRow(
              SyncItem(
                id: _uuid.v4(),
                operation: 'create',
                entityType: 'sale_item',
                entityId: saleItem.id,
                payload: jsonEncode(
                  _saleItemDao.rowForSync(saleItem, appUserId: appUserId),
                ),
                createdAt: now.add(const Duration(milliseconds: 1)),
              ),
            ),
          );
        }
      }

      return saleWithItems;
    });
  }

  Future<List<Sale>> getByCustomer(String customerId) =>
      _saleDao.getByCustomer(customerId);

  Future<Map<String, dynamic>> getTodayStats() => _saleDao.getTodayStats();

  Map<String, dynamic> _saleRow(Sale sale) => {
        ...sale.toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
        'created_by_app_user_id': appUserId,
        'updated_by_app_user_id': appUserId,
      };

  Map<String, dynamic> _saleSyncRow(Sale sale) => {
        ...sale.toClientSyncMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
        'created_by_app_user_id': appUserId,
        'updated_by_app_user_id': appUserId,
      };

  Map<String, dynamic> _syncQueueRow(SyncItem item) => {
        ...item.toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
      };
}
