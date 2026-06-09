import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/utils/moz_phone_input_formatter.dart';
import 'package:maisum/core/utils/moz_phone_validator.dart';

void main() {
  group('MozPhoneValidator', () {
    test('accepts valid 9-digit local numbers with prefixes 82-87', () {
      expect(MozPhoneValidator.isValidLocalPhone('821234567'), isTrue);
      expect(MozPhoneValidator.isValidLocalPhone('831234567'), isTrue);
      expect(MozPhoneValidator.isValidLocalPhone('841234567'), isTrue);
      expect(MozPhoneValidator.isValidLocalPhone('851234567'), isTrue);
      expect(MozPhoneValidator.isValidLocalPhone('861234567'), isTrue);
      expect(MozPhoneValidator.isValidLocalPhone('871234567'), isTrue);
    });

    test('rejects invalid prefixes and invalid lengths', () {
      expect(MozPhoneValidator.isValidLocalPhone('811234567'), isFalse);
      expect(MozPhoneValidator.isValidLocalPhone('881234567'), isFalse);
      expect(MozPhoneValidator.isValidLocalPhone('84123456'), isFalse);
      expect(MozPhoneValidator.isValidLocalPhone('8412345678'), isFalse);
    });

    test('validationMessage reports invalid and empty values', () {
      expect(MozPhoneValidator.validationMessage(''), isNotNull);
      expect(
        MozPhoneValidator.validationMessage('841234567'),
        isNull,
      );
      expect(
        MozPhoneValidator.validationMessage('811234567'),
        isNotNull,
      );
    });
  });

  group('MozPhoneFormatter', () {
    final formatter = MozPhoneFormatter();

    TextEditingValue format(String value) {
      return formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
      );
    }

    test('formats valid input as XX XXX XXXX', () {
      final formatted = format('841112345');
      expect(formatted.text, '84 111 2345');
    });

    test('strips non-digits and limits to 9 digits', () {
      final formatted = format('84 111-2345123');
      expect(formatted.text, '84 111 2345');
    });
  });
}
