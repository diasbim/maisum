import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/utils/points_calculator.dart';
import '../../../core/database/app_database.dart';
import '../../customers/domain/customer.dart';
import '../domain/sale.dart';
import 'sale_dao.dart';
import '../../sync/domain/sync_item.dart';

class SaleRepository {
  SaleRepository(
    this._database,
    this._saleDao, {
    this.merchantId,
    this.deviceId,
    this.appUserId,
  });

  final AppDatabase _database;

  final SaleDao _saleDao;
  final String? merchantId;
  final String? deviceId;
  final String? appUserId;
  static const _uuid = Uuid();
  static const _points = PointsCalculator();

  Future<Sale> createSale({
    required String customerId,
    required double amount,
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
                ...updatedCustomer.toDbMap(),
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
            payload: jsonEncode(_saleRow(sale)),
            createdAt: now,
          ),
        ),
      );

      return sale;
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

  Map<String, dynamic> _syncQueueRow(SyncItem item) => {
        ...item.toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
      };
}
