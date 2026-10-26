import '../../customers/domain/customer.dart';
import '../domain/engage_models.dart';

enum SurveyInviteDelivery {
  openedWhatsApp,
  offline,
  consentRequired,
  invalidPhone,
  noLink,
  failed,
}

typedef SurveyInviteLauncher = Future<bool> Function(Uri uri);

/// Sending a survey to one customer over WhatsApp.
///
/// Deliberately the same shape as [RetentionReminderService]: consent is
/// checked before anything is composed, the number is normalised the same way,
/// and the launcher is injected so the message can be asserted without opening
/// an app. A survey invitation is marketing contact like any other — a customer
/// who never agreed to be messaged does not get one because a survey is the
/// thing being sent.
class SurveyInviteService {
  const SurveyInviteService();

  Future<SurveyInviteDelivery> send({
    required Customer customer,
    required EngageSurvey survey,
    required SurveyLink link,
    required bool isOnline,
    required SurveyInviteLauncher launchWhatsApp,
  }) async {
    if (customer.whatsappConsentStatus != CustomerConsentStatus.granted) {
      return SurveyInviteDelivery.consentRequired;
    }
    if (!link.isShareable) return SurveyInviteDelivery.noLink;

    final phone = whatsAppNumber(customer.phone);
    if (phone == null) return SurveyInviteDelivery.invalidPhone;
    if (!isOnline) return SurveyInviteDelivery.offline;

    try {
      final opened = await launchWhatsApp(
        Uri.parse(
          'https://wa.me/$phone?text='
          '${Uri.encodeComponent(messageFor(customer.name, survey, link))}',
        ),
      );
      return opened
          ? SurveyInviteDelivery.openedWhatsApp
          : SurveyInviteDelivery.failed;
    } catch (_) {
      return SurveyInviteDelivery.failed;
    }
  }

  /// Says who is asking, what for, and how long it takes. A bare link from an
  /// unknown number is the one thing nobody taps.
  String messageFor(String name, EngageSurvey survey, SurveyLink link) {
    final trimmed = name.trim();
    final firstName =
        trimmed.isEmpty ? 'amigo' : trimmed.split(RegExp(r'\s+')).first;
    return 'Olá, $firstName. Queremos melhorar e a sua opinião conta. '
        '"${survey.title}" — leva menos de um minuto: ${link.url}';
  }

  String? whatsAppNumber(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return null;
    return clean.startsWith('258') ? clean : '258$clean';
  }
}
