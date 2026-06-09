import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/settings/data/staff_management_repository.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/data/sync_transport.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';
import 'package:maisum/features/sync/sync_service.dart';

import '../../helpers/test_database.dart';

class _FakeSyncTransport implements SyncTransport {
  final List<SyncItem> processed = <SyncItem>[];

  @override
  String get transportName => 'fake';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async {
    return const [];
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
  late StaffManagementRepository repository;

  setUp(() async {
    await setUpTestDatabase();
    syncDao = SyncDao(AppDatabase.instance, merchantId: 'merchant-1');
    repository = StaffManagementRepository(
      AppDatabase.instance,
      syncDao,
      merchantId: 'merchant-1',
      currentAppUserId: 'owner-1',
    );

    final db = await AppDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('merchants', {
      'id': 'merchant-1',
      'phone': '+258840000000',
      'merchant_name': 'Minha Loja',
      'slug': 'minha-loja',
      'subscription_status': 'TRIAL',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('app_users', {
      'id': 'owner-1',
      'merchant_id': 'merchant-1',
      'phone': '+258840000000',
      'role': 'OWNER',
      'status': 'ACTIVE',
      'accepted_at': now,
      'created_at': now,
      'updated_at': now,
      'last_login_at': now,
    });
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test('owner create and deactivate staff enqueues app_user sync operations',
      () async {
    final created = await repository.createManualStaff(
      phone: '+258840000111',
    );

    expect(created.role, 'STAFF');
    expect(created.status, 'ACTIVE');

    final deactivated = await repository.setStaffActive(
      staffId: created.id,
      isActive: false,
    );

    expect(deactivated.status, 'INACTIVE');
    expect(deactivated.deactivatedAt, isNotNull);

    final queue = await syncDao.getAllItems();
    final appUserItems =
        queue.where((item) => item.entityType == 'app_user').toList();

    expect(appUserItems.length, 2);
    expect(appUserItems.any((item) => item.operation == 'create'), isTrue);
    expect(appUserItems.any((item) => item.operation == 'update'), isTrue);

    final updateItem = appUserItems.firstWhere(
      (item) => item.operation == 'update',
    );
    final payload = jsonDecode(updateItem.payload) as Map<String, dynamic>;
    expect(payload['status'], 'INACTIVE');
    expect(payload['merchant_id'], 'merchant-1');
  });

  test('staff app_user queue items are processed and cleared by sync service',
      () async {
    final created = await repository.createManualStaff(
      phone: '+258840000222',
    );
    await repository.setStaffActive(
      staffId: created.id,
      isActive: false,
    );

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

    await service.processQueue();

    final processedAppUsers = transport.processed
        .where((item) => item.entityType == 'app_user')
        .toList();
    expect(processedAppUsers.length, 2);

    final remainingQueue = await syncDao.getAllItems();
    expect(
        remainingQueue.where((item) => item.entityType == 'app_user'), isEmpty);

    service.dispose();
    connectivity.dispose();
    await controller.close();
  });
}
