import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/constants/app_strings.dart';

void main() {
  group('WhatsApp feedback strings', () {
    test('queued copy matches acceptance criteria', () {
      expect(AppStrings.whatsappQueued, 'Será enviado quando online ⏳');
    });

    test('sent copy matches acceptance criteria', () {
      expect(AppStrings.whatsappSent, 'WhatsApp enviado ✅');
    });
  });
}
