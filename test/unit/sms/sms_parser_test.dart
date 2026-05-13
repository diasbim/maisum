import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/sms/parsers/parser_registry.dart';

void main() {
  group('SMS Parser Registry', () {
    final registry = ParserRegistry();

    test('parses M-Pesa message', () {
      const message = 'Recebeu 500 MT de 841234567. Txn ID: ABC123 Ref: REF777';
      final tx = registry.parse(message: message, receivedAt: DateTime.now());
      expect(tx, isNotNull);
      expect(tx!.amount, 500);
      expect(tx.phone, '841234567');
      expect(tx.transactionId, 'ABC123');
      expect(tx.reference, 'REF777');
      expect(tx.provider, 'mpesa');
    });

    test('parses eMola message', () {
      const message = 'Pagamento eMola: 250 MT de 841112223. ID XYZ999';
      final tx = registry.parse(message: message, receivedAt: DateTime.now());
      expect(tx, isNotNull);
      expect(tx!.amount, 250);
      expect(tx.provider, 'emola');
    });
  });
}
