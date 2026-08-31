import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/customer.dart';
import 'customer_dao.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../../sync/data/sync_transport.dart';
import '../../../core/services/connectivity_service.dart';

class CustomerRepository {
  CustomerRepository(
    this._dao,
    this._syncDao, {
    SyncTransport? syncTransport,
    ConnectivityService? connectivity,
    this.appUserId,
  })  : _syncTransport = syncTransport,
        _connectivity = connectivity;

  final CustomerDao _dao;
  final SyncDao _syncDao;
  final SyncTransport? _syncTransport;
  final ConnectivityService? _connectivity;
  final String? appUserId;
  static const _uuid = Uuid();

  Future<List<Customer>> search(String query) => _dao.search(query);

  Future<List<Customer>> searchForSale(String query) =>
      _dao.searchForSale(query);

  Future<Customer?> findByPhone(String phone) => _dao.findByPhone(phone);

  Future<Customer?> getById(String id) => _dao.getById(id);

  Future<Customer?> findByCanonicalCustomerId(String canonicalCustomerId) =>
      _dao.findByCanonicalCustomerId(canonicalCustomerId);

  Future<List<Customer>> getAll() => _dao.getAll();

  Future<List<Customer>> getArchived() => _dao.getArchived();

  Future<List<Customer>> getRecent({int limit = 6}) =>
      _dao.getRecent(limit: limit);

  Future<int> count() => _dao.getCount();

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

  Future<void> updateConsent(
    String id, {
    required CustomerConsentStatus marketing,
    required CustomerConsentStatus whatsapp,
  }) async {
    await _dao.updateConsent(
      id,
      marketing: marketing,
      whatsapp: whatsapp,
    );
    final customer = await _dao.getById(id);
    if (customer == null) {
      throw StateError('Customer not found after consent update');
    }

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

  Future<Customer> archiveCustomer(String id) =>
      _setArchived(id, archived: true);

  Future<Customer> restoreCustomer(String id) =>
      _setArchived(id, archived: false);

  Future<Customer> _setArchived(
    String id, {
    required bool archived,
  }) async {
    final customer = await _dao.setArchived(
      id,
      archived: archived,
      appUserId: appUserId,
    );
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'customer',
        entityId: id,
        payload: jsonEncode(
          _customerPayload(customer, includeArchive: true),
        ),
        createdAt: DateTime.now(),
      ),
    );
    return customer;
  }

  Future<Map<String, int>> getDeleteDependencies(String id) =>
      _dao.getDeleteDependencies(id);

  Future<void> deleteCustomerPermanently(String id) async {
    final blockers = await _dao.getDeleteDependencies(id);
    if (blockers.isNotEmpty) {
      throw StateError('O cliente possui histórico associado.');
    }
    final connectivity = _connectivity;
    if (connectivity == null || !await connectivity.check()) {
      throw StateError('A eliminação definitiva exige ligação à internet.');
    }
    final transport = _syncTransport;
    if (transport == null) {
      throw StateError('O serviço de sincronização não está disponível.');
    }
    final merchantId = _dao.merchantId;
    if (merchantId == null || merchantId.isEmpty) {
      throw StateError('Não existe um negócio ativo.');
    }
    await transport.processSyncItem(
      SyncItem(
        id: _uuid.v4(),
        operation: 'delete',
        entityType: 'customer',
        entityId: id,
        payload: jsonEncode({
          'id': id,
          'merchant_id': merchantId,
          'deleted_by_app_user_id': appUserId,
        }),
        createdAt: DateTime.now(),
      ),
    );
    await _dao.deletePermanently(id);
  }

  Future<void> addPoints(String customerId, int points) async {
    final customer = await _dao.getById(customerId);
    if (customer == null) return;
    final newTotal = customer.totalPoints + points;
    await _dao.updatePoints(customerId, newTotal);
  }

  Map<String, dynamic> _customerPayload(
    Customer customer, {
    bool includeArchive = false,
  }) =>
      {
        ...customer.toClientSyncMap(),
        'merchant_id': _dao.merchantId,
        if (includeArchive) ...{
          'archived_at': customer.archivedAt?.millisecondsSinceEpoch,
          'archived_by_app_user_id': customer.archivedByAppUserId,
        },
      };
}
