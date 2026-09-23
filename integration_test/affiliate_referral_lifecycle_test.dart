import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:maisum/app/providers.dart';
import 'package:maisum/features/affiliates/data/affiliate_repository.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/affiliate_reward.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_detail_screen.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_list_screen.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_metrics_screen.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_rewards_screen.dart';
import 'package:maisum/features/affiliates/providers/affiliate_providers.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';

/// Renderer smoke of the affiliate surfaces.
///
/// The widget tests already assert this behaviour under the fake async zone,
/// and `test/integration/affiliates/affiliate_referral_lifecycle_test.dart`
/// asserts the whole lifecycle against real SQLite. Under `flutter test`, this
/// validates the integration binding and rendered surfaces without credentials.
/// A separate run with `flutter test -d <AVD>` is still required to prove real
/// Android font metrics and density.
///
/// It stands up no Firebase, reads no credentials and makes no network call:
/// every answer comes from the in-memory gateway below, which is what lets it
/// run headlessly or on an AVD with `flutter test integration_test/...`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('The affiliate list on device', () {
    testWidgets('shows a card an owner can read at a glance', (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateListScreen(),
          _gateway(listView: _listWith(_affiliate())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana Silva'), findsWidgets);
      expect(find.text('Ativo'), findsWidgets);
      // The internal identity never reaches a screen.
      expect(find.textContaining('aff-1'), findsNothing);
      expect(find.textContaining('code-1'), findsNothing);
      // And neither does a stored enum.
      for (final raw in <String>['ACTIVE', 'FIXED_AMOUNT', 'PENDING']) {
        expect(find.text(raw), findsNothing, reason: 'raw "$raw" was painted');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty list offers the one action that helps',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateListScreen(),
          _gateway(listView: const AffiliateListView(items: [])),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('affiliate-empty-state')), findsOneWidget);
      expect(find.text('Adicionar afiliado'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long name at 200% text does not overflow a real screen',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateListScreen(),
          _gateway(
            listView: _listWith(
              _affiliate(name: 'Guilhermina Nhamirre da Conceição Mabjaia'),
            ),
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('The affiliate detail on device', () {
    testWidgets('shows the code, the benefit and the numbers behind it',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateDetailScreen(affiliateId: 'aff-1'),
          _gateway(
            detail: AffiliateDetailSnapshot(
              affiliate: _affiliate(),
              metrics: _metrics(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AFI-ANA-7K2P'), findsWidgets);
      expect(find.textContaining('Partilhar'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an offline owner still sees the buttons, with the reason',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateDetailScreen(affiliateId: 'aff-1'),
          _gateway(
            detail: AffiliateDetailSnapshot(
              affiliate: _affiliate(),
              metrics: _metrics(),
            ),
          ),
          online: false,
        ),
      );
      await tester.pumpAndSettle();

      // Offline explains what cannot be done rather than hiding the control.
      expect(find.textContaining('ligação'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Rewards and metrics on device', () {
    testWidgets('a pending reward is described in Portuguese', (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateRewardsScreen(),
          _gateway(
            rewards: AffiliatePage<MerchantAffiliateReward>(
              items: <MerchantAffiliateReward>[_reward()],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final raw in <String>[
        'PENDING',
        'FIRST_QUALIFYING_SALE',
        'POINTS'
      ]) {
        expect(find.text(raw), findsNothing, reason: 'raw "$raw" was painted');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the metrics screen paints its numbers without overflowing',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const AffiliateMetricsScreen(),
          _gateway(metrics: _metrics()),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

/* --------------------------------------------------------------- fixtures */

Widget _app(
  Widget screen,
  AffiliateGateway gateway, {
  bool online = true,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: <Override>[
      affiliateGatewayProvider.overrideWithValue(gateway),
      isOwnerUserProvider.overrideWith((ref) async => true),
      isOnlineProvider.overrideWith((ref) => Stream<bool>.value(online)),
      affiliateOfflineGatewayProvider.overrideWithValue(null),
      authControllerProvider.overrideWith(_SmokeAuthController.new),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: screen,
        ),
      ),
    ),
  );
}

class _SmokeAuthController extends AuthController {
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

AffiliateListView _listWith(MerchantAffiliate affiliate) {
  return AffiliateListView(
    items: <AffiliateListItem>[AffiliateListItem(affiliate: affiliate)],
  );
}

MerchantAffiliate _affiliate({String name = 'Ana Silva'}) {
  return MerchantAffiliate(
    id: 'aff-1',
    merchantId: 'shop-1',
    name: name,
    firstName: name.split(' ').first,
    status: AffiliateStatus.active,
    linkStatus: AffiliateMerchantStatus.active,
    phone: '+258841234567',
    phoneLast4: '4567',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 3, 4, 10, 30),
    code: MerchantAffiliateCode(
      id: 'code-1',
      merchantId: 'shop-1',
      affiliateId: 'aff-1',
      code: 'AFI-ANA-7K2P',
      normalizedCode: 'AFI-ANA-7K2P',
      benefitType: ReferralBenefitType.fixedAmount,
      benefitValue: 50,
      status: AffiliateCodeStatus.active,
      usageCount: 3,
      firstVisitOnly: true,
      updatedAt: DateTime(2025, 3, 4, 10, 30),
    ),
  );
}

AffiliateMetricsSummary _metrics() {
  return const AffiliateMetricsSummary(
    merchantId: 'shop-1',
    uniqueValidationAttempts: 8,
    confirmedAttributions: 4,
    returnedCustomers: 2,
    pendingRewardCount: 3,
    pendingRewardPoints: 300,
    approvedRewardCount: 1,
    approvedRewardPoints: 100,
    conversionRate: 0.5,
  );
}

MerchantAffiliateReward _reward() {
  return MerchantAffiliateReward(
    id: 'reward-1',
    merchantId: 'shop-1',
    affiliateId: 'aff-1',
    type: AffiliateRewardType.firstQualifyingSale,
    valueType: AffiliateRewardValueType.points,
    value: 100,
    status: AffiliateRewardStatus.pending,
    createdAt: DateTime(2025, 3, 1, 9),
  );
}

/// The API, answering from memory. No Firebase, no token, no network.
class _SmokeGateway implements AffiliateGateway {
  _SmokeGateway({this.listView, this.detail, this.rewards, this.metrics});

  final AffiliateListView? listView;
  final AffiliateDetailSnapshot? detail;
  final AffiliatePage<MerchantAffiliateReward>? rewards;
  final AffiliateMetricsSummary? metrics;

  T _need<T>(T? value, String what) {
    if (value == null) throw StateError('the smoke test staged no $what');
    return value;
  }

  @override
  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
  }) async {
    final view = _need(listView, 'list');
    return AffiliatePage<MerchantAffiliate>(
      items: <MerchantAffiliate>[
        for (final item in view.items) item.affiliate,
      ],
    );
  }

  @override
  Future<AffiliateListView> loadAffiliateList({String? status}) async =>
      _need(listView, 'list');

  @override
  Future<MerchantAffiliate> getAffiliate(String affiliateId) async =>
      _need(detail, 'detail').affiliate;

  @override
  Future<AffiliateDetailSnapshot> loadAffiliateDetail(
    String affiliateId,
  ) async =>
      _need(detail, 'detail');

  @override
  Future<MerchantAffiliate> createAffiliate(AffiliateDraft draft) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliate> setAffiliateActive({
    required String affiliateId,
    required bool active,
  }) async =>
      _need(detail, 'detail').affiliate;

  @override
  Future<MerchantAffiliateCode> updateCode(AffiliateCodeEdit edit) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliateCode> setCodeEnabled({
    required String codeId,
    required bool enabled,
  }) =>
      throw UnimplementedError();

  @override
  Future<AffiliatePage<MerchantAffiliateReward>> listRewards({
    String? affiliateId,
    String? status,
  }) async =>
      _need(rewards, 'rewards');

  @override
  Future<MerchantAffiliateReward> approveReward(String rewardId) async =>
      _need(rewards, 'rewards').items.first;

  @override
  Future<MerchantAffiliateReward> cancelReward(String rewardId) async =>
      _need(rewards, 'rewards').items.first;

  @override
  Future<AffiliateMetricsSummary> merchantMetrics() async =>
      _need(metrics, 'metrics');
}

AffiliateGateway _gateway({
  AffiliateListView? listView,
  AffiliateDetailSnapshot? detail,
  AffiliatePage<MerchantAffiliateReward>? rewards,
  AffiliateMetricsSummary? metrics,
}) {
  return _SmokeGateway(
    listView: listView,
    detail: detail,
    rewards: rewards,
    metrics: metrics,
  );
}
