import '../../sales/domain/sale.dart';
import 'affiliate_code.dart';
import 'affiliate_serialization.dart';
import 'referral_validation.dart';

/// What the server answers when a till commits a referred sale.
///
/// The commit is authoritative: the sale, the discount, the loyalty points, the
/// acquisition and the affiliate's reward are all decided inside one Firestore
/// transaction and come back already written. Nothing in this file computes a
/// value — it reads the canonical answer so the app can project it locally.
///
/// A refused code is an outcome, not a failure. The request was well formed and
/// the answer is "not this sale", with the reason the cashier needs, so the
/// caller falls back to confirming the sale without a code instead of showing
/// an error and losing the sale.
enum ReferralSaleCommitOutcome {
  committed('committed'),
  replayed('replayed'),
  rejected('rejected');

  const ReferralSaleCommitOutcome(this.storageValue);

  final String storageValue;

  static ReferralSaleCommitOutcome fromStorage(Object value) {
    final normalized = value.toString().trim().toLowerCase();
    for (final outcome in ReferralSaleCommitOutcome.values) {
      if (outcome.storageValue == normalized) return outcome;
    }
    throw FormatException('Invalid ReferralSaleCommitOutcome value: $value');
  }
}

class ReferralSaleBenefit {
  const ReferralSaleBenefit({
    required this.type,
    required this.value,
    required this.discountAmount,
    required this.pointsAwarded,
    required this.displayText,
  });

  final ReferralBenefitType type;
  final double value;
  final double discountAmount;
  final int pointsAwarded;
  final String displayText;

  factory ReferralSaleBenefit.fromMap(Map<String, dynamic> map) {
    return ReferralSaleBenefit(
      type: readRequiredEnum(
        map,
        ['type', 'benefit_type'],
        ReferralBenefitType.fromStorage,
      ),
      value: readRequiredDouble(map, ['value', 'benefit_value']),
      discountAmount:
          readNullableDouble(map, ['discount_amount', 'discountAmount']) ?? 0,
      pointsAwarded:
          (readNullableDouble(map, ['points_awarded', 'pointsAwarded']) ?? 0)
              .round(),
      displayText:
          readNullableString(map, ['display_text', 'displayText']) ?? '',
    );
  }
}

class ReferralSaleReward {
  const ReferralSaleReward({
    required this.id,
    required this.type,
    required this.value,
    required this.status,
  });

  final String id;
  final String type;
  final int value;
  final String status;

  factory ReferralSaleReward.fromMap(Map<String, dynamic> map) {
    return ReferralSaleReward(
      id: readNullableString(map, ['id']) ?? '',
      type: readNullableString(map, ['type']) ?? '',
      value: (readNullableDouble(map, ['value']) ?? 0).round(),
      status: readNullableString(map, ['status']) ?? 'PENDING',
    );
  }
}

class ReferralSaleCommit {
  const ReferralSaleCommit({
    required this.outcome,
    this.sale,
    this.affiliateId,
    this.affiliateCodeId,
    this.normalizedCode,
    this.benefit,
    this.attributionId,
    this.attributionStatus,
    this.reward,
    this.idempotencyKey,
    this.errorCode,
    this.message,
  });

  final ReferralSaleCommitOutcome outcome;

  /// The canonical sale, exactly as the server stored it. Null on a refusal.
  final Sale? sale;
  final String? affiliateId;
  final String? affiliateCodeId;
  final String? normalizedCode;
  final ReferralSaleBenefit? benefit;
  final String? attributionId;
  final String? attributionStatus;
  final ReferralSaleReward? reward;
  final String? idempotencyKey;

  /// Why the code could not be used, when [outcome] is `rejected`.
  final ReferralValidationErrorCode? errorCode;
  final String? message;

  bool get isAccepted => outcome != ReferralSaleCommitOutcome.rejected;

  /// True when the server recognised this as a sale it had already committed.
  bool get wasReplay => outcome == ReferralSaleCommitOutcome.replayed;

  factory ReferralSaleCommit.fromMap(Map<String, dynamic> map) {
    final outcome = readRequiredEnum(
      map,
      ['outcome'],
      ReferralSaleCommitOutcome.fromStorage,
    );

    if (outcome == ReferralSaleCommitOutcome.rejected) {
      return ReferralSaleCommit(
        outcome: outcome,
        errorCode: readNullableEnum(
          map,
          ['reason', 'error_code'],
          ReferralValidationErrorCode.fromStorage,
        ),
        message: readNullableString(map, ['message']),
      );
    }

    final referral = readNullableMap(map, ['referral']) ?? <String, dynamic>{};
    final benefit = readNullableMap(referral, ['benefit']);
    final reward = readNullableMap(referral, ['reward']);

    return ReferralSaleCommit(
      outcome: outcome,
      sale: referralSaleFromServerMap(
        readNullableMap(map, ['sale']) ?? <String, dynamic>{},
      ),
      affiliateId: readNullableString(referral, ['affiliate_id']),
      affiliateCodeId: readNullableString(referral, ['affiliate_code_id']),
      normalizedCode: readNullableString(referral, ['normalized_code']),
      benefit: benefit == null ? null : ReferralSaleBenefit.fromMap(benefit),
      attributionId: readNullableString(referral, ['attribution_id']),
      attributionStatus: readNullableString(referral, ['attribution_status']),
      reward: reward == null ? null : ReferralSaleReward.fromMap(reward),
      idempotencyKey: readNullableString(map, ['idempotency_key']),
    );
  }
}

/// The server's sale document, read as a [Sale].
///
/// The wire shape is the stored shape — `snake_case`, epoch milliseconds — the
/// same one the pull projection already writes into SQLite, so the mapping is
/// `saleFromMap` with the two numeric fields coerced: JSON gives back whatever
/// the encoder emitted, and `points` has to be an `int`.
///
/// `synced` is true because this sale did not come from the queue: the server
/// wrote it, and re-uploading it would ask the authoritative record to accept a
/// copy of itself.
Sale referralSaleFromServerMap(Map<String, dynamic> map) {
  final normalized = <String, dynamic>{
    ...map,
    'amount': (map['amount'] as num?)?.toDouble() ?? 0,
    'points': (map['points'] as num?)?.toInt() ?? 0,
    'synced': 1,
  };
  return saleFromMap(normalized);
}
