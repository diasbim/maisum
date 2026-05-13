import '../../../core/sms/domain/sms_transaction.dart';
import '../../customers/domain/customer.dart';

class SuggestedSale {
  const SuggestedSale({
    required this.transaction,
    required this.points,
    this.customer,
    required this.matchReason,
  });

  final SmsTransaction transaction;
  final int points;
  final Customer? customer;
  final String matchReason;
}
