import '../domain/sms_transaction.dart';

abstract class SmsParser {
  String get provider;

  bool canParse(String message);

  SmsTransaction? parse({
    required String message,
    String? address,
    DateTime? receivedAt,
  });
}
