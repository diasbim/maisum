import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/constants/app_constants.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';

import '../../helpers/test_database.dart';

SyncItem _item(String id, {int retryCount = 0, String status = 'pending'}) =>
    SyncItem(
      id: id,
      operation: 'create',
      entityType: 'customer',
      entityId: 'eid-$id',
      payload: '{"id":"eid-$id"}',
      retryCount: retryCount,
      status: status,
      createdAt: DateTime.now(),
    );

void main() {
  late SyncDao dao;
  late SyncDao otherDao;

  setUp(() async {
    await setUpTestDatabase();
    dao = SyncDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
      deviceId: 'device-1',
    );
    otherDao = SyncDao(
      AppDatabase.instance,
      merchantId: 'merchant-2',
      deviceId: 'device-2',
    );
  });

  tearDown(tearDownTestDatabase);

  group('enqueue', () {
    test('inserts with status=pending and retry_count=0', () async {
      await dao.enqueue(_item('e1'));
      final pending = await dao.getPending();
      expect(pending.length, 1);
      expect(pending.first.status, 'pending');
      expect(pending.first.retryCount, 0);
    });

    test('stores all fields correctly', () async {
      await dao.enqueue(_item('e2'));
      final item = (await dao.getPending()).first;
      expect(item.id, 'e2');
      expect(item.operation, 'create');
      expect(item.entityType, 'customer');
      expect(item.entityId, 'eid-e2');
    });

    test('stamps merchant and device metadata on queue rows', () async {
      await dao.enqueue(_item('tenant-meta'));
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'sync_queue',
        where: 'id = ?',
        whereArgs: ['tenant-meta'],
        limit: 1,
      );

      expect(rows.single['merchant_id'], 'merchant-1');
      expect(rows.single['device_id'], 'device-1');
    });
  });

  group('getPending', () {
    test('returns items in created_at ASC order', () async {
      await dao.enqueue(_item('a'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await dao.enqueue(_item('b'));
      final pending = await dao.getPending();
      expect(pending[0].id, 'a');
      expect(pending[1].id, 'b');
    });

    test('excludes items with retry_count >= maxSyncRetries', () async {
      await dao.enqueue(_item('max', retryCount: AppConstants.maxSyncRetries));
      expect(await dao.getPending(), isEmpty);
    });

    test('excludes synced items', () async {
      await dao.enqueue(_item('synced'));
      await dao.markSynced('synced');
      expect(await dao.getPending(), isEmpty);
    });

    test('excludes failed items', () async {
      await dao.enqueue(_item('failed'));
      await dao.markFailed('failed');
      expect(await dao.getPending(), isEmpty);
    });

    test('includes items with retry_count=2 (below limit)', () async {
      await dao.enqueue(_item('retry2', retryCount: 2));
      expect(await dao.getPending(), hasLength(1));
    });

    test('returns only items for the active merchant', () async {
      await dao.enqueue(_item('m1'));
      await otherDao.enqueue(_item('m2'));

      expect((await dao.getPending()).map((item) => item.id), contains('m1'));
      expect(
        (await dao.getPending()).map((item) => item.id),
        isNot(contains('m2')),
      );
    });
  });

  group('markSynced / markFailed', () {
    test('markSynced removes item from pending', () async {
      await dao.enqueue(_item('ms1'));
      await dao.markSynced('ms1');
      expect(await dao.getPending(), isEmpty);
    });

    test('markFailed removes item from pending', () async {
      await dao.enqueue(_item('mf1'));
      await dao.markFailed('mf1');
      expect(await dao.getPending(), isEmpty);
    });

    test('markSynced does not affect other items', () async {
      await dao.enqueue(_item('keep'));
      await dao.enqueue(_item('gone'));
      await dao.markSynced('gone');
      expect((await dao.getPending()).map((i) => i.id), contains('keep'));
    });
  });

  group('incrementRetry', () {
    test('increments retry_count by 1', () async {
      await dao.enqueue(_item('ir1'));
      await dao.incrementRetry('ir1');
      expect((await dao.getPending()).first.retryCount, 1);
    });

    test(
      'at retry_count=2 item is still pending; after increment it disappears',
      () async {
        await dao.enqueue(_item('ir2', retryCount: 2));
        expect(await dao.getPending(), hasLength(1));
        await dao.incrementRetry('ir2');
        expect(await dao.getPending(), isEmpty);
      },
    );
  });

  group('scheduleRetry', () {
    test('excludes items scheduled in the future', () async {
      await dao.enqueue(_item('future'));
      final nextAttempt = DateTime.now().add(const Duration(hours: 1));
      await dao.scheduleRetry('future', nextAttempt);
      expect(await dao.getPending(), isEmpty);
    });

    test('includes items scheduled in the past', () async {
      await dao.enqueue(_item('past'));
      final nextAttempt = DateTime.now().subtract(const Duration(minutes: 5));
      await dao.scheduleRetry('past', nextAttempt);
      expect(await dao.getPending(), hasLength(1));
    });
  });

  group('getPendingCount', () {
    test('counts only pending items below retry limit', () async {
      await dao.enqueue(_item('p1'));
      await dao.enqueue(_item('p2'));
      await dao.enqueue(_item('p3', retryCount: AppConstants.maxSyncRetries));
      await dao.enqueue(_item('p4'));
      await dao.markSynced('p4');
      expect(await dao.getPendingCount(), 2);
    });

    test('returns 0 when queue is empty', () async {
      expect(await dao.getPendingCount(), 0);
    });
  });

  group('clearSynced', () {
    test('removes synced items, leaves pending and failed', () async {
      await dao.enqueue(_item('cs1'));
      await dao.enqueue(_item('cs2'));
      await dao.enqueue(_item('cs3'));
      await dao.markSynced('cs1');
      await dao.markFailed('cs2');
      await dao.clearSynced();

      final pending = await dao.getPending();
      expect(pending.map((i) => i.id), contains('cs3'));
      expect(pending.map((i) => i.id), isNot(contains('cs1')));
    });

    test('does not affect pending items', () async {
      await dao.enqueue(_item('keep'));
      await dao.clearSynced();
      expect(await dao.getPendingCount(), 1);
    });
  });
}
