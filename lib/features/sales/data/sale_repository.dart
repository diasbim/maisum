import 'dart:convert';
import '../domain/sale.dart';
import 'sale_dao.dart';
import '../../customers/data/customer_dao.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import 'package:uuid/uuid.dart';

class SaleRepository {
  SaleRepository(this._saleDao, this._customerDao, this._syncDao);

  final SaleDao _saleDao;
  final CustomerDao _customerDao;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<Sale> createSale({
    required String customerId,
    required double amount,
  }) async {
    final sale = await _saleDao.create(
      customerId: customerId,
      amount: amount,
    );

    // Update customer total points immediately
    final customer = await _customerDao.getById(customerId);
    if (customer != null) {
      final newTotal = customer.totalPoints + sale.points;
      await _customerDao.updatePoints(customerId, newTotal);

      // Enqueue the updated customer so Firestore reflects the new total_points
      final updatedCustomer = customer.copyWith(
        totalPoints: newTotal,
        updatedAt: DateTime.now(),
      );
      await _syncDao.enqueue(SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'customer',
        entityId: customerId,
        payload: jsonEncode(updatedCustomer.toDbMap()),
        createdAt: DateTime.now(),
      ));
    }

    // Enqueue sale for sync
    await _syncDao.enqueue(SyncItem(
      id: _uuid.v4(),
      operation: 'create',
      entityType: 'sale',
      entityId: sale.id,
      payload: jsonEncode(sale.toDbMap()),
      createdAt: DateTime.now(),
    ));

    return sale;
  }

  Future<List<Sale>> getByCustomer(String customerId) =>
      _saleDao.getByCustomer(customerId);

  Future<Map<String, dynamic>> getTodayStats() => _saleDao.getTodayStats();
}
