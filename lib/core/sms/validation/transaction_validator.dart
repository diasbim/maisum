import '../domain/sms_transaction.dart';

class TransactionValidator {
  const TransactionValidator();

  bool isValid(SmsTransaction transaction) {
    if (transaction.amount <= 0) return false;
    if (transaction.provider.trim().isEmpty) return false;
    return true;
  }
}
