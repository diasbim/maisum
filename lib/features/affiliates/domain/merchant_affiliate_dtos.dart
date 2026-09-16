import 'affiliate.dart';
import 'affiliate_attribution.dart';
import 'affiliate_code.dart';
import 'affiliate_reward.dart';
import 'affiliate_serialization.dart';

/// The shapes the merchant affiliate API actually sends.
///
/// These are deliberately separate from the stored models in this folder. The
/// stored models describe a row that is already complete — every timestamp
/// present, every foreign key resolved — because SQLite only ever holds a
/// record the server has already confirmed. The API answers about records that
/// are still being written: an attribution with no sale yet, a reward with no
/// approval yet, an affiliate whose phone the caller is not allowed to see. A
/// single class cannot be both strict about the first and honest about the
/// second, and making the stored model lenient would let a half-written row
/// into the database.
///
/// The enums are shared, though, and on purpose: a status the wire can send and
/// this app cannot name is a contract break, so parsing throws rather than
/// falling back to a default that would quietly mislabel a suspended affiliate
/// as an active one.

/// One page of a list endpoint, with the two facts that say whether it is the
/// whole answer.
///
/// [hasMore] is ordinary paging. [truncated] is not: it means the server
/// stopped scanning before it reached the end, so the counts and the list are
/// both a floor rather than a total, and the UI has to say so instead of
/// presenting a partial answer as complete.
class AffiliatePage<T> {
  const AffiliatePage({
    required this.items,
    this.limit = 0,
    this.offset = 0,
    this.hasMore = false,
    this.total = 0,
    this.truncated = false,
  });

  final List<T> items;
  final int limit;
  final int offset;
  final bool hasMore;
  final int total;
  final bool truncated;

  bool get isEmpty => items.isEmpty;

  static AffiliatePage<T> fromEnvelope<T>(
    Map<String, dynamic>? envelope,
    Object? data,
    T Function(Map<String, dynamic> item) parse,
  ) {
    final rows = <T>[];
    if (data is List) {
      for (final row in data) {
        final map = _asMap(row);
        if (map != null) rows.add(parse(map));
      }
    }
    final paging =
        envelope == null ? null : readNullableMap(envelope, ['paging', 'page']);
    return AffiliatePage<T>(
      items: rows,
      limit: paging == null ? 0 : readNullableInt(paging, ['limit']) ?? 0,
      offset: paging == null ? 0 : readNullableInt(paging, ['offset']) ?? 0,
      hasMore: paging != null && readBool(paging, ['has_more', 'hasMore']),
      total: envelope == null
          ? rows.length
          : readNullableInt(envelope, ['total']) ?? rows.length,
      truncated: envelope != null && readBool(envelope, ['truncated']),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

enum MerchantAffiliateCodeAvailability {
  active,
  disabled,
  notStarted,
  expired,
  exhausted,
}

/// A code as the API reports it.
///
/// `created_at`/`updated_at` are nullable on the wire because a code minted in
/// the same request has not been read back yet; the stored model requires them,
/// which is why this is not that model.
class MerchantAffiliateCode {
  const MerchantAffiliateCode({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.code,
    required this.normalizedCode,
    required this.benefitType,
    required this.benefitValue,
    required this.status,
    this.startsAt,
    this.expiresAt,
    this.usageLimit,
    this.usageCount = 0,
    this.firstVisitOnly = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final String code;
  final String normalizedCode;
  final ReferralBenefitType benefitType;
  final double benefitValue;
  final AffiliateCodeStatus status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? usageLimit;
  final int usageCount;
  final bool firstVisitOnly;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == AffiliateCodeStatus.active;

  bool get isUnlimited => usageLimit == null;

  int? get remainingUses {
    final limit = usageLimit;
    if (limit == null) return null;
    final left = limit - usageCount;
    return left < 0 ? 0 : left;
  }

  MerchantAffiliateCodeAvailability availabilityAt(DateTime now) {
    if (!isActive) return MerchantAffiliateCodeAvailability.disabled;
    if (startsAt != null && now.isBefore(startsAt!)) {
      return MerchantAffiliateCodeAvailability.notStarted;
    }
    if (expiresAt != null && !now.isBefore(expiresAt!)) {
      return MerchantAffiliateCodeAvailability.expired;
    }
    final limit = usageLimit;
    if (limit != null && usageCount >= limit) {
      return MerchantAffiliateCodeAvailability.exhausted;
    }
    return MerchantAffiliateCodeAvailability.active;
  }

  bool isUsableAt(DateTime now) =>
      availabilityAt(now) == MerchantAffiliateCodeAvailability.active;

  factory MerchantAffiliateCode.fromMap(Map<String, dynamic> map) {
    return MerchantAffiliateCode(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      code: readRequiredString(map, ['code']),
      normalizedCode: readNullableString(
            map,
            ['normalized_code', 'normalizedCode'],
          ) ??
          readRequiredString(map, ['code']),
      benefitType: readRequiredEnum(
        map,
        ['benefit_type', 'benefitType'],
        ReferralBenefitType.fromStorage,
      ),
      benefitValue: readRequiredDouble(map, ['benefit_value', 'benefitValue']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateCodeStatus.fromStorage,
      ),
      startsAt: readNullableDateTime(map, ['starts_at', 'startsAt']),
      expiresAt: readNullableDateTime(map, ['expires_at', 'expiresAt']),
      usageLimit: readNullableInt(map, ['usage_limit', 'usageLimit']),
      usageCount: readNullableInt(map, ['usage_count', 'usageCount']) ?? 0,
      firstVisitOnly: readBool(
        map,
        ['first_visit_only', 'firstVisitOnly'],
        defaultValue: true,
      ),
      createdAt: readNullableDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readNullableDateTime(map, ['updated_at', 'updatedAt']),
    );
  }
}

/// An affiliate as seen from inside one business.
///
/// [phone] can be absent: the API withholds it from callers who may not see it
/// and sends only [phoneLast4], so the UI has to be able to render a row that
/// has no number at all rather than inventing one.
class MerchantAffiliate {
  const MerchantAffiliate({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.firstName,
    required this.status,
    required this.linkStatus,
    this.lastName,
    this.phone,
    this.phoneLast4,
    this.linkedAt,
    this.createdAt,
    this.updatedAt,
    this.code,
  });

  final String id;
  final String merchantId;
  final String name;
  final String firstName;
  final String? lastName;
  final String? phone;
  final String? phoneLast4;
  final AffiliateStatus status;
  final AffiliateMerchantStatus linkStatus;
  final DateTime? linkedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final MerchantAffiliateCode? code;

  bool get isLinkActive => linkStatus == AffiliateMerchantStatus.active;

  bool get isSuspended => status == AffiliateStatus.suspended;

  /// True when this affiliate can be handed a code to share.
  ///
  /// A suspended or unlinked affiliate still has a code row, but using it would
  /// be refused at the till, so offering to share it would be a promise the
  /// business cannot keep.
  bool canShareCodeAt(DateTime now) =>
      code != null &&
      code!.isUsableAt(now) &&
      isLinkActive &&
      status == AffiliateStatus.active;

  bool get canShareCode => canShareCodeAt(DateTime.now());

  DateTime? get lastActivityAt {
    final candidates = <DateTime>[
      if (updatedAt != null) updatedAt!,
      if (code?.updatedAt != null) code!.updatedAt!,
      if (linkedAt != null) linkedAt!,
    ];
    if (candidates.isEmpty) return createdAt;
    candidates.sort();
    return candidates.last;
  }

  factory MerchantAffiliate.fromMap(Map<String, dynamic> map) {
    final codeMap = readNullableMap(map, ['code']);
    final name = readNullableString(map, ['name', 'display_name']) ??
        readRequiredString(map, ['first_name', 'firstName']);
    return MerchantAffiliate(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      name: name,
      firstName: readNullableString(map, ['first_name', 'firstName']) ?? name,
      lastName: readNullableString(map, ['last_name', 'lastName']),
      phone: readNullableString(map, ['phone']),
      phoneLast4: readNullableString(map, ['phone_last4', 'phoneLast4']),
      status: readRequiredEnum(map, ['status'], AffiliateStatus.fromStorage),
      linkStatus: readRequiredEnum(
        map,
        ['link_status', 'linkStatus'],
        AffiliateMerchantStatus.fromStorage,
      ),
      linkedAt: readNullableDateTime(map, ['linked_at', 'linkedAt']),
      createdAt: readNullableDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readNullableDateTime(map, ['updated_at', 'updatedAt']),
      code: codeMap == null ? null : MerchantAffiliateCode.fromMap(codeMap),
    );
  }
}

/// An acquisition the server attributed to a code.
class MerchantReferralAttribution {
  const MerchantReferralAttribution({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.status,
    this.affiliateCodeId,
    this.customerId,
    this.firstSaleId,
    this.rejectionReason,
    this.attributedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final AffiliateAttributionStatus status;
  final String? affiliateCodeId;
  final String? customerId;
  final String? firstSaleId;
  final String? rejectionReason;
  final DateTime? attributedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isConfirmed => status == AffiliateAttributionStatus.confirmed;

  factory MerchantReferralAttribution.fromMap(Map<String, dynamic> map) {
    return MerchantReferralAttribution(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateAttributionStatus.fromStorage,
      ),
      affiliateCodeId: readNullableString(
        map,
        ['affiliate_code_id', 'affiliateCodeId'],
      ),
      customerId: readNullableString(map, ['customer_id', 'customerId']),
      firstSaleId: readNullableString(map, ['first_sale_id', 'firstSaleId']),
      rejectionReason: readNullableString(
        map,
        ['rejection_reason', 'rejectionReason'],
      ),
      attributedAt:
          readNullableDateTime(map, ['attributed_at', 'attributedAt']),
      createdAt: readNullableDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readNullableDateTime(map, ['updated_at', 'updatedAt']),
    );
  }
}

/// A reward as the API reports it: `type`/`value`, not `reward_type`/
/// `reward_value`, and with no attribution when the reward stands alone.
class MerchantAffiliateReward {
  const MerchantAffiliateReward({
    required this.id,
    required this.merchantId,
    required this.affiliateId,
    required this.type,
    required this.valueType,
    required this.value,
    required this.status,
    this.attributionId,
    this.triggerSaleId,
    this.approvedBy,
    this.approvedAt,
    this.paidAt,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String merchantId;
  final String affiliateId;
  final AffiliateRewardType type;
  final AffiliateRewardValueType valueType;
  final double value;
  final AffiliateRewardStatus status;
  final String? attributionId;
  final String? triggerSaleId;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == AffiliateRewardStatus.pending;

  /// Only a pending reward can still be approved or cancelled; the server
  /// answers 409 for anything else, so the buttons come off rather than
  /// offering a call that is already known to fail.
  bool get isDecidable => isPending;

  factory MerchantAffiliateReward.fromMap(Map<String, dynamic> map) {
    return MerchantAffiliateReward(
      id: readRequiredString(map, ['id']),
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readRequiredString(map, ['affiliate_id', 'affiliateId']),
      type: readRequiredEnum(
        map,
        ['type', 'reward_type', 'rewardType'],
        AffiliateRewardType.fromStorage,
      ),
      valueType: readRequiredEnum(
        map,
        ['value_type', 'valueType'],
        AffiliateRewardValueType.fromStorage,
      ),
      value: readRequiredDouble(map, ['value', 'reward_value', 'rewardValue']),
      status: readRequiredEnum(
        map,
        ['status'],
        AffiliateRewardStatus.fromStorage,
      ),
      attributionId: readNullableString(
        map,
        ['attribution_id', 'attributionId'],
      ),
      triggerSaleId: readNullableString(
        map,
        ['trigger_sale_id', 'triggerSaleId'],
      ),
      approvedBy: readNullableString(map, ['approved_by', 'approvedBy']),
      approvedAt: readNullableDateTime(map, ['approved_at', 'approvedAt']),
      paidAt: readNullableDateTime(map, ['paid_at', 'paidAt']),
      cancelledAt: readNullableDateTime(map, ['cancelled_at', 'cancelledAt']),
      createdAt: readNullableDateTime(map, ['created_at', 'createdAt']),
      updatedAt: readNullableDateTime(map, ['updated_at', 'updatedAt']),
    );
  }
}

/// The six numbers the business is owed, plus the honesty flag.
///
/// [conversionRate] is `confirmedAttributions / uniqueValidationAttempts`, which
/// the server sends as `0` when nothing has been attempted. That is arithmetic,
/// not a result: the screen says so instead of printing "0%" for a business
/// that has never had a code typed.
class AffiliateMetricsSummary {
  const AffiliateMetricsSummary({
    required this.merchantId,
    this.affiliateId,
    this.uniqueValidationAttempts = 0,
    this.confirmedAttributions = 0,
    this.rejectedAttributions = 0,
    this.returnedCustomers = 0,
    this.pendingRewardCount = 0,
    this.pendingRewardPoints = 0,
    this.approvedRewardCount = 0,
    this.approvedRewardPoints = 0,
    this.conversionRate = 0,
    this.lastActivityAt,
    this.truncated = false,
  });

  final String merchantId;
  final String? affiliateId;
  final int uniqueValidationAttempts;
  final int confirmedAttributions;
  final int rejectedAttributions;
  final int returnedCustomers;
  final int pendingRewardCount;
  final int pendingRewardPoints;
  final int approvedRewardCount;
  final int approvedRewardPoints;
  final double conversionRate;
  final DateTime? lastActivityAt;
  final bool truncated;

  /// False when no code has ever been tried, which is the only case where a
  /// conversion rate would be a division by zero.
  bool get hasConversionRate => uniqueValidationAttempts > 0;

  factory AffiliateMetricsSummary.fromMap(Map<String, dynamic> map) {
    return AffiliateMetricsSummary(
      merchantId: readRequiredString(map, ['merchant_id', 'merchantId']),
      affiliateId: readNullableString(map, ['affiliate_id', 'affiliateId']),
      uniqueValidationAttempts: readNullableInt(
            map,
            ['unique_validation_attempts', 'uniqueValidationAttempts'],
          ) ??
          0,
      confirmedAttributions: readNullableInt(
            map,
            ['confirmed_attributions', 'confirmedAttributions'],
          ) ??
          0,
      rejectedAttributions: readNullableInt(
            map,
            ['rejected_attributions', 'rejectedAttributions'],
          ) ??
          0,
      returnedCustomers: readNullableInt(
            map,
            ['returned_customers', 'returnedCustomers'],
          ) ??
          0,
      pendingRewardCount: readNullableInt(
            map,
            ['pending_reward_count', 'pendingRewardCount'],
          ) ??
          0,
      pendingRewardPoints: readNullableInt(
            map,
            ['pending_reward_points', 'pendingRewardPoints'],
          ) ??
          0,
      approvedRewardCount: readNullableInt(
            map,
            ['approved_reward_count', 'approvedRewardCount'],
          ) ??
          0,
      approvedRewardPoints: readNullableInt(
            map,
            ['approved_reward_points', 'approvedRewardPoints'],
          ) ??
          0,
      conversionRate:
          readNullableDouble(map, ['conversion_rate', 'conversionRate']) ?? 0,
      lastActivityAt: readNullableDateTime(
        map,
        ['last_activity_at', 'lastActivityAt'],
      ),
      truncated: readBool(map, ['truncated']),
    );
  }
}

/// One acquisition with the rewards it produced.
class MerchantReferralDetail {
  const MerchantReferralDetail({
    required this.attribution,
    this.rewards = const <MerchantAffiliateReward>[],
  });

  final MerchantReferralAttribution attribution;
  final List<MerchantAffiliateReward> rewards;

  factory MerchantReferralDetail.fromMap(Map<String, dynamic> map) {
    final rewards = <MerchantAffiliateReward>[];
    final raw = map['rewards'];
    if (raw is List) {
      for (final row in raw) {
        final rowMap = _asMap(row);
        if (rowMap != null) {
          rewards.add(MerchantAffiliateReward.fromMap(rowMap));
        }
      }
    }
    return MerchantReferralDetail(
      attribution: MerchantReferralAttribution.fromMap(map),
      rewards: rewards,
    );
  }
}

/// The per-affiliate figures the detail screen shows, gathered from the
/// endpoints that own each of them.
class AffiliateDetailSnapshot {
  const AffiliateDetailSnapshot({
    required this.affiliate,
    required this.metrics,
    this.pendingRewards = const <MerchantAffiliateReward>[],
    this.approvedRewards = const <MerchantAffiliateReward>[],
    this.truncated = false,
  });

  final MerchantAffiliate affiliate;
  final AffiliateMetricsSummary metrics;
  final List<MerchantAffiliateReward> pendingRewards;
  final List<MerchantAffiliateReward> approvedRewards;
  final bool truncated;
}

/// One row of the affiliate list.
///
/// [referredCustomers] is the code's usage count, which the server only
/// increments for a confirmed acquisition — so it is the number of customers
/// this affiliate actually brought in, not the number of times the code was
/// typed.
class AffiliateListItem {
  const AffiliateListItem({
    required this.affiliate,
    this.referredCustomers = 0,
    this.pendingRewards = 0,
  });

  final MerchantAffiliate affiliate;
  final int referredCustomers;
  final int? pendingRewards;
}

class AffiliateListView {
  const AffiliateListView({
    required this.items,
    this.truncated = false,
    this.rewardsUnavailable = false,
  });

  final List<AffiliateListItem> items;
  final bool truncated;

  /// True when the affiliates loaded but their pending-reward counts did not.
  ///
  /// The list is still worth showing — the names and states are correct — so
  /// this degrades to a partial answer that says so, rather than an error page
  /// over a secondary number.
  final bool rewardsUnavailable;

  bool get isEmpty => items.isEmpty;
}
