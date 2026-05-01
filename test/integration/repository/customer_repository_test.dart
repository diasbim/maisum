import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/database/app_database.dart';
import 'package:loyalty_app/features/customers/data/customer_dao.dart';
import 'package:loyalty_app/features/customers/data/customer_repository.dart';
import 'package:loyalty_app/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late CustomerRepository repo;
  late SyncDao syncDao;

  setUp(() async {
    await setUpTestDatabase();
    final db = AppDatabase.instance;
    syncDao = SyncDao(db);
    repo = CustomerRepository(CustomerDao(db), syncDao);
  });

  tearDown(tearDownTestDatabase);

  group('createCustomer', () {
    test('persists customer to the database', () async {
      final c = await repo.createCustomer(name: 'Filipe', phone: '840000201');
      final found = await repo.findByPhone('840000201');
      expect(found, isNotNull);
      expect(found!.id, c.id);
      expect(found.name, 'Filipe');
    });

    test('enqueues sync item with operation=create, entityType=customer', () async {
      final c = await repo.createCustomer(name: 'Graça', phone: '840000202');
      final items = await syncDao.getPending();
      expect(items.length, 1);
      expect(items.first.operation, 'create');
      expect(items.first.entityType, 'customer');
      expect(items.first.entityId, c.id);
    });

    test('payload contains customer data', () async {
      final c = await repo.createCustomer(name: 'Hugo', phone: '840000203');
      final payload = (await syncDao.getPending()).first.payload;
      expect(payload, contains(c.id));
      expect(payload, contains('840000203'));
    });

    test('each customer creates one sync item', () async {
      await repo.createCustomer(name: 'I', phone: '840000210');
      await repo.createCustomer(name: 'J', phone: '840000211');
      expect(await syncDao.getPendingCount(), 2);
    });
  });

  group('addPoints', () {
    test('increases customer totalPoints from 0', () async {
      final c = await repo.createCustomer(name: 'Ivone', phone: '840000204');
      await repo.addPoints(c.id, 5);
      expect((await repo.getById(c.id))!.totalPoints, 5);
    });

    test('accumulates across multiple calls', () async {
      final c = await repo.createCustomer(name: 'João', phone: '840000205');
      await repo.addPoints(c.id, 3);
      await repo.addPoints(c.id, 7);
      expect((await repo.getById(c.id))!.totalPoints, 10);
    });

    test('does nothing for nonexistent customer', () async {
      await expectLater(repo.addPoints('ghost-id', 10), completes);
    });
  });

  group('search / getAll', () {
    test('search returns customers matching phone fragment', () async {
      await repo.createCustomer(name: 'Karina', phone: '841500001');
      await repo.createCustomer(name: 'Luís', phone: '842600002');
      final results = await repo.search('841');
      expect(results.length, 1);
      expect(results.first.name, 'Karina');
    });

    test('getAll returns all customers', () async {
      await repo.createCustomer(name: 'M', phone: '840000220');
      await repo.createCustomer(name: 'N', phone: '840000221');
      expect((await repo.getAll()).length, 2);
    });
  });
}
