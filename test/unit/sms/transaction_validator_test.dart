import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/sms/domain/sms_transaction.dart';
import 'package:maisum/core/sms/validation/transaction_validator.dart';

void main() {
  const validator = TransactionValidator();

  SmsTransaction _baseTransaction({
    String provider = 'mpesa',
    double amount = 500,
  }) {
    return SmsTransaction(
      provider: provider,
      amount: amount,
      phone: '841234567',
      transactionId: 'ABC123',
      receivedAt: DateTime(2026, 5, 13, 10, 0),
      rawMessage: 'Recebeu 500 MT de 841234567',
    );
  }

  test('rejects zero or negative amounts', () {
    expect(validator.isValid(_baseTransaction(amount: 0)), false);
    expect(validator.isValid(_baseTransaction(amount: -10)), false);
  });

  test('rejects empty provider', () {
    expect(validator.isValid(_baseTransaction(provider: '  ')), false);
  });

  test('accepts valid transactions', () {
    expect(validator.isValid(_baseTransaction()), true);
  });
}
