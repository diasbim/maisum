import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/affiliates/domain/affiliate_reward.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_rewards_screen.dart';

import 'affiliate_test_support.dart';

/// The approval queue.
///
/// Approving is an owner's decision and it is recorded by the server, so it is
/// the one action in this feature that genuinely cannot happen offline. The
/// tests hold both halves of that: the button never vanishes, and it is never
/// live when the call would fail.
void main() {
  testWidgets('lists a pending reward with both decisions', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: AffiliatePage<MerchantAffiliateReward>(
        items: <MerchantAffiliateReward>[sampleReward()],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('100 pontos'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
    expect(find.text('Aprovar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('approving sends the reward id', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: AffiliatePage<MerchantAffiliateReward>(
        items: <MerchantAffiliateReward>[sampleReward()],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tapControl(tester, find.byKey(const Key('reward-approve-reward-1')));
    await tester.pumpAndSettle();

    expect(gateway.approvedRewardIds, <String>['reward-1']);
    expect(gateway.cancelledRewardIds, isEmpty);
  });

  testWidgets('cancelling sends the reward id', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: AffiliatePage<MerchantAffiliateReward>(
        items: <MerchantAffiliateReward>[sampleReward()],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tapControl(tester, find.byKey(const Key('reward-cancel-reward-1')));
    await tester.pumpAndSettle();

    expect(gateway.cancelledRewardIds, <String>['reward-1']);
  });

  testWidgets('offline disables the decision and says why', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: AffiliatePage<MerchantAffiliateReward>(
        items: <MerchantAffiliateReward>[sampleReward()],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway, online: false),
      ),
    );
    await tester.pumpAndSettle();

    final approve = tester.widget<MaisUmButton>(
      find.byKey(const Key('reward-approve-reward-1')),
    );
    expect(approve.onPressed, isNull);
    expect(
      find.text('Sem ligação: a decisão fica para quando houver rede.'),
      findsOneWidget,
    );
    expect(gateway.approvedRewardIds, isEmpty);
  });

  testWidgets('a staff member sees the queue but cannot decide',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: AffiliatePage<MerchantAffiliateReward>(
        items: <MerchantAffiliateReward>[sampleReward()],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway, isOwner: false),
      ),
    );
    await tester.pumpAndSettle();

    final approve = tester.widget<MaisUmButton>(
      find.byKey(const Key('reward-approve-reward-1')),
    );
    expect(approve.onPressed, isNull);
    expect(
      find.text('Só o responsável do negócio pode decidir.'),
      findsOneWidget,
    );
  });

  testWidgets('an approved reward offers no decision at all', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: AffiliatePage<MerchantAffiliateReward>(
        items: <MerchantAffiliateReward>[
          sampleReward(status: AffiliateRewardStatus.approved),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aprovada'), findsOneWidget);
    expect(find.byKey(const Key('reward-approve-reward-1')), findsNothing);
  });

  testWidgets('an empty queue explains what would fill it', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      rewards: const AffiliatePage<MerchantAffiliateReward>(items: []),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-rewards-empty')), findsOneWidget);
  });

  testWidgets('a failed load is retryable', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(rewardsError: StateError('boom'));

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateRewardsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-error-state')), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}
