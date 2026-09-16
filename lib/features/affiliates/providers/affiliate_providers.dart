import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../business_profile/domain/business_profile.dart';
import '../data/affiliate_api.dart';
import '../data/affiliate_dao.dart';
import '../data/affiliate_local_repository.dart';
import '../data/affiliate_repository.dart';
import '../data/affiliate_sale_api.dart';
import '../data/affiliate_sale_repository.dart';
import '../domain/merchant_affiliate_dtos.dart';

/// The per-business affiliate switch, as the backend stores it.
///
/// Only [enabled] changes what the app offers; the rest is read so the screens
/// can explain what will happen â€” whether a reward needs approving, whether a
/// return is worth anything â€” instead of guessing defaults that the server may
/// not share.
class AffiliateFeatureConfig {
  const AffiliateFeatureConfig({
    this.enabled = false,
    this.firstSaleRewardPoints = 0,
    this.returnRewardEnabled = false,
    this.returnRewardPoints = 0,
    this.returnWindowDays = 30,
    this.rewardApprovalRequired = true,
    this.notificationsEnabled = true,
  });

  final bool enabled;
  final int firstSaleRewardPoints;
  final bool returnRewardEnabled;
  final int returnRewardPoints;
  final int returnWindowDays;
  final bool rewardApprovalRequired;
  final bool notificationsEnabled;

  /// What every business gets until someone turns the feature on: nothing.
  ///
  /// This is also what a failed read resolves to, deliberately. A business that
  /// cannot be asked is a business whose till must keep selling exactly as it
  /// did yesterday.
  static const AffiliateFeatureConfig disabled = AffiliateFeatureConfig();

  factory AffiliateFeatureConfig.fromBusinessData(Map<String, dynamic> data) {
    final raw = data['affiliate_config'];
    if (raw is! Map) return disabled;
    final config = raw.map((key, value) => MapEntry(key.toString(), value));

    bool flag(String key, bool fallback) {
      final value = config[key];
      return value is bool ? value : fallback;
    }

    int number(String key, int fallback) {
      final value = config[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return fallback;
    }

    return AffiliateFeatureConfig(
      enabled: flag('enabled', false),
      firstSaleRewardPoints: number('first_sale_reward_points', 0),
      returnRewardEnabled: flag('return_reward_enabled', false),
      returnRewardPoints: number('return_reward_points', 0),
      returnWindowDays: number('return_window_days', 30),
      rewardApprovalRequired: flag('reward_approval_required', true),
      notificationsEnabled: flag('notifications_enabled', true),
    );
  }
}

/// Reads the business's affiliate settings.
///
/// Resolves to [AffiliateFeatureConfig.disabled] without touching Firestore
/// when there is no merchant session, which is also what keeps the sale screen
/// buildable in a test that never signed anyone in.
final affiliateFeatureConfigProvider =
    FutureProvider<AffiliateFeatureConfig>((ref) async {
  final merchantId = ref.watch(activeMerchantIdProvider);
  if (merchantId == null || merchantId.isEmpty) {
    return AffiliateFeatureConfig.disabled;
  }
  try {
    final doc = await ref
        .read(firestoreInstanceProvider)
        .collection('businesses')
        .doc(merchantId)
        .get();
    return AffiliateFeatureConfig.fromBusinessData(
      doc.data() ?? const <String, dynamic>{},
    );
  } catch (_) {
    return AffiliateFeatureConfig.disabled;
  }
});

/// True only when the business has switched affiliates on.
///
/// A pending or failed read counts as off, so nothing new appears in the sale
/// flow while the answer is still unknown.
final affiliateFeatureEnabledProvider = Provider<bool>((ref) {
  return ref.watch(affiliateFeatureConfigProvider).valueOrNull?.enabled ??
      false;
});

/// The Firebase ID token, fetched per call.
///
/// Not cached: tokens expire, and a stale one turns every affiliate action into
/// an unexplained 401 an hour after login.
final affiliateAccessTokenResolverProvider =
    Provider<Future<String?> Function()>((ref) {
  final auth = ref.watch(firebaseAuthInstanceProvider);
  return () async => auth.currentUser?.getIdToken();
});

final affiliateApiProvider = Provider<AffiliateApi>((ref) {
  return AffiliateApi(
    ref.watch(cloudFunctionsApiClientProvider),
    ref.watch(affiliateAccessTokenResolverProvider),
  );
});

final affiliateGatewayProvider = Provider<AffiliateGateway>((ref) {
  return AffiliateRepository(ref.watch(affiliateApiProvider));
});

final affiliateSaleApiProvider = Provider<AffiliateSaleGateway>((ref) {
  return AffiliateSaleApi(
    ref.watch(cloudFunctionsApiClientProvider),
    ref.watch(affiliateAccessTokenResolverProvider),
  );
});

/// The repository that commits a referred sale, or null when this device cannot
/// identify itself.
///
/// Both ids are required and neither is invented. A commit carries
/// `device_id` + `local_sale_id` as its idempotency key, so a placeholder device
/// would make two different tills share a key and let one of them resolve to the
/// other's sale. Without a real one the caller is told plainly instead.
final affiliateSaleRepositoryProvider =
    Provider<AffiliateSaleRepository?>((ref) {
  final merchantId = ref.watch(activeMerchantIdProvider);
  final deviceId = ref.watch(activeDeviceIdProvider);
  if (merchantId == null || merchantId.isEmpty) return null;
  if (deviceId == null || deviceId.isEmpty) return null;
  return AffiliateSaleRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(affiliateSaleApiProvider),
    merchantId: merchantId,
    deviceId: deviceId,
    appUserId: ref.watch(activeAppUserIdProvider),
  );
});

/// The local projection of the affiliate tables, or null when this device has
/// no business to project them for.
final affiliateDaoProvider = Provider<AffiliateDao?>((ref) {
  final merchantId = ref.watch(activeMerchantIdProvider);
  if (merchantId == null || merchantId.isEmpty) return null;
  return AffiliateDao(ref.watch(appDatabaseProvider), merchantId: merchantId);
});

/// Everything the app does about affiliates without a server.
///
/// Requires both ids for the same reason the online commit does: the device id
/// is half of every idempotency key this writes, and a placeholder would let
/// two tills share a key and resolve to each other's sale.
final affiliateLocalRepositoryProvider =
    Provider<AffiliateLocalRepository?>((ref) {
  final merchantId = ref.watch(activeMerchantIdProvider);
  final deviceId = ref.watch(activeDeviceIdProvider);
  final dao = ref.watch(affiliateDaoProvider);
  if (merchantId == null || merchantId.isEmpty) return null;
  if (deviceId == null || deviceId.isEmpty) return null;
  if (dao == null) return null;
  return AffiliateLocalRepository(
    ref.watch(appDatabaseProvider),
    dao,
    merchantId: merchantId,
    deviceId: deviceId,
    appUserId: ref.watch(activeAppUserIdProvider),
    gateway: ref.watch(affiliateGatewayProvider),
    pointsPerMzn: ref
            .watch(activeBusinessProfileProvider)
            .valueOrNull
            ?.loyalty
            .pointsPerMzn ??
        BusinessProfiles.generic.loyalty.pointsPerMzn,
  );
});

/// The narrow view of the offline path the screens use.
///
/// Separate from [affiliateLocalRepositoryProvider], which the sync queue needs
/// in full: a screen only ever previews, records and lists, and depending on
/// the interface is what lets a widget test state what this till knows without
/// standing up SQLite inside a pump.
final affiliateOfflineGatewayProvider =
    Provider<AffiliateOfflineGateway?>((ref) {
  return ref.watch(affiliateLocalRepositoryProvider);
});

/// The affiliates of this business, filtered by status.
final affiliateListProvider = FutureProvider.autoDispose
    .family<AffiliateListView, AffiliateListFilter>((ref, filter) {
  return ref
      .watch(affiliateGatewayProvider)
      .loadAffiliateList(status: filter.wireValue);
});
final affiliateDetailProvider =
    FutureProvider.autoDispose.family<AffiliateDetailSnapshot, String>(
  (ref, affiliateId) {
    return ref.watch(affiliateGatewayProvider).loadAffiliateDetail(affiliateId);
  },
);

/// The rewards queue. A null id means the whole business.
final affiliateRewardsProvider = FutureProvider.autoDispose
    .family<AffiliatePage<MerchantAffiliateReward>, String?>(
  (ref, affiliateId) {
    return ref.watch(affiliateGatewayProvider).listRewards(
          affiliateId: affiliateId,
        );
  },
);

final affiliateMetricsProvider =
    FutureProvider.autoDispose<AffiliateMetricsSummary>((ref) {
  return ref.watch(affiliateGatewayProvider).merchantMetrics();
});

/// The affiliates this device added without a connection.
///
/// Read from SQLite rather than from the API on purpose: these are exactly the
/// people the API has never heard of, and a list that only showed confirmed
/// affiliates would make an offline create look like it did nothing.
final provisionalAffiliatesProvider =
    FutureProvider.autoDispose<List<ProvisionalAffiliate>>((ref) async {
  final repository = ref.watch(affiliateOfflineGatewayProvider);
  if (repository == null) return const <ProvisionalAffiliate>[];
  return repository.provisionalAffiliates();
});

/// The mutations, all of which the server refuses for a non-owner.
///
/// Each one invalidates the lists it could have changed rather than patching
/// them in place: the server owns the code, the status and the reward, and a
/// locally edited copy would disagree with it the moment another till acted.
class AffiliateAdminController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<MerchantAffiliate> createAffiliate(AffiliateDraft draft) async {
    return _run(
        () => ref.read(affiliateGatewayProvider).createAffiliate(draft));
  }

  Future<MerchantAffiliate> setAffiliateActive({
    required String affiliateId,
    required bool active,
  }) async {
    return _run(
      () => ref.read(affiliateGatewayProvider).setAffiliateActive(
            affiliateId: affiliateId,
            active: active,
          ),
      affiliateId: affiliateId,
    );
  }

  Future<MerchantAffiliateCode> updateCode({
    required AffiliateCodeEdit edit,
    required String affiliateId,
  }) async {
    return _run(
      () => ref.read(affiliateGatewayProvider).updateCode(edit),
      affiliateId: affiliateId,
    );
  }

  Future<MerchantAffiliateCode> setCodeEnabled({
    required String codeId,
    required bool enabled,
    required String affiliateId,
  }) async {
    return _run(
      () => ref.read(affiliateGatewayProvider).setCodeEnabled(
            codeId: codeId,
            enabled: enabled,
          ),
      affiliateId: affiliateId,
    );
  }

  Future<MerchantAffiliateReward> approveReward({
    required String rewardId,
    String? affiliateId,
  }) async {
    return _run(
      () => ref.read(affiliateGatewayProvider).approveReward(rewardId),
      affiliateId: affiliateId,
    );
  }

  Future<MerchantAffiliateReward> cancelReward({
    required String rewardId,
    String? affiliateId,
  }) async {
    return _run(
      () => ref.read(affiliateGatewayProvider).cancelReward(rewardId),
      affiliateId: affiliateId,
    );
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    String? affiliateId,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await action();
      state = const AsyncData(null);
      _invalidate(affiliateId);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void _invalidate(String? affiliateId) {
    ref.invalidate(affiliateListProvider);
    ref.invalidate(affiliateRewardsProvider);
    ref.invalidate(affiliateMetricsProvider);
    if (affiliateId != null) {
      ref.invalidate(affiliateDetailProvider(affiliateId));
    }
  }
}

final affiliateAdminControllerProvider =
    AsyncNotifierProvider<AffiliateAdminController, void>(
  AffiliateAdminController.new,
);
