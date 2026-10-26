import '../domain/affiliate_code.dart';
import '../domain/merchant_affiliate_dtos.dart';

/// The message an affiliate is handed to forward, and the link that opens it.
///
/// Nothing here sends anything. It composes the text and hands back a `wa.me`
/// URL with the message already encoded, so the owner sees it in WhatsApp and
/// chooses who gets it — an auto-send would be a message the business did not
/// read, to a contact it did not pick.
class AffiliateShareDraft {
  const AffiliateShareDraft({required this.message, required this.uri});

  final String message;
  final Uri uri;
}

/// A short invitation in the Portuguese the till already speaks.
///
/// The benefit is spelled out because that is the part that makes someone use
/// the code; the code itself is uppercased because that is how it is printed
/// everywhere else and a lowercase copy invites a failed entry.
String buildAffiliateShareMessage({
  required String code,
  required String businessName,
  ReferralBenefitType? benefitType,
  double? benefitValue,
}) {
  final trimmedBusiness = businessName.trim();
  final business =
      trimmedBusiness.isEmpty ? 'o nosso negócio' : trimmedBusiness;
  final benefit = describeReferralBenefit(benefitType, benefitValue);
  final lines = <String>[
    'Olá! Use o código $code em $business.',
    if (benefit != null) 'Na primeira compra recebe $benefit.',
    'Basta dizer o código no balcão.',
  ];
  return lines.join('\n');
}

/// The benefit in words, or null when there is nothing trustworthy to promise.
String? describeReferralBenefit(ReferralBenefitType? type, double? value) {
  if (type == null || value == null || value <= 0) return null;
  return switch (type) {
    ReferralBenefitType.percentage =>
      '${formatBenefitNumber(value)}% de desconto',
    ReferralBenefitType.fixedAmount =>
      '${formatBenefitNumber(value)} MT de desconto',
    ReferralBenefitType.points => '${formatBenefitNumber(value)} pontos',
  };
}

/// Drops the decimal part when it carries no information: "50" reads as money,
/// "50.0" reads as a bug.
String formatBenefitNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Builds the draft for a confirmed code.
///
/// Returns null when the affiliate has no code that can be used yet, which is
/// the same condition that greys out the share button: a code the server has
/// not confirmed would be shared, typed and refused.
AffiliateShareDraft? buildAffiliateShareDraft({
  required MerchantAffiliate affiliate,
  required String businessName,
}) {
  final code = affiliate.code;
  if (code == null || !affiliate.canShareCode) return null;
  final message = buildAffiliateShareMessage(
    code: code.code.toUpperCase(),
    businessName: businessName,
    benefitType: code.benefitType,
    benefitValue: code.benefitValue,
  );
  return AffiliateShareDraft(
    message: message,
    uri: buildWhatsAppShareUri(message: message, phone: affiliate.phone),
  );
}

/// A `wa.me` link with the text percent-encoded.
///
/// The phone is optional: without one WhatsApp opens the contact picker, which
/// is the right behaviour when the API withheld the affiliate's number.
Uri buildWhatsAppShareUri({required String message, String? phone}) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  final encoded = Uri.encodeComponent(message);
  if (digits.isEmpty) {
    return Uri.parse('https://wa.me/?text=$encoded');
  }
  final number = digits.startsWith('258') ? digits : '258$digits';
  return Uri.parse('https://wa.me/$number?text=$encoded');
}
