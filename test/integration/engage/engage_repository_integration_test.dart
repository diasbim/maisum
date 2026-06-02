import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/engage/data/engage_dao.dart';
import 'package:maisum/features/engage/data/engage_repository.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late EngageRepository repository;
  late SyncDao syncDao;

  setUp(() async {
    await setUpTestDatabase();
    syncDao = SyncDao(AppDatabase.instance, merchantId: 'merchant-1');
    repository = EngageRepository(
      EngageDao(AppDatabase.instance, merchantId: 'merchant-1'),
      syncDao,
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test(
    'recovery queue keeps ordering: value, then risk priority, then points',
    () async {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now();

      Future<void> seedCustomer({
        required String id,
        required String name,
        required int points,
        required int daysAgo,
        required double totalSpent,
      }) async {
        final createdAt = now
            .subtract(const Duration(days: 120))
            .millisecondsSinceEpoch;
        final saleAt = now
            .subtract(Duration(days: daysAgo))
            .millisecondsSinceEpoch;

        await db.insert('customers', {
          'id': id,
          'merchant_id': 'merchant-1',
          'name': name,
          'phone': '84$id',
          'total_points': points,
          'created_at': createdAt,
          'updated_at': createdAt,
          'synced': 1,
        });

        await db.insert('sales', {
          'id': 'sale_$id',
          'merchant_id': 'merchant-1',
          'customer_id': id,
          'amount': totalSpent,
          'points': 10,
          'created_at': saleAt,
          'synced': 1,
        });

        await db.insert('retention_metrics', {
          'id': 'metric_$id',
          'merchant_id': 'merchant-1',
          'customer_id': id,
          'last_visit_at': saleAt,
          'days_inactive': daysAgo,
          'risk_level': 'risk',
          'total_visits': 1,
          'average_visit_interval': 0,
          'total_spent': totalSpent,
          'is_recurring': 0,
          'recovered': 0,
          'updated_at': saleAt,
          'synced': 1,
        });
      }

      await seedCustomer(
        id: 'a',
        name: 'Cliente A',
        points: 100,
        daysAgo: 20,
        totalSpent: 5000,
      );
      await seedCustomer(
        id: 'b',
        name: 'Cliente B',
        points: 9999,
        daysAgo: 70,
        totalSpent: 2000,
      );
      await seedCustomer(
        id: 'c',
        name: 'Cliente C',
        points: 100,
        daysAgo: 70,
        totalSpent: 1000,
      );
      await seedCustomer(
        id: 'd',
        name: 'Cliente D',
        points: 7000,
        daysAgo: 20,
        totalSpent: 1000,
      );

      await repository.recalculateRiskScores();
      final queue = await repository.getRecoveryQueue(limit: 10);

      expect(queue.map((item) => item.customerId).toList(), [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(queue.first.riskLevel, EngageRiskLevel.yellow);
      expect(queue[1].riskLevel, EngageRiskLevel.red);
    },
  );

  test(
    'task lifecycle creates and completes task with sync queue entries',
    () async {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('customers', {
        'id': 'cust-1',
        'merchant_id': 'merchant-1',
        'name': 'Cliente 1',
        'phone': '841111111',
        'total_points': 500,
        'created_at': now,
        'updated_at': now,
        'synced': 1,
      });

      final created = await repository.createRecoveryTask(
        customerId: 'cust-1',
        priority: RecoveryTaskPriority.high,
        notes: 'Ligar ainda hoje',
      );

      expect(created.status, RecoveryTaskStatus.open);

      final completed = await repository.completeRecoveryTask(created.id);

      expect(completed, isNotNull);
      expect(completed!.status, RecoveryTaskStatus.completed);

      final pending = await syncDao.getAllItems();
      final recoveryItems = pending
          .where((item) => item.entityType == 'recovery_task')
          .toList();
      expect(recoveryItems.length, 2);
      expect(recoveryItems.any((item) => item.operation == 'create'), isTrue);
      expect(recoveryItems.any((item) => item.operation == 'update'), isTrue);
    },
  );
}
