import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/database/app_database.dart';
import 'package:loyalty_app/features/customers/data/customer_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late CustomerDao dao;

  setUp(() async {
    await setUpTestDatabase();
    dao = CustomerDao(AppDatabase.instance);
  });

  tearDown(tearDownTestDatabase);

  group('create', () {
    test('inserts and returns customer with non-empty uuid', () async {
      final c = await dao.create(name: 'Ana Mabjaia', phone: '840000001');
      expect(c.id, isNotEmpty);
      expect(c.name, 'Ana Mabjaia');
      expect(c.phone, '840000001');
      expect(c.totalPoints, 0);
      expect(c.synced, false);
    });

    test('uses phone as name when name is empty', () async {
      final c = await dao.create(name: '', phone: '840000002');
      expect(c.name, '840000002');
    });

    test('throws on duplicate phone (UNIQUE constraint)', () async {
      await dao.create(name: 'A', phone: '840000003');
      expect(() => dao.create(name: 'B', phone: '840000003'), throwsA(anything));
    });
  });

  group('findByPhone', () {
    test('returns customer for known phone', () async {
      await dao.create(name: 'Carlos', phone: '840000010');
      final c = await dao.findByPhone('840000010');
      expect(c, isNotNull);
      expect(c!.name, 'Carlos');
    });

    test('returns null for unknown phone', () async {
      expect(await dao.findByPhone('999999999'), isNull);
    });
  });

  group('getById', () {
    test('returns customer for known id', () async {
      final created = await dao.create(name: 'Dinis', phone: '840000020');
      final found = await dao.getById(created.id);
      expect(found, isNotNull);
      expect(found!.id, created.id);
    });

    test('returns null for unknown id', () async {
      expect(await dao.getById('ghost'), isNull);
    });
  });

  group('search', () {
    setUp(() async {
      await dao.create(name: 'Ana Costa', phone: '841000001');
      await dao.create(name: 'Bruno Lopes', phone: '842000002');
      await dao.create(name: 'Carlos Matos', phone: '843000003');
    });

    test('finds by partial phone', () async {
      final results = await dao.search('842');
      expect(results.length, 1);
      expect(results.first.name, 'Bruno Lopes');
    });

    test('finds by partial name', () async {
      final results = await dao.search('Costa');
      expect(results.length, 1);
      expect(results.first.name, 'Ana Costa');
    });

    test('returns empty list when no match', () async {
      expect(await dao.search('ZZZZ'), isEmpty);
    });
  });

  group('searchForSale', () {
    setUp(() async {
      await dao.create(name: 'Ana Costa', phone: '841000001');
      await dao.create(name: 'Bruno Lopes', phone: '842000002');
      await dao.create(name: 'Carlos Matos', phone: '843000003');
    });

    test('finds by phone prefix', () async {
      final results = await dao.searchForSale('842');
      expect(results.length, 1);
      expect(results.first.name, 'Bruno Lopes');
    });

    test('finds by name prefix', () async {
      final results = await dao.searchForSale('Ana');
      expect(results.length, 1);
      expect(results.first.name, 'Ana Costa');
    });

    test('does not use substring matching for sale lookup', () async {
      final results = await dao.searchForSale('Costa');
      expect(results, isEmpty);
    });
  });

  group('getAll', () {
    test('returns customers ordered by name ASC', () async {
      await dao.create(name: 'Zara', phone: '841111001');
      await dao.create(name: 'Abel', phone: '841111002');
      await dao.create(name: 'Maria', phone: '841111003');
      final names = (await dao.getAll()).map((c) => c.name).toList();
      expect(names, ['Abel', 'Maria', 'Zara']);
    });

    test('returns empty list when no customers', () async {
      expect(await dao.getAll(), isEmpty);
    });
  });

  group('updatePoints', () {
    test('sets new totalPoints value', () async {
      final c = await dao.create(name: 'Edna', phone: '849000001');
      await dao.updatePoints(c.id, 25);
      final updated = await dao.getById(c.id);
      expect(updated!.totalPoints, 25);
    });

    test('overwrites previous value', () async {
      final c = await dao.create(name: 'Fátima', phone: '849000002');
      await dao.updatePoints(c.id, 10);
      await dao.updatePoints(c.id, 20);
      expect((await dao.getById(c.id))!.totalPoints, 20);
    });
  });

  group('getUnsynced / markSynced', () {
    test('getUnsynced returns only unsynced customers', () async {
      final c1 = await dao.create(name: 'E', phone: '848000001');
      final c2 = await dao.create(name: 'F', phone: '848000002');
      await dao.markSynced(c1.id);
      final ids = (await dao.getUnsynced()).map((c) => c.id).toList();
      expect(ids, contains(c2.id));
      expect(ids, isNot(contains(c1.id)));
    });

    test('markSynced sets synced=true', () async {
      final c = await dao.create(name: 'G', phone: '847000001');
      await dao.markSynced(c.id);
      expect((await dao.getById(c.id))!.synced, true);
    });

    test('freshly created customer is unsynced', () async {
      final c = await dao.create(name: 'H', phone: '846000001');
      expect((await dao.getById(c.id))!.synced, false);
    });
  });
}
