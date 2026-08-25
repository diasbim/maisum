import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/rewards/data/loyalty_ledger_dao.dart';
import 'package:maisum/features/rewards/domain/loyalty_ledger_entry.dart';

import '../../helpers/test_database.dart';

void main() {
  setUp(setUpTestDatabase);
  tearDown(tearDownTestDatabase);

  test('returns immutable ledger history and latest confirmed balance',
      () async {
    final customerDao = CustomerDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );
    final customer = await customerDao.create(
      name: 'Ana',
      phone: '841234567',
    );
    final db = await AppDatabase.instance.database;
    await db.insert('loyalty_ledger', <String, Object?>{
      'id': 'sale-s1',
      'merchant_id': 'merchant-1',
      'customer_id': customer.id,
      'entry_type': 'EARN',
      'points_delta': 10,
      'source_type': 'SALE',
      'source_id': 's1',
      'policy_version': 1,
      'occurred_at': 1000,
      'created_at': 1000,
      'balance_after': 10,
    });
    await db.insert('loyalty_ledger', <String, Object?>{
      'id': 'redeem-r1',
      'merchant_id': 'merchant-1',
      'customer_id': customer.id,
      'entry_type': 'REDEEM',
      'points_delta': -4,
      'source_type': 'REDEMPTION',
      'source_id': 'r1',
      'policy_version': 1,
      'occurred_at': 2000,
      'created_at': 2000,
      'balance_after': 6,
    });
    final dao = LoyaltyLedgerDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );

    final entries = await dao.getByCustomer(customer.id);

    expect(entries, hasLength(2));
    expect(entries.first.entryType, LoyaltyLedgerEntryType.redeem);
    expect(entries.first.pointsDelta, -4);
    expect(await dao.getConfirmedBalance(customer.id), 6);
  });

  test('separates confirmed balance from pending offline earnings', () async {
    final customerDao = CustomerDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );
    final customer = await customerDao.create(
      name: 'Ana',
      phone: '841234568',
    );
    final db = await AppDatabase.instance.database;
    await db.update(
      'customers',
      <String, Object?>{
        'total_points': 12,
        'confirmed_points': 10,
      },
      where: 'id = ?',
      whereArgs: <Object?>[customer.id],
    );
    await db.insert('sales', <String, Object?>{
      'id': 'sale-pending',
      'merchant_id': 'merchant-1',
      'customer_id': customer.id,
      'amount': 200,
      'points': 2,
      'created_at': 1000,
      'updated_at': 1000,
      'confirmation_status': 'PENDING',
      'synced': 0,
    });
    final dao = LoyaltyLedgerDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );

    final balance = await dao.getCustomerBalance(customer.id);

    expect(balance.confirmedPoints, 10);
    expect(balance.pendingPoints, 2);
    expect(balance.projectedPoints, 12);
    expect(balance.hasConfirmedBaseline, isTrue);
  });
}
