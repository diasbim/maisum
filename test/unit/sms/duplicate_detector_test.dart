import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/sms/data/sms_transaction_dao.dart';
import 'package:maisum/core/sms/domain/sms_transaction.dart';
import 'package:maisum/core/sms/validation/duplicate_detector.dart';

import '../../helpers/test_database.dart';

void main() {
  late SmsTransactionDao dao;
  late DuplicateDetector detector;

  setUp(() async {
    await setUpTestDatabase();
    dao = SmsTransactionDao(AppDatabase.instance);
    detector = DuplicateDetector(dao);
  });

  tearDown(tearDownTestDatabase);

  test('detects duplicates by hash', () async {
    final tx = SmsTransaction(
      provider: 'mpesa',
      amount: 500,
      phone: '841234567',
      transactionId: 'ABC123',
      receivedAt: DateTime(2026, 5, 13, 10, 0),
      rawMessage: 'Recebeu 500 MT',
    );

    expect(await detector.isDuplicate(tx), false);
    await detector.register(tx);
    expect(await detector.isDuplicate(tx), true);
  });
}
