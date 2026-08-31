import 'dart:async';
import 'dart:convert';

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
  Future<SyncProcessResult?> processSyncItem(SyncItem item) async {
    processed.add(item);
    return null;
  }
}

class _TransientFailSyncTransport extends _FakeSyncTransport {
  @override
  Future<SyncProcessResult?> processSyncItem(SyncItem item) async {
    throw const SyncTransportException(
      'Unable to resolve host firestore.googleapis.com',
      code: 'unavailable',
    );
  }
}

class _PermissionDeniedSyncTransport extends _FakeSyncTransport {
  @override
  Future<SyncProcessResult?> processSyncItem(SyncItem item) async {
    throw const SyncTransportException(
      'Forbidden',
      code: 'permission-denied',
    );
  }
}

class _CanonicalRecoveryTransport extends _FakeSyncTransport {
  @override
  Future<SyncProcessResult?> processSyncItem(SyncItem item) async {
    processed.add(item);
    if (item.entityType != 'recovery_task') return null;
    return const SyncProcessResult(
      canonicalEntity: {
        'id': 'task-canonical',
        'merchant_id': 'merchant-1',
        'customer_id': 'cust-recovery',
        'priority': 'high',
        'status': 'open',
        'created_at': 1000,
        'updated_at': 2000,
      },
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

  test('customer tombstone removes the local customer', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final customer = await customerDao.create(
      name: 'Eliminar noutro dispositivo',
      phone: '841230099',
    );
    final transport = _FakeSyncTransport(
      collections: {
        'sync_tombstone': [
          {
            'id': 'customer__merchant-1__${customer.id}',
            'merchant_id': 'merchant-1',
            'entity_type': 'customer',
            'entity_id': customer.id,
            'deleted_at': DateTime.now().millisecondsSinceEpoch,
          },
        ],
      },
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    expect(await customerDao.getById(customer.id), isNull);
    final db = await AppDatabase.instance.database;
    final tombstones = await db.query(
      'sync_tombstones',
      where: 'entity_id = ?',
      whereArgs: [customer.id],
    );
    expect(tombstones, hasLength(1));

    connectivity.dispose();
    await controller.close();
  });

  test('successful processQueue can process items added by a later cycle',
      () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
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
        id: 'sync-first',
        operation: 'create',
        entityType: 'customer',
        entityId: 'cust-first',
        payload: '{"id":"cust-first"}',
        createdAt: DateTime.now(),
      ),
    );

    await service.processQueue();

    expect(service.status.phase, SyncPhase.synced);

    await syncDao.enqueue(
      SyncItem(
        id: 'sync-second',
        operation: 'create',
        entityType: 'customer',
        entityId: 'cust-second',
        payload: '{"id":"cust-second"}',
        createdAt: DateTime.now(),
      ),
    );

    await service.processQueue();

    expect(
      transport.processed.map((item) => item.id),
      ['sync-first', 'sync-second'],
    );
    expect(await syncDao.getPending(), isEmpty);
    expect(service.status.phase, SyncPhase.synced);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('defers entitlement pull until local merchant bootstrap completes',
      () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final transport = _FakeSyncTransport(
      collections: {
        'entitlement': [
          {
            'id': 'merchant-1-analytics',
            'merchant_id': 'merchant-1',
            'feature_key': 'analytics',
            'is_enabled': true,
            'updated_at': 1000,
          },
        ],
      },
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );
    final db = await AppDatabase.instance.database;

    await service.processQueue();

    expect(await db.query('entitlements'), isEmpty);
    expect(
      await db.query(
        'sync_state',
        where: 'entity_type = ?',
        whereArgs: ['entitlement'],
      ),
      isEmpty,
    );

    await db.insert('merchants', {
      'id': 'merchant-1',
      'phone': '+258841234567',
      'merchant_name': 'Merchant 1',
      'slug': 'merchant-1',
      'subscription_status': 'TRIAL',
      'created_at': 1000,
      'updated_at': 1000,
    });

    await service.processQueue();

    final entitlements = await db.query('entitlements');
    expect(entitlements, hasLength(1));
    expect(entitlements.single['feature_key'], 'analytics');

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('imports legacy customer without updated_at', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final transport = _FakeSyncTransport(
      collections: {
        'customer': [
          {
            'id': 'legacy-customer',
            'merchant_id': 'merchant-1',
            'name': 'Legacy Customer',
            'phone': '842222222',
            'total_points': 4,
            'created_at': '2026-07-09T18:34:25.564Z',
          },
        ],
      },
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final customer = await customerDao.getById('legacy-customer');
    final expectedTimestamp =
        DateTime.parse('2026-07-09T18:34:25.564Z').millisecondsSinceEpoch;
    expect(customer, isNotNull);
    expect(customer?.createdAt.millisecondsSinceEpoch, expectedTimestamp);
    expect(customer?.updatedAt?.millisecondsSinceEpoch, expectedTimestamp);
    expect(customer?.synced, isTrue);
    expect(service.status.phase, SyncPhase.synced);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('imports legacy camelCase reward', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final transport = _FakeSyncTransport(
      collections: {
        'reward': [
          {
            'id': 'legacy-reward',
            'merchantId': 'merchant-1',
            'title': 'Legacy Reward',
            'pointsRequired': 10,
            'description': 'Imported legacy reward',
          },
        ],
      },
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'rewards',
      where: 'merchant_id = ? AND id = ?',
      whereArgs: ['merchant-1', 'legacy-reward'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Legacy Reward');
    expect(rows.single['points_required'], 10);
    expect(rows.single['active'], 1);
    expect(rows.single['created_at'], isA<int>());
    expect(rows.single['updated_at'], rows.single['created_at']);
    expect(rows.single['synced'], 1);
    expect(service.status.phase, SyncPhase.synced);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('imports legacy camelCase redemption', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final transport = _FakeSyncTransport(
      collections: {
        'customer': [
          {
            'id': 'legacy-redemption-customer',
            'merchantId': 'merchant-1',
            'name': 'Legacy Customer',
            'phone': '843333333',
            'createdAt': '2026-06-27T18:20:00.000Z',
          },
        ],
        'reward': [
          {
            'id': 'legacy-redemption-reward',
            'merchantId': 'merchant-1',
            'title': 'Legacy Reward',
            'pointsRequired': 10,
          },
        ],
        'redemption': [
          {
            'id': 'legacy-redemption',
            'merchantId': 'merchant-1',
            'customerId': 'legacy-redemption-customer',
            'rewardId': 'legacy-redemption-reward',
            'pointsRedeemed': 10,
            'createdAt': '2026-06-27T18:22:04.421Z',
            'status': 'synced',
          },
        ],
      },
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'redemptions',
      where: 'merchant_id = ? AND id = ?',
      whereArgs: ['merchant-1', 'legacy-redemption'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['customer_id'], 'legacy-redemption-customer');
    expect(rows.single['reward_id'], 'legacy-redemption-reward');
    expect(rows.single['points_spent'], 10);
    expect(
      rows.single['redeemed_at'],
      DateTime.parse('2026-06-27T18:22:04.421Z').millisecondsSinceEpoch,
    );
    expect(rows.single['synced'], 1);
    expect(service.status.phase, SyncPhase.synced);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('skips orphaned remote redemption without failing sync', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final transport = _FakeSyncTransport(
      collections: {
        'redemption': [
          {
            'id': 'orphaned-redemption',
            'merchantId': 'merchant-1',
            'customerId': 'missing-customer',
            'rewardId': 'missing-reward',
            'pointsRedeemed': 10,
            'createdAt': '2026-06-27T18:22:04.421Z',
          },
        ],
      },
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final db = await AppDatabase.instance.database;
    expect(
      await db.query(
        'redemptions',
        where: 'merchant_id = ? AND id = ?',
        whereArgs: ['merchant-1', 'orphaned-redemption'],
      ),
      isEmpty,
    );
    expect(service.status.phase, SyncPhase.synced);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });

  test('queued recovery task converges to remote canonical task', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final transport = _CanonicalRecoveryTransport();
    final db = await AppDatabase.instance.database;
    await db.insert('customers', {
      'id': 'cust-recovery',
      'merchant_id': 'merchant-1',
      'name': 'Cliente',
      'phone': '841111111',
      'total_points': 0,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 1,
    });
    await db.insert('recovery_tasks', {
      'id': 'task-provisional',
      'merchant_id': 'merchant-1',
      'customer_id': 'cust-recovery',
      'priority': 'low',
      'status': 'open',
      'created_at': 1500,
      'updated_at': 1500,
      'synced': 0,
    });
    await syncDao.enqueue(
      SyncItem(
        id: 'sync-recovery',
        operation: 'create',
        entityType: 'recovery_task',
        entityId: 'task-provisional',
        payload:
            '{"id":"task-provisional","merchant_id":"merchant-1","customer_id":"cust-recovery","priority":"low","status":"open","created_at":1500,"updated_at":1500}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1500),
      ),
    );
    await syncDao.enqueue(
      SyncItem(
        id: 'sync-action',
        operation: 'create',
        entityType: 'recovery_action',
        entityId: 'action-1',
        payload:
            '{"id":"action-1","merchant_id":"merchant-1","customer_id":"cust-recovery","task_id":"task-provisional","action_type":"CALL","created_at":1600,"updated_at":1600}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1600),
      ),
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
    );

    await service.processQueue();

    final tasks = await db.query(
      'recovery_tasks',
      where: 'merchant_id = ? AND customer_id = ?',
      whereArgs: ['merchant-1', 'cust-recovery'],
    );
    expect(tasks, hasLength(1));
    expect(tasks.single['id'], 'task-canonical');
    expect(tasks.single['synced'], 1);
    final syncedAction = transport.processed.singleWhere(
      (item) => item.entityType == 'recovery_action',
    );
    expect(
      (jsonDecode(syncedAction.payload) as Map<String, dynamic>)['task_id'],
      'task-canonical',
    );
    expect(await syncDao.getAllItems(), isEmpty);

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

  test('server cancellation resolves conflicting unsynced cancellation',
      () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final customer = await customerDao.create(
      name: 'Venda em conflito',
      phone: '841234598',
    );
    final db = await AppDatabase.instance.database;
    await db.insert('sales', {
      'id': 'sale-cancel-conflict',
      'merchant_id': 'merchant-1',
      'customer_id': customer.id,
      'amount': 200,
      'points': 2,
      'created_at': 1000,
      'updated_at': 2000,
      'confirmation_status': 'CONFIRMED',
      'cancellation_status': 'CANCELLED',
      'cancelled_at': 2000,
      'cancellation_reason': 'Motivo local',
      'synced': 0,
    });
    final transport = _FakeSyncTransport(
      collections: {
        'sale': [
          {
            'id': 'sale-cancel-conflict',
            'merchant_id': 'merchant-1',
            'customer_id': customer.id,
            'amount': 200,
            'points': 2,
            'created_at': 1000,
            'updated_at': 3000,
            'confirmation_status': 'CANCELLED',
            'cancellation_status': 'CANCELLED',
            'cancelled_at': 1500,
            'cancelled_by_app_user_id': 'staff-server',
            'cancellation_reason': 'Motivo confirmado no servidor',
          },
        ],
      },
    );
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
      whereArgs: ['sale-cancel-conflict'],
    ))
        .single;
    expect(sale['cancellation_reason'], 'Motivo confirmado no servidor');
    expect(sale['cancelled_by_app_user_id'], 'staff-server');
    expect(sale['cancelled_at'], 1500);

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

  test('permission errors use the localized sync message', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    final connectivity = ConnectivityService(
      onConnectivityChanged: controller.stream,
      checkConnectivity: () async => [ConnectivityResult.wifi],
      initialOnline: true,
    );
    final service = SyncService(
      AppDatabase.instance,
      syncDao,
      _PermissionDeniedSyncTransport(),
      connectivity,
    );

    await syncDao.enqueue(
      SyncItem(
        id: 'sync-permission-1',
        operation: 'create',
        entityType: 'usage_event',
        entityId: 'usage-event-1',
        payload: '{"id":"usage-event-1"}',
        createdAt: DateTime.now(),
      ),
    );

    await service.processQueue();

    final item = (await syncDao.getAllItems()).single;
    expect(item.status, 'failed');
    final db = await AppDatabase.instance.database;
    final storedItem = (await db.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: ['sync-permission-1'],
    ))
        .single;
    expect(storedItem['last_error'], 'Sem permissão para sincronizar.');
    expect(service.status.lastError, 'Sem permissão para sincronizar.');

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });
}
