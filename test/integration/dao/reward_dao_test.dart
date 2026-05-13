import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/rewards/data/reward_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late RewardDao dao;

  setUp(() async {
    await setUpTestDatabase();
    dao = RewardDao(AppDatabase.instance);
  });

  tearDown(tearDownTestDatabase);

  group('create', () {
    test('inserts reward with active=true and synced=false by default', () async {
      final r = await dao.create(name: 'Corte Grátis', pointsRequired: 10);
      expect(r.active, true);
      expect(r.synced, false);
      expect(r.id, isNotEmpty);
    });

    test('persists optional description', () async {
      final r = await dao.create(name: 'Barba', pointsRequired: 5, description: 'Inclui modelação');
      expect((await dao.getById(r.id))!.description, 'Inclui modelação');
    });

    test('null description stored as null', () async {
      final r = await dao.create(name: 'No Desc', pointsRequired: 3);
      expect((await dao.getById(r.id))!.description, isNull);
    });
  });

  group('getAll', () {
    test('returns only active rewards ordered by points_required ASC', () async {
      await dao.create(name: 'C', pointsRequired: 30);
      await dao.create(name: 'A', pointsRequired: 10);
      await dao.create(name: 'B', pointsRequired: 20);
      final names = (await dao.getAll()).map((r) => r.name).toList();
      expect(names, ['A', 'B', 'C']);
    });

    test('excludes deactivated rewards', () async {
      final r1 = await dao.create(name: 'Active', pointsRequired: 5);
      final r2 = await dao.create(name: 'Inactive', pointsRequired: 10);
      await dao.deactivate(r2.id);
      final ids = (await dao.getAll()).map((r) => r.id).toList();
      expect(ids, contains(r1.id));
      expect(ids, isNot(contains(r2.id)));
    });

    test('returns empty list when no active rewards', () async {
      expect(await dao.getAll(), isEmpty);
    });
  });

  group('getById', () {
    test('returns reward for known id', () async {
      final r = await dao.create(name: 'Test', pointsRequired: 8);
      expect((await dao.getById(r.id))!.name, 'Test');
    });

    test('returns null for unknown id', () async {
      expect(await dao.getById('ghost'), isNull);
    });
  });

  group('update', () {
    test('updates pointsRequired', () async {
      final r = await dao.create(name: 'Original', pointsRequired: 10);
      await dao.update(r.copyWith(pointsRequired: 15));
      expect((await dao.getById(r.id))!.pointsRequired, 15);
    });

    test('updates name', () async {
      final r = await dao.create(name: 'Old', pointsRequired: 10);
      await dao.update(r.copyWith(name: 'New'));
      expect((await dao.getById(r.id))!.name, 'New');
    });
  });

  group('getUnsynced / markSynced', () {
    test('getUnsynced returns only unsynced rewards', () async {
      final r1 = await dao.create(name: 'X', pointsRequired: 5);
      final r2 = await dao.create(name: 'Y', pointsRequired: 10);
      await dao.markSynced(r1.id);
      final ids = (await dao.getUnsynced()).map((r) => r.id).toList();
      expect(ids, contains(r2.id));
      expect(ids, isNot(contains(r1.id)));
    });
  });
}

