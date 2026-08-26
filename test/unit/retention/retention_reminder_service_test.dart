import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/retention/services/retention_reminder_service.dart';

Customer _customer({
  CustomerConsentStatus consent = CustomerConsentStatus.granted,
  String phone = '841000001',
}) =>
    Customer(
      id: 'customer-1',
      name: 'Ana Costa',
      phone: phone,
      whatsappConsentStatus: consent,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  const service = RetentionReminderService();

  group('RetentionReminderService', () {
    test('opens WhatsApp with a truthful inactive-customer reminder', () async {
      Uri? launchedUri;

      final outcome = await service.send(
        customer: _customer(),
        isOnline: true,
        launchWhatsApp: (uri) async {
          launchedUri = uri;
          return true;
        },
      );

      expect(outcome, RetentionReminderDelivery.openedWhatsApp);
      expect(launchedUri?.host, 'wa.me');
      expect(launchedUri?.path, '/258841000001');
      expect(launchedUri?.queryParameters['text'], contains('Ana'));
      expect(
        launchedUri?.queryParameters['text'],
        contains('Sentimos a sua falta'),
      );
    });

    test('requires an online retry instead of promising offline delivery',
        () async {
      var launched = false;
      final outcome = await service.send(
        customer: _customer(),
        isOnline: false,
        launchWhatsApp: (_) async {
          launched = true;
          return true;
        },
      );

      expect(outcome, RetentionReminderDelivery.offline);
      expect(launched, isFalse);
    });

    test('reports an error when WhatsApp cannot be opened', () async {
      final outcome = await service.send(
        customer: _customer(),
        isOnline: true,
        launchWhatsApp: (_) async => false,
      );

      expect(outcome, RetentionReminderDelivery.failed);
    });

    test('does not launch without WhatsApp consent', () async {
      var launched = false;

      final outcome = await service.send(
        customer: _customer(consent: CustomerConsentStatus.denied),
        isOnline: true,
        launchWhatsApp: (_) async {
          launched = true;
          return true;
        },
      );

      expect(outcome, RetentionReminderDelivery.consentRequired);
      expect(launched, isFalse);
    });
  });
}
