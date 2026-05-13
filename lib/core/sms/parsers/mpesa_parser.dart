import '../domain/sms_transaction.dart';
import 'sms_parser.dart';

class MpesaParser implements SmsParser {
  static final _amountRegex =
      RegExp(r'(\d+(?:[.,]\d+)?)\s?MT', caseSensitive: false);
  static final _phoneRegex =
      RegExp(r'(?:de|para)\s*(\d{7,12})', caseSensitive: false);
  static final _txnRegex = RegExp(
      r'(?:Txn\s*ID|ID|Transac[aã]o)[:\s]*([A-Z0-9-]+)',
      caseSensitive: false);
  static final _referenceRegex = RegExp(
      r'(?:Ref(?:erencia|erência)?|Referencia|Referência|Ref)[:\s]*([A-Z0-9-]+)',
      caseSensitive: false);

  @override
  String get provider => 'mpesa';

  @override
  bool canParse(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('m-pesa') || normalized.contains('mpesa');
  }

  @override
  SmsTransaction? parse({
    required String message,
    String? address,
    DateTime? receivedAt,
  }) {
    if (!canParse(message)) {
      return null;
    }

    final amountMatch = _amountRegex.firstMatch(message);
    final amountRaw = amountMatch?.group(1)?.replaceAll(',', '.');
    final amount = double.tryParse(amountRaw ?? '');
    if (amount == null) return null;

    final phoneMatch = _phoneRegex.firstMatch(message);
    final txnMatch = _txnRegex.firstMatch(message);
    final referenceMatch = _referenceRegex.firstMatch(message);

    return SmsTransaction(
      provider: provider,
      amount: amount,
      phone: phoneMatch?.group(1),
      transactionId: txnMatch?.group(1),
      reference: referenceMatch?.group(1),
      receivedAt: receivedAt,
      rawMessage: message,
    );
  }
}
