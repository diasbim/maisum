import '../domain/affiliate.dart';
import '../domain/affiliate_reward.dart';
import '../domain/merchant_affiliate_dtos.dart';
import 'affiliate_api.dart';

/// What the affiliate screens are allowed to ask for.
///
/// The screens talk to this and never to [AffiliateApi] directly, which is what
/// lets a test replace the whole backend with a few lines instead of a fake
/// HTTP server, and what keeps a route rename from reaching the widgets.
abstract interface class AffiliateGateway {
  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
  });

  Future<AffiliateListView> loadAffiliateList({String? status});

  Future<MerchantAffiliate> getAffiliate(String affiliateId);

  Future<AffiliateDetailSnapshot> loadAffiliateDetail(String affiliateId);

  Future<MerchantAffiliate> createAffiliate(AffiliateDraft draft);

  Future<MerchantAffiliate> setAffiliateActive({
    required String affiliateId,
    required bool active,
  });

  Future<MerchantAffiliateCode> updateCode(AffiliateCodeEdit edit);

  Future<MerchantAffiliateCode> setCodeEnabled({
    required String codeId,
    required bool enabled,
  });

  Future<AffiliatePage<MerchantAffiliateReward>> listRewards({
    String? affiliateId,
    String? status,
  });

  Future<MerchantAffiliateReward> approveReward(String rewardId);

  Future<MerchantAffiliateReward> cancelReward(String rewardId);

  Future<AffiliateMetricsSummary> merchantMetrics();
}

/// The form an owner fills to add an affiliate, already in the server's words.
class AffiliateDraft {
  const AffiliateDraft({
    required this.name,
    required this.phone,
    required this.benefitType,
    required this.benefitValue,
    this.usageLimit,
    this.firstVisitOnly = true,
    this.expiresAt,
  });

  final String name;
  final String phone;
  final String benefitType;
  final double benefitValue;

  /// Null means unlimited, which the API spells the same way.
  final int? usageLimit;
  final bool firstVisitOnly;
  final DateTime? expiresAt;
}

/// A change to an existing code. Absent fields are left alone.
class AffiliateCodeEdit {
  const AffiliateCodeEdit({
    required this.codeId,
    this.benefitType,
    this.benefitValue,
    this.startsAt,
    this.expiresAt,
    this.usageLimit,
    this.clearUsageLimit = false,
    this.firstVisitOnly,
  });

  final String codeId;
  final String? benefitType;
  final double? benefitValue;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? usageLimit;
  final bool clearUsageLimit;
  final bool? firstVisitOnly;
}

class AffiliateRepository implements AffiliateGateway {
  const AffiliateRepository(this._api);

  final AffiliateApi _api;

  /// The page size the list screens ask for.
  ///
  /// Below the server's 200 cap on purpose: a business with more affiliates
  /// than this is told the list is partial rather than shown a silent prefix.
  static const int pageSize = 100;

  @override
  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
  }) {
    return _api.listAffiliates(
      search: search,
      status: status,
      limit: pageSize,
    );
  }

  @override
  Future<MerchantAffiliate> getAffiliate(String affiliateId) {
    return _api.getAffiliate(affiliateId);
  }

  /// The list with the two numbers the cards show beside each name.
  ///
  /// The pending-reward count comes from a second call because the list
  /// endpoint does not carry it. That call is allowed to fail on its own: an
  /// owner who opened this screen wants to see who their affiliates are, and
  /// hiding all of them because one secondary count is missing would be a worse
  /// answer than showing them with the count flagged as unavailable.
  @override
  Future<AffiliateListView> loadAffiliateList({String? status}) async {
    final page = await _api.listAffiliates(status: status, limit: pageSize);

    var rewardsUnavailable = false;
    final pendingByAffiliate = <String, int>{};
    try {
      final rewards = await _api.listRewards(
        status: AffiliateRewardStatus.pending.storageValue,
        limit: pageSize,
      );
      rewardsUnavailable = rewards.truncated || rewards.hasMore;
      for (final reward in rewards.items) {
        if (reward.status != AffiliateRewardStatus.pending) continue;
        pendingByAffiliate.update(
          reward.affiliateId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    } catch (_) {
      rewardsUnavailable = true;
    }

    return AffiliateListView(
      items: <AffiliateListItem>[
        for (final affiliate in page.items)
          AffiliateListItem(
            affiliate: affiliate,
            referredCustomers: affiliate.code?.usageCount ?? 0,
            pendingRewards: rewardsUnavailable
                ? null
                : pendingByAffiliate[affiliate.id] ?? 0,
          ),
      ],
      truncated: page.truncated,
      rewardsUnavailable: rewardsUnavailable,
    );
  }

  /// Everything the detail screen shows, gathered in parallel.
  ///
  /// The three calls are independent, and the screen is useless without all of
  /// them, so a failure in any one surfaces as a failure of the load rather
  /// than as a screen with a silently missing section.
  @override
  Future<AffiliateDetailSnapshot> loadAffiliateDetail(
    String affiliateId,
  ) async {
    final results = await Future.wait(<Future<Object>>[
      _api.getAffiliate(affiliateId),
      _api.affiliateMetrics(affiliateId),
      _api.listRewards(affiliateId: affiliateId, limit: pageSize),
    ]);

    final affiliate = results[0] as MerchantAffiliate;
    final metrics = results[1] as AffiliateMetricsSummary;
    final rewards = results[2] as AffiliatePage<MerchantAffiliateReward>;

    return AffiliateDetailSnapshot(
      affiliate: affiliate,
      metrics: metrics,
      pendingRewards: rewards.items
          .where((reward) => reward.status == AffiliateRewardStatus.pending)
          .toList(growable: false),
      approvedRewards: rewards.items
          .where((reward) => reward.status == AffiliateRewardStatus.approved)
          .toList(growable: false),
      truncated: metrics.truncated || rewards.truncated,
    );
  }

  @override
  Future<MerchantAffiliate> createAffiliate(AffiliateDraft draft) {
    return _api.createAffiliate(
      name: draft.name,
      phone: draft.phone,
      benefitType: draft.benefitType,
      benefitValue: draft.benefitValue,
      usageLimit: draft.usageLimit,
      includeUsageLimit: true,
      firstVisitOnly: draft.firstVisitOnly,
      expiresAt: draft.expiresAt,
    );
  }

  @override
  Future<MerchantAffiliate> setAffiliateActive({
    required String affiliateId,
    required bool active,
  }) {
    return active
        ? _api.activateAffiliate(affiliateId)
        : _api.deactivateAffiliate(affiliateId);
  }

  @override
  Future<MerchantAffiliateCode> updateCode(AffiliateCodeEdit edit) {
    return _api.updateCode(
      codeId: edit.codeId,
      benefitType: edit.benefitType,
      benefitValue: edit.benefitValue,
      startsAt: edit.startsAt,
      expiresAt: edit.expiresAt,
      usageLimit: edit.usageLimit,
      clearUsageLimit: edit.clearUsageLimit,
      firstVisitOnly: edit.firstVisitOnly,
    );
  }

  @override
  Future<MerchantAffiliateCode> setCodeEnabled({
    required String codeId,
    required bool enabled,
  }) {
    return enabled ? _api.enableCode(codeId) : _api.disableCode(codeId);
  }

  @override
  Future<AffiliatePage<MerchantAffiliateReward>> listRewards({
    String? affiliateId,
    String? status,
  }) {
    return _api.listRewards(
      affiliateId: affiliateId,
      status: status,
      limit: pageSize,
    );
  }

  @override
  Future<MerchantAffiliateReward> approveReward(String rewardId) {
    return _api.approveReward(rewardId);
  }

  @override
  Future<MerchantAffiliateReward> cancelReward(String rewardId) {
    return _api.cancelReward(rewardId);
  }

  @override
  Future<AffiliateMetricsSummary> merchantMetrics() {
    return _api.merchantMetrics();
  }
}

/// The status filter values the list screen offers, in the server's spelling.
enum AffiliateListFilter {
  all(null, 'Todos'),
  active('ACTIVE', 'Ativos'),
  inactive('INACTIVE', 'Inativos');

  const AffiliateListFilter(this.wireValue, this.label);

  final String? wireValue;
  final String label;
}

/// Reads an affiliate's operational status as one label.
///
/// A suspended affiliate is suspended everywhere; an unlinked one is inactive
/// only here. Collapsing the two into "inactive" would hide a platform-level
/// suspension from the owner who has to explain it.
String affiliateStatusLabel(MerchantAffiliate affiliate) {
  if (affiliate.status == AffiliateStatus.suspended) return 'Suspenso';
  if (!affiliate.isLinkActive) return 'Inativo';
  if (affiliate.status == AffiliateStatus.inactive) return 'Inativo';
  return 'Ativo';
}
