import '../domain/referral_validation.dart';
import 'affiliate_share_message.dart';

/// The words the counter uses for a referral, in one place.
///
/// Every string here is short on purpose. The cashier reads them out loud with
/// a customer waiting, so a refusal has to land in one line and never has to
/// name a code id, an affiliate id or an HTTP status.

/// Why a code cannot be used, in a sentence.
///
/// The server's own message wins when it sent one: it is already Portuguese and
/// already specific. The table below is the fallback for a transport that lost
/// it, and for the one case the server cannot phrase — an unrecognised refusal.
String referralRejectionMessage(ReferralValidationResult result) {
  final serverMessage = result.statusText?.trim();
  if (serverMessage != null && serverMessage.isNotEmpty) {
    return serverMessage;
  }
  return referralErrorMessage(result.errorCode);
}

String referralErrorMessage(ReferralValidationErrorCode? code) {
  return switch (code) {
    ReferralValidationErrorCode.codeNotFound => 'Código não encontrado.',
    ReferralValidationErrorCode.codeDisabled => 'Código desativado.',
    ReferralValidationErrorCode.codeNotStarted => 'Código ainda não começou.',
    ReferralValidationErrorCode.codeExpired => 'Código expirado.',
    ReferralValidationErrorCode.codeUsageLimitReached =>
      'Código já atingiu o limite de usos.',
    ReferralValidationErrorCode.affiliateInactive => 'Afiliado inativo.',
    ReferralValidationErrorCode.selfReferralNotAllowed =>
      'O afiliado não pode usar o próprio código.',
    ReferralValidationErrorCode.customerNotEligible =>
      'Este cliente não pode usar o código.',
    ReferralValidationErrorCode.customerAlreadyReferred =>
      'Este cliente já foi indicado.',
    ReferralValidationErrorCode.benefitInvalid => 'Benefício inválido.',
    null => 'Não foi possível usar este código.',
  };
}

/// What the customer gets, phrased for the counter.
String referralBenefitText(ReferralValidationResult result) {
  final benefit = result.benefit;
  final serverText = benefit?.displayText?.trim() ?? result.statusText?.trim();
  if (serverText != null && serverText.isNotEmpty) return serverText;
  return describeReferralBenefit(benefit?.benefitType, benefit?.benefitValue) ??
      'benefício aplicado na venda';
}

/// Normalises what the cashier typed into what the server indexes.
///
/// Trim and uppercase, and nothing else: the server normalises exactly this
/// way, and a till that also stripped the hyphens would turn `AFI-ANA-7K2P`
/// into a code that does not exist.
String normalizeReferralCodeInput(String raw) {
  return raw.trim().toUpperCase();
}

/// The length the commit endpoint accepts. Below it the request is refused for
/// its shape rather than for the code, which is not a useful thing to tell a
/// cashier, so the button stays off instead.
bool isReferralCodeLongEnough(String normalizedCode) {
  return normalizedCode.length >= 3 && normalizedCode.length <= 40;
}
