import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/services/firestore_sync_service.dart';
import 'package:loyalty_app/features/sync/data/sync_transport.dart';
import 'package:loyalty_app/features/sync/domain/sync_item.dart';

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
          .collection('customers')
          .doc('cust-3')
          .set({'name': 'Temp Customer'});

      final item = SyncItem(
        id: 'sync-3',
        operation: 'delete',
        entityType: 'customer',
        entityId: 'cust-3',
        payload: '{}',
        createdAt: DateTime.now(),
      );
      await service.processSyncItem(item);

      final doc = await fakeFirestore
          .collection('businesses')
          .doc(businessUid)
          .collection('customers')
          .doc('cust-3')
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
