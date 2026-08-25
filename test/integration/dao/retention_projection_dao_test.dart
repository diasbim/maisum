import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/retention/data/retention_dao.dart';
import 'package:maisum/features/retention/domain/retention_metric.dart';

import '../../helpers/test_database.dart';

void main() {
  setUp(setUpTestDatabase);
  tearDown(tearDownTestDatabase);

  test('reads server-owned lifecycle and retention projections', () async {
    final customerDao = CustomerDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );
    final recurring = await customerDao.create(
      name: 'Ana',
      phone: '841234560',
    );
    final inactive = await customerDao.create(
      name: 'Bento',
      phone: '841234561',
    );
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    await db.update(
      'customers',
      <String, Object?>{
        'lifecycle_stage': 'REGULAR',
        'retention_status': 'HEALTHY',
        'total_visits': 7,
        'total_spent': 3500,
        'average_visit_interval_days': 12,
        'last_visit_at':
            now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      },
      where: 'merchant_id = ? AND id = ?',
      whereArgs: <Object?>['merchant-1', recurring.id],
    );
    await db.update(
      'customers',
      <String, Object?>{
        'lifecycle_stage': 'RETURNING',
        'retention_status': 'INACTIVE',
        'total_visits': 3,
        'total_spent': 900,
        'last_visit_at':
            now.subtract(const Duration(days: 50)).millisecondsSinceEpoch,
      },
      where: 'merchant_id = ? AND id = ?',
      whereArgs: <Object?>['merchant-1', inactive.id],
    );

    final dao = RetentionDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );
    final recurringCustomers = await dao.getRecurringCustomers();
    final inactiveCustomers = await dao.getInactiveCustomers();

    expect(
      recurringCustomers.map((customer) => customer.customerId),
      containsAll(<String>[recurring.id, inactive.id]),
    );
    expect(inactiveCustomers, hasLength(1));
    expect(inactiveCustomers.single.customerId, inactive.id);
    expect(inactiveCustomers.single.riskLevel, RetentionRiskLevel.risk);
    expect(inactiveCustomers.single.daysInactive, greaterThanOrEqualTo(49));
  });

  test('keeps retention projections isolated by merchant', () async {
    final customer = await CustomerDao(
      AppDatabase.instance,
      merchantId: 'merchant-2',
    ).create(name: 'Celina', phone: '841234562');
    final db = await AppDatabase.instance.database;
    await db.update(
      'customers',
      <String, Object?>{
        'lifecycle_stage': 'VIP',
        'retention_status': 'AT_RISK',
        'total_visits': 12,
      },
      where: 'merchant_id = ? AND id = ?',
      whereArgs: <Object?>['merchant-2', customer.id],
    );

    final merchantOneDao = RetentionDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );

    expect(await merchantOneDao.getRecurringCustomers(), isEmpty);
    expect(await merchantOneDao.getInactiveCustomers(), isEmpty);
  });
}
