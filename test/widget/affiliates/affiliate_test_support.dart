import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/features/affiliates/data/affiliate_repository.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/affiliate_reward.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/providers/affiliate_providers.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';

/// A backend the affiliate screens can be pointed at.
///
/// Every method either answers from a field or throws what the field holds, so
/// a test states the server's answer rather than staging an HTTP exchange. The
/// counters are here because several of the behaviours worth protecting are
/// about how many calls happen, not what they return.
class FakeAffiliateGateway implements AffiliateGateway {
  FakeAffiliateGateway({
    this.listView,
    this.detail,
    this.rewards,
    this.metrics,
    this.created,
    this.listError,
    this.detailError,
    this.rewardsError,
    this.metricsError,
    this.createError,
    this.mutationError,
    this.delay = Duration.zero,
  });

  AffiliateListView? listView;
  AffiliateDetailSnapshot? detail;
  AffiliatePage<MerchantAffiliateReward>? rewards;
  AffiliateMetricsSummary? metrics;
  MerchantAffiliate? created;

  Object? listError;
  Object? detailError;
  Object? rewardsError;
  Object? metricsError;
  Object? createError;
  Object? mutationError;
  Duration delay;

  int listCalls = 0;
  AffiliateDraft? lastDraft;
  final List<String> approvedRewardIds = <String>[];
  final List<String> cancelledRewardIds = <String>[];
  final List<({String affiliateId, bool active})> linkChanges =
      <({String affiliateId, bool active})>[];
  final List<AffiliateCodeEdit> codeEdits = <AffiliateCodeEdit>[];

  Future<T> _answer<T>(Object? error, T? value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error;
    if (value == null) {
      throw StateError('FakeAffiliateGateway has no answer configured');
    }
    return value;
  }

  @override
  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
  }) async {
    final view = await loadAffiliateList(status: status);
    return AffiliatePage<MerchantAffiliate>(
      items: <MerchantAffiliate>[
        for (final item in view.items) item.affiliate,
      ],
      truncated: view.truncated,
    );
  }

  @override
  Future<AffiliateListView> loadAffiliateList({String? status}) {
    listCalls += 1;
    return _answer(listError, listView);
  }

  @override
  Future<MerchantAffiliate> getAffiliate(String affiliateId) {
    return _answer(detailError, detail?.affiliate);
  }

  @override
  Future<AffiliateDetailSnapshot> loadAffiliateDetail(String affiliateId) {
    return _answer(detailError, detail);
  }

  @override
  Future<MerchantAffiliate> createAffiliate(AffiliateDraft draft) {
    lastDraft = draft;
    return _answer(createError, created);
  }

  @override
  Future<MerchantAffiliate> setAffiliateActive({
    required String affiliateId,
    required bool active,
  }) {
    linkChanges.add((affiliateId: affiliateId, active: active));
    return _answer(mutationError, detail?.affiliate);
  }

  @override
  Future<MerchantAffiliateCode> updateCode(AffiliateCodeEdit edit) {
    codeEdits.add(edit);
    return _answer(mutationError, detail?.affiliate.code);
  }

  @override
  Future<MerchantAffiliateCode> setCodeEnabled({
    required String codeId,
    required bool enabled,
  }) {
    return _answer(mutationError, detail?.affiliate.code);
  }

  @override
  Future<AffiliatePage<MerchantAffiliateReward>> listRewards({
    String? affiliateId,
    String? status,
  }) {
    return _answer(rewardsError, rewards);
  }

  @override
  Future<MerchantAffiliateReward> approveReward(String rewardId) {
    approvedRewardIds.add(rewardId);
    return _answer(mutationError, rewards?.items.first);
  }

  @override
  Future<MerchantAffiliateReward> cancelReward(String rewardId) {
    cancelledRewardIds.add(rewardId);
    return _answer(mutationError, rewards?.items.first);
  }

  @override
  Future<AffiliateMetricsSummary> merchantMetrics() {
    return _answer(metricsError, metrics);
  }
}

/// A signed-in merchant session with no Firebase behind it.
class FakeAuthController extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        userId: 'user-1',
        phone: '841234567',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        merchantId: 'shop-1',
        merchantName: 'Salão Bela',
        deviceId: 'till-1',
      );
}

List<Override> affiliateOverrides({
  required FakeAffiliateGateway gateway,
  bool isOwner = true,
  bool online = true,
  bool withSession = true,
}) {
  return <Override>[
    affiliateGatewayProvider.overrideWithValue(gateway),
    isOwnerUserProvider.overrideWith((ref) async => isOwner),
    isOnlineProvider.overrideWith((ref) => Stream<bool>.value(online)),
    if (withSession)
      authControllerProvider.overrideWith(FakeAuthController.new),
  ];
}

Widget wrapScreen(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// Re-renders [child] at [scale] without discarding the real screen metrics.
Widget textScaled(Widget child, double scale) {
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: child,
    ),
  );
}

/// Scrolls a control into view before tapping it.
///
/// These forms are longer than the 800×600 test surface, which is not a layout
/// problem — it is a phone-sized page — but a tap at an off-screen offset hits
/// nothing and the test would pass for the wrong reason.
Future<void> tapControl(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

/// A phone-shaped surface tall enough to hold a whole form.
///
/// The default test window is 800×600, which is wider and far shorter than any
/// phone these screens run on, so it produces scroll offsets no real device
/// would have.
void usePhoneSurface(
  WidgetTester tester, {
  Size size = const Size(420, 1600),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MerchantAffiliateCode sampleCode({
  String id = 'code-1',
  AffiliateCodeStatus status = AffiliateCodeStatus.active,
  ReferralBenefitType benefitType = ReferralBenefitType.fixedAmount,
  double benefitValue = 50,
  int usageCount = 3,
  int? usageLimit,
  bool firstVisitOnly = true,
}) {
  return MerchantAffiliateCode(
    id: id,
    merchantId: 'shop-1',
    affiliateId: 'aff-1',
    code: 'AFI-ANA-7K2P',
    normalizedCode: 'AFI-ANA-7K2P',
    benefitType: benefitType,
    benefitValue: benefitValue,
    status: status,
    usageCount: usageCount,
    usageLimit: usageLimit,
    firstVisitOnly: firstVisitOnly,
    updatedAt: DateTime(2025, 3, 4, 10, 30),
  );
}

MerchantAffiliate sampleAffiliate({
  String id = 'aff-1',
  String name = 'Ana Silva',
  AffiliateStatus status = AffiliateStatus.active,
  AffiliateMerchantStatus linkStatus = AffiliateMerchantStatus.active,
  MerchantAffiliateCode? code,
  String? phone = '+258841234567',
}) {
  return MerchantAffiliate(
    id: id,
    merchantId: 'shop-1',
    name: name,
    firstName: name.split(' ').first,
    status: status,
    linkStatus: linkStatus,
    phone: phone,
    phoneLast4: '4567',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 3, 4, 10, 30),
    code: code ?? sampleCode(),
  );
}

AffiliateMetricsSummary sampleMetrics({
  int attempts = 8,
  int confirmed = 4,
  int returned = 2,
  int pendingCount = 3,
  int pendingPoints = 300,
  int approvedCount = 1,
  int approvedPoints = 100,
  double conversionRate = 0.5,
  bool truncated = false,
  DateTime? lastActivityAt,
}) {
  return AffiliateMetricsSummary(
    merchantId: 'shop-1',
    uniqueValidationAttempts: attempts,
    confirmedAttributions: confirmed,
    returnedCustomers: returned,
    pendingRewardCount: pendingCount,
    pendingRewardPoints: pendingPoints,
    approvedRewardCount: approvedCount,
    approvedRewardPoints: approvedPoints,
    conversionRate: conversionRate,
    truncated: truncated,
    lastActivityAt: lastActivityAt,
  );
}

MerchantAffiliateReward sampleReward({
  String id = 'reward-1',
  AffiliateRewardStatus status = AffiliateRewardStatus.pending,
  double value = 100,
}) {
  return MerchantAffiliateReward(
    id: id,
    merchantId: 'shop-1',
    affiliateId: 'aff-1',
    type: AffiliateRewardType.firstQualifyingSale,
    valueType: AffiliateRewardValueType.points,
    value: value,
    status: status,
    createdAt: DateTime(2025, 3, 1, 9),
  );
}
