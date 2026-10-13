import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'affiliate_code.dart';
import 'referral_validation.dart';

/// What a till may decide about a referral with no server in reach.
///
/// Everything here is deliberately a mirror of `functions/src/affiliate_engine.ts`
/// rather than a second opinion. The offline path exists so a sale can be
/// completed during an outage, not so the phone can start pricing referrals its
/// own way: the discount a customer is given at the counter has to be the one
/// the server would have given, to the centavo, or the reconciliation that
/// follows is a correction nobody can make to a customer who has already left.
///
/// The one thing this file never does is decide that a referral *succeeded*.
/// A benefit applied from the cache leaves the sale `PENDING_SYNC` and the
/// affiliate unpaid until the server agrees.

/// The separator `affiliate_engine.ts` joins id parts with (ASCII unit
/// separator), chosen there because it cannot occur in any of the parts.
const String _idSeparator = '\u001f';

/// The prefix that marks a code as this device's guess.
///
/// Deliberately not of the form `AFI-{NAME}-{XXXX}`: a provisional code must be
/// impossible to mistake for a real one, because a code that looks real gets
/// shared, and a shared code that the server never minted is refused at some
/// other counter with the affiliate standing there.
const String provisionalCodePrefix = 'LOCAL';

String _digest(List<String> parts) {
  final hash = sha256.convert(utf8.encode(parts.join(_idSeparator)));
  return hash.toString().substring(0, 40);
}

/// The canonical sale id the server will derive for this commit.
///
/// Computed here so the offline sale is written under the id it will keep. The
/// alternative — a local uuid renamed after sync — leaves a window in which the
/// pulled canonical sale and the local one are two rows for one purchase.
String referralSaleDocumentId({
  required String deviceId,
  required String localSaleId,
}) {
  return 'sale_${_digest(<String>[deviceId, localSaleId])}';
}

/// `sale:{deviceId}:{localSaleId}`, the key a replay resolves on.
String referralSaleIdempotencyKey({
  required String deviceId,
  required String localSaleId,
}) {
  return 'sale:$deviceId:$localSaleId';
}

/// `affiliate-attribution:{merchantId}:{customerPhoneHash}`.
///
/// The phone is hashed before it gets here and never stored or logged raw;
/// [referralPhoneHash] is the only way this app derives it, and it matches the
/// backend's `phoneFingerprint` so the two sides agree on one acquisition.
String referralAttributionIdempotencyKey({
  required String merchantId,
  required String customerPhoneHash,
}) {
  return 'affiliate-attribution:$merchantId:$customerPhoneHash';
}

/// `affiliate-reward:{attributionId}:{rewardType}`.
String referralRewardIdempotencyKey({
  required String attributionId,
  required String rewardType,
}) {
  return 'affiliate-reward:$attributionId:$rewardType';
}

/// The one-way derivation both sides use for a phone number.
///
/// Matches `phoneFingerprint` in `affiliate_sale_commit.ts`. An empty phone
/// hashes to the empty string rather than to the hash of nothing, so "no phone"
/// cannot accidentally equal another record that also has no phone.
String referralPhoneHash(String? phoneE164) {
  final phone = phoneE164?.trim() ?? '';
  if (phone.isEmpty) return '';
  return sha256.convert(utf8.encode('affiliate-phone-v1:$phone')).toString();
}

/// A code this device minted for an affiliate it has not been able to register.
///
/// Carries the local id so two provisional affiliates created in the same
/// minute cannot collide, and stays out of the `AFI-` namespace so the global
/// uniqueness index the server owns is never contested by a guess.
String buildProvisionalAffiliateCode({
  required String firstName,
  required String localId,
}) {
  final folded = firstName
      .trim()
      .split(RegExp(r'\s+'))
      .first
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final name = folded.isEmpty
      ? 'AFILIADO'
      : folded.substring(0, folded.length.clamp(0, 8));
  final suffix = _digest(<String>[localId]).substring(0, 6).toUpperCase();
  return '$provisionalCodePrefix-$name-$suffix';
}

/// True for any code this device invented. Never shareable, never sent as a
/// code the server should recognise.
bool isProvisionalAffiliateCode(String? code) {
  final value = code?.trim().toUpperCase() ?? '';
  return value.startsWith('$provisionalCodePrefix-');
}

/// The lifecycle of a locally-decided record, as stored in `sync_status`.
enum AffiliateSyncStatus {
  pending('PENDING'),
  synced('SYNCED'),
  rejected('REJECTED'),
  failed('FAILED');

  const AffiliateSyncStatus(this.storageValue);

  final String storageValue;

  static AffiliateSyncStatus? fromStorage(Object? value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toUpperCase();
    for (final status in AffiliateSyncStatus.values) {
      if (status.storageValue == normalized) return status;
    }
    return null;
  }
}

/// What a code is worth on this sale, computed the server's way.
class OfflineReferralBenefit {
  const OfflineReferralBenefit({
    required this.type,
    required this.value,
    required this.discountAmount,
    required this.pointsAwarded,
    required this.netAmount,
    required this.displayText,
  });

  final ReferralBenefitType type;

  /// What the code declares: a percentage, an amount or a points count.
  final double value;

  /// Money taken off this sale. Always 0 for a POINTS benefit.
  final double discountAmount;

  /// Extra loyalty points for the customer. Always 0 for a money benefit.
  final int pointsAwarded;

  /// What the customer is actually charged.
  final double netAmount;

  final String displayText;

  /// What the sale row stores in `referral_benefit_amount`: the points for a
  /// POINTS benefit, the discount for a monetary one, which is the same column
  /// the server writes.
  double get storedBenefitAmount => type == ReferralBenefitType.points
      ? pointsAwarded.toDouble()
      : discountAmount;
}

/// Mirrors `calculateBenefit` in `affiliate_engine.ts`, including its rounding.
///
/// Percentages are worked in centavos and floored, so the discount can never
/// come out a centavo larger than the percentage allows; a fixed amount is
/// rounded to centavos and then capped at the bill, because a discount larger
/// than the sale would be money owed to the customer, which this product does
/// not do.
OfflineReferralBenefit calculateOfflineReferralBenefit({
  required ReferralBenefitType benefitType,
  required double benefitValue,
  required double grossAmount,
}) {
  final gross = grossAmount < 0 ? 0.0 : grossAmount;

  if (benefitType == ReferralBenefitType.points) {
    final points = benefitValue.floor();
    return OfflineReferralBenefit(
      type: ReferralBenefitType.points,
      value: points.toDouble(),
      discountAmount: 0,
      pointsAwarded: points,
      netAmount: gross,
      displayText: '${_formatPoints(points)} pontos extra',
    );
  }

  final grossCents = (gross * 100).round();
  final rawCents = benefitType == ReferralBenefitType.percentage
      ? (grossCents * benefitValue / 100).floor()
      : (benefitValue * 100).round();
  final discountCents = rawCents < 0
      ? 0
      : rawCents > grossCents
          ? grossCents
          : rawCents;
  final discountAmount = discountCents / 100;

  return OfflineReferralBenefit(
    type: benefitType,
    value: benefitValue,
    discountAmount: discountAmount,
    pointsAwarded: 0,
    netAmount: (grossCents - discountCents) / 100,
    displayText: benefitType == ReferralBenefitType.percentage
        ? '${_formatNumber(benefitValue)}% de desconto '
            '(${_formatMoney(discountAmount)})'
        : '${_formatMoney(discountAmount)} de desconto',
  );
}

String _formatMoney(double value) {
  final whole = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '$whole MT';
}

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

String _formatPoints(int value) => value.toString();

/// The checks a till can make on its own, in the server's order.
///
/// The three it cannot make are the three that need the server's whole picture:
/// whether this customer is new to the business, whether they already belong to
/// another affiliate, and whether the affiliate is the customer. The till knows
/// only what it has locally, so [customerIsNew] is passed in from the local
/// customer record and the rest is left to the reconciliation — which is why a
/// benefit granted here leaves the sale pending rather than attributed.
ReferralValidationErrorCode? validateCachedReferralCode({
  required AffiliateCodeLookupCache cache,
  required String merchantId,
  required DateTime now,
  required bool customerIsNew,
  required double? saleAmount,
  String? affiliateStatus,
  String? linkStatus,
  String? customerPhoneHash,
  String? affiliatePhoneHash,
}) {
  if (cache.merchantId != merchantId) {
    return ReferralValidationErrorCode.codeNotFound;
  }
  if (cache.status != AffiliateCodeStatus.active) {
    return ReferralValidationErrorCode.codeDisabled;
  }
  final startsAt = cache.startsAt;
  if (startsAt != null && now.isBefore(startsAt)) {
    return ReferralValidationErrorCode.codeNotStarted;
  }
  final expiresAt = cache.expiresAt;
  if (expiresAt != null && !now.isBefore(expiresAt)) {
    return ReferralValidationErrorCode.codeExpired;
  }
  final usageLimit = cache.usageLimit;
  if (usageLimit != null && cache.usageCount >= usageLimit) {
    return ReferralValidationErrorCode.codeUsageLimitReached;
  }
  final affiliateActive =
      (affiliateStatus ?? 'ACTIVE').toUpperCase() == 'ACTIVE';
  final linkActive = (linkStatus ?? 'ACTIVE').toUpperCase() == 'ACTIVE';
  if (!affiliateActive || !linkActive) {
    return ReferralValidationErrorCode.affiliateInactive;
  }
  if (affiliatePhoneHash != null &&
      affiliatePhoneHash.isNotEmpty &&
      affiliatePhoneHash == customerPhoneHash) {
    return ReferralValidationErrorCode.selfReferralNotAllowed;
  }
  if (cache.firstVisitOnly && !customerIsNew) {
    return ReferralValidationErrorCode.customerNotEligible;
  }
  if (!_isBenefitValid(cache.benefitType, cache.benefitValue, saleAmount)) {
    return ReferralValidationErrorCode.benefitInvalid;
  }
  return null;
}

bool _isBenefitValid(
  ReferralBenefitType type,
  double value,
  double? saleAmount,
) {
  if (!value.isFinite || value <= 0) return false;
  switch (type) {
    case ReferralBenefitType.percentage:
      return value >= 1 && value <= 50;
    case ReferralBenefitType.fixedAmount:
      if (saleAmount == null) return true;
      return saleAmount > 0 && value <= saleAmount;
    case ReferralBenefitType.points:
      return value == value.roundToDouble();
  }
}

/// What the till decided about a code before writing the sale.
///
/// [benefit] is null whenever nothing may be applied — an unknown code, or a
/// cached one that failed a local check — and the sale is still written with
/// the typed code kept as an intention for the server to judge.
class OfflineReferralDecision {
  const OfflineReferralDecision({
    required this.normalizedCode,
    this.cache,
    this.benefit,
    this.errorCode,
  });

  /// The code exactly as the server indexes it.
  final String normalizedCode;

  /// The cache entry the code resolved to, when there was one.
  final AffiliateCodeLookupCache? cache;

  /// The benefit to apply now. Null means the sale is charged in full.
  final OfflineReferralBenefit? benefit;

  /// Why nothing was applied, when the code was cached but unusable.
  final ReferralValidationErrorCode? errorCode;

  bool get isKnownCode => cache != null;

  bool get appliesBenefit => benefit != null;
}
