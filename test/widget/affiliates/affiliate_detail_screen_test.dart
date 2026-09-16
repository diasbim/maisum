import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_detail_screen.dart';

import 'affiliate_test_support.dart';

/// One affiliate's page: the code, the numbers, and the two decisions.
///
/// The decisions are the reason the screen exists, and both are owner-only and
/// online-only. What is tested here is that neither disappears when it is
/// unavailable — an owner offline should see that the action exists and is
/// waiting, not a page that quietly lost a button.
AffiliateDetailSnapshot _snapshot({
  MerchantAffiliate? affiliate,
  AffiliateMetricsSummary? metrics,
  bool truncated = false,
}) {
  return AffiliateDetailSnapshot(
    affiliate: affiliate ?? sampleAffiliate(),
    metrics: metrics ?? sampleMetrics(),
    truncated: truncated,
  );
}

void main() {
  testWidgets('shows the code, the benefit and the four numbers',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(detail: _snapshot());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.text('AFI-ANA-7K2P'), findsOneWidget);
    expect(find.textContaining('50 MT de desconto'), findsOneWidget);
    expect(find.text('Clientes indicados'), findsOneWidget);
    expect(find.text('Clientes que voltaram'), findsOneWidget);
    expect(find.text('Recompensas pendentes'), findsOneWidget);
    expect(find.text('Recompensas aprovadas'), findsOneWidget);
  });

  testWidgets('deactivating asks the server to deactivate', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(detail: _snapshot());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Desativar afiliado'), findsOneWidget);
    await tapControl(tester, find.byKey(const Key('affiliate-link-toggle')));
    await tester.pumpAndSettle();

    expect(gateway.linkChanges, hasLength(1));
    expect(gateway.linkChanges.single.affiliateId, 'aff-1');
    expect(gateway.linkChanges.single.active, isFalse);
  });

  testWidgets('an inactive affiliate is offered reactivation instead',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      detail: _snapshot(
        affiliate: sampleAffiliate(
          linkStatus: AffiliateMerchantStatus.inactive,
        ),
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reativar afiliado'), findsOneWidget);
    await tapControl(tester, find.byKey(const Key('affiliate-link-toggle')));
    await tester.pumpAndSettle();

    expect(gateway.linkChanges.single.active, isTrue);
  });

  testWidgets('a staff member sees the action and the reason it is closed',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(detail: _snapshot());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway, isOwner: false),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-link-toggle')),
    );
    expect(toggle.onPressed, isNull);
    expect(
      find.textContaining('Só o responsável do negócio pode ativar'),
      findsOneWidget,
    );
    final share = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-detail-share-button')),
    );
    expect(share.onPressed, isNull);
  });

  testWidgets('sharing is refused for a disabled code, with the reason',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      detail: _snapshot(
        affiliate: sampleAffiliate(
          code: sampleCode(status: AffiliateCodeStatus.disabled),
        ),
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    final share = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-detail-share-button')),
    );
    expect(share.onPressed, isNull);
    expect(find.textContaining('A partilha fica desativada'), findsOneWidget);
  });

  testWidgets('flags partial data instead of presenting it as complete',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(detail: _snapshot(truncated: true));

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-truncated-banner')), findsOneWidget);
  });

  testWidgets('a failed load is retryable', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(detailError: StateError('boom'));

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-error-state')), findsOneWidget);

    gateway.detailError = null;
    gateway.detail = _snapshot();
    await tapControl(tester, find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Silva'), findsOneWidget);
  });

  testWidgets('offline keeps the buttons visible and explains', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(detail: _snapshot());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateDetailScreen(affiliateId: 'aff-1'),
        affiliateOverrides(gateway: gateway, online: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-link-toggle')), findsOneWidget);
    final toggle = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-link-toggle')),
    );
    expect(toggle.onPressed, isNull);
    expect(find.textContaining('só é possível online'), findsOneWidget);
  });
}
