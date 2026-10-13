import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/services/survey_invite_service.dart';

/// A survey invitation is marketing contact like any other. These tests pin the
/// order the checks happen in — consent first, before a message is composed or
/// an app is opened — and what the customer actually receives.
void main() {
  const service = SurveyInviteService();

  final survey = EngageSurvey(
    id: 'survey-1',
    title: 'Porque não voltou?',
    isActive: true,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
    questions: const [],
  );

  final link = SurveyLink(
    token: 'sl1.abc.def',
    url: 'https://portal.exemplo/q/sl1.abc.def',
    expiresAt: DateTime(2026, 10, 15),
    surveyTitle: 'Porque não voltou?',
  );

  Customer customer({
    CustomerConsentStatus consent = CustomerConsentStatus.granted,
    String phone = '840000001',
    String name = 'Amélia Cossa',
  }) =>
      Customer(
        id: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        name: name,
        phone: phone,
        whatsappConsentStatus: consent,
        createdAt: DateTime(2026, 1, 1),
      );

  group('who gets a message', () {
    test('a customer who never agreed to WhatsApp is not messaged', () async {
      var launched = false;
      final outcome = await service.send(
        customer: customer(consent: CustomerConsentStatus.denied),
        survey: survey,
        link: link,
        isOnline: true,
        launchWhatsApp: (_) async {
          launched = true;
          return true;
        },
      );

      expect(outcome, SurveyInviteDelivery.consentRequired);
      expect(
        launched,
        isFalse,
        reason: 'consent is checked before anything is composed or opened',
      );
    });

    test('unknown consent is not consent', () async {
      expect(
        await service.send(
          customer: customer(consent: CustomerConsentStatus.unknown),
          survey: survey,
          link: link,
          isOnline: true,
          launchWhatsApp: (_) async => true,
        ),
        SurveyInviteDelivery.consentRequired,
      );
    });

    test('a link with nowhere to point is refused before the phone check',
        () async {
      // The server has no public base URL configured. Sending the customer a
      // message with "null" in it would be worse than not sending one.
      final outcome = await service.send(
        customer: customer(phone: ''),
        survey: survey,
        link: SurveyLink(
          token: 'sl1.abc.def',
          url: null,
          expiresAt: DateTime(2026, 10, 15),
        ),
        isOnline: true,
        launchWhatsApp: (_) async => true,
      );

      expect(outcome, SurveyInviteDelivery.noLink);
    });

    test('an unusable number is reported, not silently skipped', () async {
      expect(
        await service.send(
          customer: customer(phone: 'sem número'),
          survey: survey,
          link: link,
          isOnline: true,
          launchWhatsApp: (_) async => true,
        ),
        SurveyInviteDelivery.invalidPhone,
      );
    });

    test('offline, nothing is opened and the caller is told', () async {
      var launched = false;
      final outcome = await service.send(
        customer: customer(),
        survey: survey,
        link: link,
        isOnline: false,
        launchWhatsApp: (_) async {
          launched = true;
          return true;
        },
      );

      expect(outcome, SurveyInviteDelivery.offline);
      expect(launched, isFalse);
    });

    test('a launcher that throws is a failure, not a crash', () async {
      expect(
        await service.send(
          customer: customer(),
          survey: survey,
          link: link,
          isOnline: true,
          launchWhatsApp: (_) async => throw StateError('no WhatsApp'),
        ),
        SurveyInviteDelivery.failed,
      );
    });
  });

  group('what the customer receives', () {
    test('the message names the shop question and carries the link', () async {
      late Uri opened;
      final outcome = await service.send(
        customer: customer(),
        survey: survey,
        link: link,
        isOnline: true,
        launchWhatsApp: (uri) async {
          opened = uri;
          return true;
        },
      );

      expect(outcome, SurveyInviteDelivery.openedWhatsApp);
      final text = Uri.decodeComponent(opened.query.split('text=').last);
      expect(text, contains('Amélia'));
      expect(text, contains('Porque não voltou?'));
      expect(text, contains(link.url));
      expect(
        text,
        contains('menos de um minuto'),
        reason: 'a link with no idea of the cost is the one nobody taps',
      );
    });

    test('only the first name is used', () {
      expect(
        service.messageFor('Amélia Cossa da Conceição', survey, link),
        startsWith('Olá, Amélia.'),
      );
    });

    test('a customer with no name still gets a greeting', () {
      expect(service.messageFor('   ', survey, link), startsWith('Olá, amigo.'));
    });
  });

  group('the number', () {
    test('a local number gains the country code', () {
      expect(service.whatsAppNumber('84 000 0001'), '258840000001');
    });

    test('a number that already has it is left alone', () {
      expect(service.whatsAppNumber('+258 84 000 0001'), '258840000001');
    });

    test('a number with no digits at all is refused', () {
      expect(service.whatsAppNumber('--'), isNull);
    });
  });
}
