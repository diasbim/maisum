import '../../customers/domain/customer.dart';

enum RetentionReminderDelivery {
  openedWhatsApp,
  offline,
  consentRequired,
  invalidPhone,
  failed,
}

typedef RetentionReminderLauncher = Future<bool> Function(Uri uri);

class RetentionReminderService {
  const RetentionReminderService();

  Future<RetentionReminderDelivery> send({
    required Customer customer,
    required bool isOnline,
    required RetentionReminderLauncher launchWhatsApp,
  }) async {
    if (customer.whatsappConsentStatus != CustomerConsentStatus.granted) {
      return RetentionReminderDelivery.consentRequired;
    }

    final phone = _whatsAppNumber(customer.phone);
    if (phone == null) return RetentionReminderDelivery.invalidPhone;

    final message = _messageFor(customer.name);
    try {
      if (!isOnline) {
        return RetentionReminderDelivery.offline;
      }

      final opened = await launchWhatsApp(
        Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
        ),
      );
      return opened
          ? RetentionReminderDelivery.openedWhatsApp
          : RetentionReminderDelivery.failed;
    } catch (_) {
      return RetentionReminderDelivery.failed;
    }
  }

  String _messageFor(String name) {
    final trimmedName = name.trim();
    final firstName =
        trimmedName.isEmpty ? 'amigo' : trimmedName.split(RegExp(r'\s+')).first;
    return 'Olá, $firstName. Sentimos a sua falta. '
        'Passe por aqui esta semana — será um prazer recebê-lo novamente.';
  }

  String? _whatsAppNumber(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return null;
    return clean.startsWith('258') ? clean : '258$clean';
  }
}
