import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late SaleDao saleDao;
  late String customerId;

  setUp(() async {
    await setUpTestDatabase();
    saleDao = SaleDao(AppDatabase.instance);
    final c = await CustomerDao(AppDatabase.instance).create(name: 'Test', phone: '840000099');
    customerId = c.id;
  });

  tearDown(tearDownTestDatabase);

  group('create — points calculation', () {
    test('200 MZN → 2 pts', () async => expect((await saleDao.create(customerId: customerId, amount: 200)).points, 2));
    test('100 MZN → 1 pt', () async => expect((await saleDao.create(customerId: customerId, amount: 100)).points, 1));
    test('150 MZN → 1 pt (floor)', () async => expect((await saleDao.create(customerId: customerId, amount: 150)).points, 1));
    test('99 MZN → 0 pts', () async => expect((await saleDao.create(customerId: customerId, amount: 99)).points, 0));
    test('500 MZN → 5 pts', () async => expect((await saleDao.create(customerId: customerId, amount: 500)).points, 5));

    test('inserts with synced=false and non-empty id', () async {
      final s = await saleDao.create(customerId: customerId, amount: 200);
      expect(s.synced, false);
      expect(s.id, isNotEmpty);
    });

    test('amount is stored exactly', () async {
      final s = await saleDao.create(customerId: customerId, amount: 350.5);
      expect(s.amount, 350.5);
    });
  });

  group('getByCustomer', () {
    test('returns sales in created_at DESC order', () async {
      await saleDao.create(customerId: customerId, amount: 100);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await saleDao.create(customerId: customerId, amount: 200);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await saleDao.create(customerId: customerId, amount: 300);

      final sales = await saleDao.getByCustomer(customerId);
      expect(sales[0].amount, 300);
      expect(sales[1].amount, 200);
      expect(sales[2].amount, 100);
    });

    test('returns empty list for unknown customer', () async {
      expect(await saleDao.getByCustomer('ghost'), isEmpty);
    });
  });

  group('getTodayStats', () {
    test('returns count and total_points for sales today', () async {
      await saleDao.create(customerId: customerId, amount: 200); // 2 pts
      await saleDao.create(customerId: customerId, amount: 300); // 3 pts
      final stats = await saleDao.getTodayStats();
      expect(stats['count'], 2);
      expect(stats['total_points'], 5);
    });

    test('returns zeros when no sales today', () async {
      final stats = await saleDao.getTodayStats();
      expect(stats['count'], 0);
      expect(stats['total_points'], 0);
    });
  });

  group('getUnsynced / markSynced', () {
    test('getUnsynced excludes synced sales', () async {
      final s1 = await saleDao.create(customerId: customerId, amount: 100);
      final s2 = await saleDao.create(customerId: customerId, amount: 200);
      await saleDao.markSynced(s1.id);
      final ids = (await saleDao.getUnsynced()).map((s) => s.id).toList();
      expect(ids, contains(s2.id));
      expect(ids, isNot(contains(s1.id)));
    });

    test('markSynced persists', () async {
      final s = await saleDao.create(customerId: customerId, amount: 100);
      await saleDao.markSynced(s.id);
      expect(await saleDao.getUnsynced(), isEmpty);
    });
  });
}

