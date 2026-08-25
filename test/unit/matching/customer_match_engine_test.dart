import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/matching/customer_match_engine.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late CustomerDao dao;
  late CustomerMatchEngine engine;

  setUp(() async {
    await setUpTestDatabase();
    dao = CustomerDao.unscoped(AppDatabase.instance);
    engine = CustomerMatchEngine(dao);
  });

  tearDown(tearDownTestDatabase);

  test('matches by phone when available', () async {
    final customer = await dao.create(name: 'Carlos', phone: '841234567');
    final match = await engine.match(phone: '841234567');
    expect(match.customer?.id, customer.id);
    expect(match.reason, 'phone');
  });

  test('does not infer identity from the most recent customer', () async {
    final recent = await dao.create(name: 'Maria', phone: '841111111');
    final match = await engine.match(phone: '000000000');
    expect(match.customer, isNull);
    expect(match.reason, 'none');
    expect((await engine.suggestMostRecent())?.id, recent.id);
  });
}
