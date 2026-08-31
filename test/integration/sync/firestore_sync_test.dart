import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/services/firestore_sync_service.dart';
import 'package:maisum/features/sync/data/sync_transport.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreSyncService service;
  const businessUid = 'biz-test-uid';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    service = FirestoreSyncService(fakeFirestore, businessUid);
  });

  group('FirestoreSyncService', () {
    test('implements SyncTransport with firestore transport name', () {
      expect(service, isA<SyncTransport>());
      expect(service.transportName, 'firestore');
    });

    test('create operation writes document to correct collection', () async {
      final item = SyncItem(
        id: 'sync-1',
        operation: 'create',
        entityType: 'customer',
        entityId: 'cust-1',
        payload: '{"id":"cust-1","name":"Filipe","phone":"840000001"}',
        createdAt: DateTime.now(),
      );
      await service.processSyncItem(item);

      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('customers')
          .doc('cust-1')
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['name'], 'Filipe');
      expect(doc.data()!['phone'], '840000001');
    });

    test(
      'update operation merges data without overwriting other fields',
      () async {
        await fakeFirestore
            .collection('businesses')
            .doc(businessUid)
            .collection('customers')
            .doc('cust-2')
            .set({
          'name': 'Old Name',
          'phone': '840000002',
          'total_points': 50,
        });

        final item = SyncItem(
          id: 'sync-2',
          operation: 'update',
          entityType: 'customer',
          entityId: 'cust-2',
          payload: '{"id":"cust-2","name":"New Name"}',
          createdAt: DateTime.now(),
        );
        await service.processSyncItem(item);

        final doc = await fakeFirestore
            .collection('businesses')
            .doc(businessUid)
            .collection('customers')
            .doc('cust-2')
            .get();
        expect(doc.data()!['name'], 'New Name');
        expect(doc.data()!['phone'], '840000002');
        expect(doc.data()!['total_points'], 50);
      },
    );

    test('delete operation removes document', () async {
      await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('rewards')
          .doc('reward-3')
          .set({'name': 'Temp Reward'});

      final item = SyncItem(
        id: 'sync-3',
        operation: 'delete',
        entityType: 'reward',
        entityId: 'reward-3',
        payload: '{}',
        createdAt: DateTime.now(),
      );
      await service.processSyncItem(item);

      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('rewards')
          .doc('reward-3')
          .get();
      expect(doc.exists, false);
    });

    test('throws ArgumentError for unknown operation', () async {
      final item = SyncItem(
        id: 'sync-4',
        operation: 'invalid',
        entityType: 'customer',
        entityId: 'cust-4',
        payload: '{}',
        createdAt: DateTime.now(),
      );
      await expectLater(service.processSyncItem(item), throwsArgumentError);
    });

    test('sale entityType maps to sales collection', () async {
      final item = SyncItem(
        id: 'sync-5',
        operation: 'create',
        entityType: 'sale',
        entityId: 'sale-1',
        payload: '{"id":"sale-1","amount":200,"points":2}',
        createdAt: DateTime.now(),
      );
      await service.processSyncItem(item);

      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('sales')
          .doc('sale-1')
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['amount'], 200);
    });

    test('reward entityType maps to rewards collection', () async {
      final item = SyncItem(
        id: 'sync-6',
        operation: 'create',
        entityType: 'reward',
        entityId: 'reward-1',
        payload:
            '{"id":"reward-1","name":"Corte grátis","points_required":500}',
        createdAt: DateTime.now(),
      );
      await service.processSyncItem(item);

      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('rewards')
          .doc('reward-1')
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['name'], 'Corte grátis');
    });

    test('usage_event uses its API handler instead of Firestore', () async {
      SyncItem? handledItem;
      service = FirestoreSyncService(
        fakeFirestore,
        businessUid,
        usageEventSyncHandler: (item) async => handledItem = item,
      );
      final item = SyncItem(
        id: 'sync-usage-1',
        operation: 'create',
        entityType: 'usage_event',
        entityId: 'usage-1',
        payload: '{"id":"usage-1","metric_key":"sales_count","quantity":1}',
        createdAt: DateTime.now(),
      );

      await service.processSyncItem(item);

      expect(handledItem, same(item));
      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('usage_events')
          .doc('usage-1')
          .get();
      expect(doc.exists, isFalse);
    });

    test('sensitive corrections use the authoritative API handler', () async {
      final handled = <SyncItem>[];
      service = FirestoreSyncService(
        fakeFirestore,
        businessUid,
        authoritativeSyncHandler: (item) async => handled.add(item),
      );
      final items = [
        SyncItem(
          id: 'sync-archive',
          operation: 'update',
          entityType: 'customer',
          entityId: 'customer-archive',
          payload:
              '{"id":"customer-archive","archived_at":1234,"updated_at":1234}',
          createdAt: DateTime.now(),
        ),
        SyncItem(
          id: 'sync-delete',
          operation: 'delete',
          entityType: 'customer',
          entityId: 'customer-delete',
          payload: '{"id":"customer-delete"}',
          createdAt: DateTime.now(),
        ),
        SyncItem(
          id: 'sync-cancel',
          operation: 'cancel',
          entityType: 'sale',
          entityId: 'sale-cancel',
          payload: '{"id":"sale-cancel","cancellation_reason":"Erro de valor"}',
          createdAt: DateTime.now(),
        ),
      ];

      for (final item in items) {
        await service.processSyncItem(item);
      }

      expect(handled, items);
      expect(
        (await fakeFirestore
                .collection('businesses')
                .doc(businessUid)
                .collection('customers')
                .doc('customer-archive')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await fakeFirestore
                .collection('businesses')
                .doc(businessUid)
                .collection('sales')
                .doc('sale-cancel')
                .get())
            .exists,
        isFalse,
      );
    });

    test('sync entity types map to Firestore collection names', () async {
      const mappings = {
        'merchant_item': 'merchant_items',
        'sale_item': 'sale_items',
        'customer_risk_score': 'customer_risk_scores',
        'recovery_task': 'recovery_tasks',
        'recovery_action': 'recovery_actions',
        'visit_report': 'visit_reports',
        'survey': 'surveys',
        'survey_question': 'survey_questions',
        'survey_response': 'survey_responses',
        'survey_response_answer': 'survey_response_answers',
        'app_user': 'app_users',
      };

      for (final entry in mappings.entries) {
        final entityId = '${entry.key}-1';
        final payload = entry.key == 'recovery_task'
            ? '{"id":"$entityId","customer_id":"customer-1","status":"open","updated_at":1234}'
            : '{"id":"$entityId","updated_at":1234}';
        final item = SyncItem(
          id: 'sync-${entry.key}',
          operation: 'create',
          entityType: entry.key,
          entityId: entityId,
          payload: payload,
          createdAt: DateTime.now(),
        );
        await service.processSyncItem(item);

        final mappedDoc = await fakeFirestore
            .collection('businesses')
            .doc(businessUid)
            .collection(entry.value)
            .doc(entityId)
            .get();
        expect(mappedDoc.exists, true, reason: entry.key);
        expect(mappedDoc.data()!['id'], entityId);

        final fallbackDoc = await fakeFirestore
            .collection('businesses')
            .doc(businessUid)
            .collection(entry.key)
            .doc(entityId)
            .get();
        expect(fallbackDoc.exists, false, reason: entry.key);
      }
    });

    test('sync_tombstone pulls from the plural Firestore collection', () async {
      await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('sync_tombstones')
          .doc('tombstone-1')
          .set({
        'merchant_id': businessUid,
        'entity_type': 'customer',
        'entity_id': 'customer-deleted',
        'deleted_at': 1234,
      });

      final rows = await service.fetchCollection('sync_tombstone');

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'tombstone-1');
      expect(rows.single['entity_id'], 'customer-deleted');
    });

    test('recovery task sync returns canonical open task across devices',
        () async {
      final first = SyncItem(
        id: 'sync-task-1',
        operation: 'create',
        entityType: 'recovery_task',
        entityId: 'task-canonical',
        payload:
            '{"id":"task-canonical","merchant_id":"merchant-1","customer_id":"customer-1","priority":"high","status":"open","created_at":1000,"updated_at":1000}',
        createdAt: DateTime.now(),
      );
      final second = SyncItem(
        id: 'sync-task-2',
        operation: 'create',
        entityType: 'recovery_task',
        entityId: 'task-provisional',
        payload:
            '{"id":"task-provisional","merchant_id":"merchant-1","customer_id":"customer-1","priority":"low","status":"open","created_at":2000,"updated_at":2000}',
        createdAt: DateTime.now(),
      );

      final created = await service.processSyncItem(first);
      final collision = await service.processSyncItem(second);

      expect(created?.canonicalEntity?['id'], 'task-canonical');
      expect(collision?.canonicalEntity?['id'], 'task-canonical');
      expect(
        (await fakeFirestore
                .collection('businesses')
                .doc(businessUid)
                .collection('recovery_tasks')
                .doc('task-provisional')
                .get())
            .exists,
        isFalse,
      );

      await service.processSyncItem(
        SyncItem(
          id: 'sync-complete',
          operation: 'update',
          entityType: 'recovery_task',
          entityId: 'task-canonical',
          payload:
              '{"id":"task-canonical","merchant_id":"merchant-1","customer_id":"customer-1","priority":"high","status":"completed","created_at":1000,"updated_at":3000}',
          createdAt: DateTime.now(),
        ),
      );
      final afterCompletion = await service.processSyncItem(second);
      expect(afterCompletion?.canonicalEntity?['id'], 'task-provisional');
    });

    test(
      'fetchCollectionSince returns only documents after the saved cursor',
      () async {
        final rewards = fakeFirestore
            .collection('businesses')
            .doc(businessUid)
            .collection('rewards');

        await rewards.doc('reward-1').set({
          'id': 'reward-1',
          'name': 'Primeiro',
          'points_required': 100,
          'updated_at': 1000,
        });
        await rewards.doc('reward-2').set({
          'id': 'reward-2',
          'name': 'Segundo',
          'points_required': 200,
          'updated_at': 2000,
        });
        await rewards.doc('reward-3').set({
          'id': 'reward-3',
          'name': 'Terceiro',
          'points_required': 300,
          'updated_at': 2000,
        });

        final docs = await service.fetchCollectionSince(
          entityType: 'reward',
          orderField: 'updated_at',
          lastValue: 2000,
          lastDocId: 'reward-2',
        );

        expect(docs.map((doc) => doc['id']), ['reward-3']);
      },
    );

    test('different businessUid uses separate path', () async {
      final otherService = FirestoreSyncService(fakeFirestore, 'other-biz');

      final item = SyncItem(
        id: 'sync-7',
        operation: 'create',
        entityType: 'customer',
        entityId: 'cust-shared',
        payload: '{"id":"cust-shared","name":"Isolado"}',
        createdAt: DateTime.now(),
      );
      await otherService.processSyncItem(item);

      // Original service's path should not have this document
      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('customers')
          .doc('cust-shared')
          .get();
      expect(doc.exists, false);

      // Other service's path should have it
      final otherDoc = await fakeFirestore
          .collection('businesses')
          .doc('other-biz')
          .collection('customers')
          .doc('cust-shared')
          .get();
      expect(otherDoc.exists, true);
    });
  });
}
