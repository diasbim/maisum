import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/utils/nfc_card_uid_utils.dart';

void main() {
  group('NfcCardUidUtils.normalize', () {
    test('strips separators and upper-cases the uid', () {
      expect(NfcCardUidUtils.normalize('04:a2:2c:9b'), '04A22C9B');
      expect(
        NfcCardUidUtils.normalize('04-a2-2c-9b-7e-11-80'),
        '04A22C9B7E1180',
      );
      expect(NfcCardUidUtils.normalize(' 04a22c9b '), '04A22C9B');
    });

    test('accepts 4, 7 and 10 byte uids', () {
      expect(NfcCardUidUtils.isValid('04A22C9B'), isTrue);
      expect(NfcCardUidUtils.isValid('04A22C9B7E1180'), isTrue);
      expect(NfcCardUidUtils.isValid('04A22C9B7E11803344'.padRight(20, '0')),
          isTrue);
    });

    test('rejects invalid uids', () {
      expect(() => NfcCardUidUtils.normalize(''), throwsFormatException);
      expect(
        () => NfcCardUidUtils.normalize('ZZZZZZZZ'),
        throwsFormatException,
      );
      expect(() => NfcCardUidUtils.normalize('04A22C'), throwsFormatException);
      expect(NfcCardUidUtils.tryNormalize('not-hex'), isNull);
    });
  });

  group('NfcCardUidUtils.fromBytes', () {
    test('converts raw tag bytes into the normalized hex uid', () {
      expect(
        NfcCardUidUtils.fromBytes([0x04, 0xA2, 0x2C, 0x9B]),
        '04A22C9B',
      );
    });
  });

  group('NfcCardUidUtils.maskedLast4', () {
    test('shows only the last 4 characters', () {
      expect(NfcCardUidUtils.maskedLast4('04A22C9B'), '••••2C9B');
    });
  });
}
