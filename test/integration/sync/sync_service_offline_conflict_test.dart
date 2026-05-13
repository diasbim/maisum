import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
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
    return List<Map<String, dynamic>>.from(_collections[entityType] ?? const []);
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

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });
}
