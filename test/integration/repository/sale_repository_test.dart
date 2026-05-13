import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/data/sale_repository.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late SaleRepository repo;
  late CustomerDao customerDao;
  late SyncDao syncDao;
  const merchantId = 'merchant-1';
  const deviceId = 'device-1';
  late String customerId;

  setUp(() async {
    await setUpTestDatabase();
    final db = AppDatabase.instance;
    customerDao = CustomerDao(db, merchantId: merchantId);
    syncDao = SyncDao(db, merchantId: merchantId, deviceId: deviceId);
    repo = SaleRepository(
      db,
      SaleDao(db, merchantId: merchantId),
      merchantId: merchantId,
      deviceId: deviceId,
    );

    final c = await customerDao.create(
      name: 'Test Customer',
      phone: '840000301',
    );
    customerId = c.id;
  });

  tearDown(tearDownTestDatabase);

  group('createSale', () {
    test('creates sale with correct points (200 MZN → 2 pts)', () async {
      final sale = await repo.createSale(customerId: customerId, amount: 200);
      expect(sale.points, 2);
      expect(sale.amount, 200);
      expect(sale.customerId, customerId);
    });

    test('150 MZN → 1 pt (floor)', () async {
      expect(
        (await repo.createSale(customerId: customerId, amount: 150)).points,
        1,
      );
    });

    test('99 MZN → 0 pts', () async {
      expect(
        (await repo.createSale(customerId: customerId, amount: 99)).points,
        0,
      );
    });

    test('updates customer totalPoints immediately', () async {
      await repo.createSale(customerId: customerId, amount: 200); // 2 pts
      await repo.createSale(customerId: customerId, amount: 300); // 3 pts
      expect((await customerDao.getById(customerId))!.totalPoints, 5);
    });

    test('each sale adds its points to running total', () async {
      await repo.createSale(customerId: customerId, amount: 500); // 5 pts
      await repo.createSale(customerId: customerId, amount: 500); // 5 pts
      await repo.createSale(customerId: customerId, amount: 500); // 5 pts
      expect((await customerDao.getById(customerId))!.totalPoints, 15);
    });

    test('enqueues sync item with operation=create, entityType=sale', () async {
      final sale = await repo.createSale(customerId: customerId, amount: 200);
      final items = await syncDao.getPending();
      expect(items.length, 2);
      final saleItem = items.firstWhere((item) => item.entityType == 'sale');
      expect(saleItem.operation, 'create');
      expect(saleItem.entityId, sale.id);
    });

    test('each sale creates exactly one sync item', () async {
      await repo.createSale(customerId: customerId, amount: 100);
      await repo.createSale(customerId: customerId, amount: 200);
      expect(await syncDao.getPendingCount(), 4);
    });

    test('sale payload contains sale id', () async {
      final sale = await repo.createSale(customerId: customerId, amount: 200);
      final payload = (await syncDao.getPending())
          .firstWhere((item) => item.entityType == 'sale')
          .payload;
      expect(payload, contains(sale.id));
    });

    test(
      'stamps merchant_id and device_id on sale row and queue payload',
      () async {
        final sale = await repo.createSale(customerId: customerId, amount: 200);
        final db = await AppDatabase.instance.database;

        final saleRows = await db.query(
          'sales',
          where: 'id = ?',
          whereArgs: [sale.id],
          limit: 1,
        );
        expect(saleRows.single['merchant_id'], merchantId);
        expect(saleRows.single['device_id'], deviceId);

        final queueRows = await db.query(
          'sync_queue',
          where: 'entity_id = ?',
          whereArgs: [sale.id],
          limit: 1,
        );
        expect(queueRows.single['merchant_id'], merchantId);
        expect(queueRows.single['device_id'], deviceId);
        expect(
          queueRows.single['payload'],
          contains('"merchant_id":"$merchantId"'),
        );
        expect(
          queueRows.single['payload'],
          contains('"device_id":"$deviceId"'),
        );
      },
    );
  });

  group('getTodayStats', () {
    test('counts sales and sums points for today', () async {
      await repo.createSale(customerId: customerId, amount: 200); // 2 pts
      await repo.createSale(customerId: customerId, amount: 500); // 5 pts
      final stats = await repo.getTodayStats();
      expect(stats['count'], 2);
      expect(stats['total_points'], 7);
    });

    test('returns zeros when no sales', () async {
      final stats = await repo.getTodayStats();
      expect(stats['count'], 0);
      expect(stats['total_points'], 0);
    });
  });

  group('getByCustomer', () {
    test('returns all sales for a customer', () async {
      await repo.createSale(customerId: customerId, amount: 100);
      await repo.createSale(customerId: customerId, amount: 200);
      expect((await repo.getByCustomer(customerId)).length, 2);
    });

    test('returns empty list for customer with no sales', () async {
      expect(await repo.getByCustomer('ghost'), isEmpty);
    });
  });
}

