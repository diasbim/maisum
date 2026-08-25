import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/data/sync_transport.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';
import 'package:maisum/features/sync/sync_service.dart';

import '../../helpers/test_database.dart';

class _FakeSyncTransport implements SyncTransport {
  _FakeSyncTransport({Map<String, List<Map<String, dynamic>>>? collections})
      : _collections = collections ?? <String, List<Map<String, dynamic>>>{};

  final Map<String, List<Map<String, dynamic>>> _collections;
  final List<SyncItem> processed = <SyncItem>[];

  @override
  String get transportName => 'fake';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async {
    return List<Map<String, dynamic>>.from(
        _collections[entityType] ?? const []);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit = 200,
  }) async {
    return const [];
  }

  @override
  Future<void> processSyncItem(SyncItem item) async {
    processed.add(item);
  }
}

class _TransientFailSyncTransport extends _FakeSyncTransport {
  @override
  Future<void> processSyncItem(SyncItem item) async {
    throw const SyncTransportException(
      'Unable to resolve host firestore.googleapis.com',
      code: 'unavailable',
    );
  }
}

void main() {
  late SyncDao syncDao;
  late CustomerDao customerDao;

  setUp(() async {
    await setUpTestDatabase();
    syncDao = SyncDao(AppDatabase.instance, merchantId: 'merchant-1');
    customerDao = CustomerDao(AppDatabase.instance, merchantId: 'merchant-1');
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test('offline processQueue keeps items pending', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.none],
      initialOnline: false,
    );
    final transport = _FakeSyncTransport();
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await syncDao.enqueue(
      SyncItem(
        id: 'sync-1',
        operation: 'create',
        entityType: 'customer',
        entityId: 'cust-1',
        payload: '{"id":"cust-1"}',
        createdAt: DateTime.now(),
      ),
    );

    await service.processQueue();

    expect(transport.processed, isEmpty);
    expect(await syncDao.getPending(), hasLength(1));
    expect(service.status.phase, SyncPhase.offline);
    expect(service.status.pendingCount, 1);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('remote updates do not overwrite unsynced local data', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );

    final transport = _FakeSyncTransport(collections: {
      'customer': [
        {
          'id': 'cust-1',
          'merchant_id': 'merchant-1',
          'name': 'Remote Name',
          'phone': '841111111',
          'total_points': 50,
          'confirmed_points': 40,
          'canonical_customer_id': 'canonical-1',
          'account_state': 'UNCLAIMED',
          'relationship_status': 'ACTIVE',
          'lifecycle_stage': 'RETURNING',
          'retention_status': 'AT_RISK',
          'total_visits': 2,
          'total_spent': 500.0,
          'average_spend': 250.0,
          'schema_version': 1,
          'created_at': 2000,
          'updated_at': 2000,
        },
      ],
    });

    final db = await AppDatabase.instance.database;
    await db.insert('customers', {
      'id': 'cust-1',
      'merchant_id': 'merchant-1',
      'name': 'Local Name',
      'phone': '840000000',
      'total_points': 10,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 0,
    });

    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final customer = await customerDao.getById('cust-1');
    expect(customer?.name, 'Local Name');
    expect(customer?.phone, '840000000');
    expect(customer?.totalPoints, 10);
    expect(customer?.confirmedPoints, 40);
    expect(customer?.canonicalCustomerId, 'canonical-1');
    expect(customer?.lifecycleStage, CustomerLifecycleStage.returning);
    expect(customer?.retentionStatus, CustomerRetentionStatus.atRisk);
    expect(customer?.totalVisits, 2);
    expect(customer?.totalSpent, 500);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('server confirmation and immutable ledger merge into pending sale',
      () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      initialOnline: true,
    );
    final customer = await customerDao.create(
      name: 'Ana',
      phone: '841234568',
    );
    final db = await AppDatabase.instance.database;
    await db.insert('sales', <String, Object?>{
      'id': 'sale-1',
      'merchant_id': 'merchant-1',
      'customer_id': customer.id,
      'amount': 200,
      'points': 2,
      'created_at': 1000,
      'updated_at': 1000,
      'confirmation_status': 'PENDING',
      'synced': 0,
    });
    final transport = _FakeSyncTransport(collections: {
      'sale': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'sale-1',
          'merchant_id': 'merchant-1',
          'customer_id': customer.id,
          'amount': 200,
          'points': 999,
          'created_at': 1000,
          'updated_at': 2000,
          'confirmation_status': 'CONFIRMED',
          'confirmed_points': 2,
          'confirmed_at': 2000,
          'loyalty_policy_version': 1,
        },
      ],
      'loyalty_ledger': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'sale-sale-1',
          'merchant_id': 'merchant-1',
          'customer_id': customer.id,
          'entry_type': 'EARN',
          'points_delta': 2,
          'source_type': 'SALE',
          'source_id': 'sale-1',
          'policy_version': 1,
          'occurred_at': 1000,
          'created_at': 2000,
          'balance_after': 2,
        },
      ],
    });
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final sale = (await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: <Object?>['sale-1'],
    ))
        .single;
    expect(sale['points'], 2);
    expect(sale['confirmation_status'], 'CONFIRMED');
    expect(sale['confirmed_points'], 2);
    expect(
      await db.query(
        'loyalty_ledger',
        where: 'id = ?',
        whereArgs: <Object?>['sale-sale-1'],
      ),
      hasLength(1),
    );

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('transient network failures keep queue pending instead of failed',
      () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );

    final transport = _TransientFailSyncTransport();
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await syncDao.enqueue(
      SyncItem(
        id: 'sync-transient-1',
        operation: 'create',
        entityType: 'customer',
        entityId: 'cust-transient-1',
        payload: '{"id":"cust-transient-1"}',
        createdAt: DateTime.now(),
      ),
    );

    await service.processQueue();

    final stats = await syncDao.getStats();
    expect(stats.pendingTotal, 1);
    expect(stats.failed, 0);
    expect(stats.pendingReady, 0);
    expect(service.status.phase, isNot(SyncPhase.syncFailed));
    expect(service.status.lastError, isNull);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });
}
