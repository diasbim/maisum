import 'dart:convert';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../customers/domain/customer.dart';
import '../domain/sale.dart';
import 'sale_dao.dart';
import '../../sync/domain/sync_item.dart';
import 'package:uuid/uuid.dart';

class SaleRepository {
  SaleRepository(this._database, this._saleDao);

  final AppDatabase _database;

  final SaleDao _saleDao;
  static const _uuid = Uuid();

  Future<Sale> createSale({
    required String customerId,
    required double amount,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final points = (amount / AppConstants.pointsPerMzn).floor();
      final sale = Sale(
        id: _uuid.v4(),
        customerId: customerId,
        amount: amount,
        points: points,
        createdAt: now,
      );

      await txn.insert('sales', sale.toDbMap());

      final customerRows = await txn.query(
        'customers',
        where: 'id = ?',
        whereArgs: [customerId],
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
          updatedCustomer.toDbMap(),
          where: 'id = ?',
          whereArgs: [customerId],
        );

        await txn.insert(
          'sync_queue',
          SyncItem(
            id: _uuid.v4(),
            operation: 'update',
            entityType: 'customer',
            entityId: customerId,
            payload: jsonEncode(updatedCustomer.toDbMap()),
            createdAt: now,
          ).toDbMap(),
        );
      }

      await txn.insert(
        'sync_queue',
        SyncItem(
          id: _uuid.v4(),
          operation: 'create',
          entityType: 'sale',
          entityId: sale.id,
          payload: jsonEncode(sale.toDbMap()),
          createdAt: now,
        ).toDbMap(),
      );

      return sale;
    });
  }

  Future<List<Sale>> getByCustomer(String customerId) =>
      _saleDao.getByCustomer(customerId);

  Future<Map<String, dynamic>> getTodayStats() => _saleDao.getTodayStats();
}
