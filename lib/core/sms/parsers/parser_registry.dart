import '../domain/sms_transaction.dart';
import 'emola_parser.dart';
import 'mpesa_parser.dart';
import 'sms_parser.dart';

class ParserRegistry {
  ParserRegistry({List<SmsParser>? parsers})
      : _parsers = parsers ?? [MpesaParser(), EmolaParser()];

  final List<SmsParser> _parsers;

  SmsTransaction? parse({
    required String message,
    String? address,
    DateTime? receivedAt,
  }) {
    for (final parser in _parsers) {
      if (!parser.canParse(message)) {
        continue;
      }
      final transaction = parser.parse(
        message: message,
        address: address,
        receivedAt: receivedAt,
      );
      if (transaction != null) {
        return transaction;
      }
    }
    return null;
  }
}
