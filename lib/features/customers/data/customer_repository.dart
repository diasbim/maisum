import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/customer.dart';
import 'customer_dao.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';

class CustomerRepository {
  CustomerRepository(this._dao, this._syncDao);

  final CustomerDao _dao;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<List<Customer>> search(String query) => _dao.search(query);

  Future<List<Customer>> searchForSale(String query) =>
      _dao.searchForSale(query);

  Future<Customer?> findByPhone(String phone) => _dao.findByPhone(phone);

  Future<Customer?> getById(String id) => _dao.getById(id);

  Future<List<Customer>> getAll() => _dao.getAll();

  Future<List<Customer>> getRecent({int limit = 6}) =>
      _dao.getRecent(limit: limit);

  Future<Customer> createCustomer({
    required String name,
    required String phone,
  }) async {
    final customer = await _dao.create(name: name, phone: phone);
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'customer',
        entityId: customer.id,
        payload: jsonEncode(_customerPayload(customer)),
        createdAt: DateTime.now(),
      ),
    );
    return customer;
  }

  Future<void> updateCustomer(
    String id, {
    required String name,
    required String phone,
  }) async {
    await _dao.update(id, name: name, phone: phone);
    final customer = await _dao.getById(id);
    if (customer != null) {
      await _syncDao.enqueue(
        SyncItem(
          id: _uuid.v4(),
          operation: 'update',
          entityType: 'customer',
          entityId: id,
          payload: jsonEncode(_customerPayload(customer)),
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> addPoints(String customerId, int points) async {
    final customer = await _dao.getById(customerId);
    if (customer == null) return;
    final newTotal = customer.totalPoints + points;
    await _dao.updatePoints(customerId, newTotal);
  }

  Map<String, dynamic> _customerPayload(Customer customer) => {
    ...customer.toDbMap(),
    'merchant_id': _dao.merchantId,
  };
}
