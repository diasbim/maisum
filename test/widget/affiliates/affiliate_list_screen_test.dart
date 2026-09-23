import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/affiliates/data/affiliate_dao.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/domain/offline_referral.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_list_screen.dart';

import 'affiliate_test_support.dart';

/// The list is the screen an owner opens to answer one question: is anyone
/// actually bringing me customers? Every state below exists because the wrong
/// answer to that question is expensive — an empty list that looks like a
/// failure, or a truncated list that looks complete.
void main() {
  testWidgets('keeps the layout while it waits', (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: const AffiliateListView(items: []),
      delay: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('affiliate-skeleton')), findsOneWidget);
    // The action never disappears while loading; it is the reason the owner
    // came here, and a page that swaps it for a spinner reads as broken.
    expect(find.byKey(const Key('affiliate-add-button')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('offers the one useful action when there is nobody yet',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: const AffiliateListView(items: []),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-empty-state')), findsOneWidget);
    expect(find.text('Ainda não tem afiliados'), findsOneWidget);
    expect(find.text('Adicionar afiliado'), findsWidgets);
  });

  testWidgets('shows a retryable error rather than an empty page',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listError: StateError('boom'),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-error-state')), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    gateway.listError = null;
    gateway.listView = AffiliateListView(
      items: <AffiliateListItem>[
        AffiliateListItem(affiliate: sampleAffiliate()),
      ],
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Silva'), findsOneWidget);
  });

  testWidgets('a card carries the four facts the owner scans for',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(
            affiliate: sampleAffiliate(),
            referredCustomers: 3,
            pendingRewards: 2,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.text('+258841234567'), findsOneWidget);
    expect(find.text('Ativo'), findsOneWidget);
    expect(find.textContaining('Clientes indicados'), findsOneWidget);
    expect(find.textContaining('Recompensas pendentes'), findsOneWidget);
    expect(find.textContaining('Última atividade'), findsOneWidget);
  });

  testWidgets('an incomplete reward count is shown as unknown', (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        rewardsUnavailable: true,
        items: <AffiliateListItem>[
          AffiliateListItem(
            affiliate: sampleAffiliate(),
            referredCustomers: 3,
            pendingRewards: null,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.textContaining('A contagem fica por confirmar'), findsOneWidget);
    expect(
      find.textContaining('Recompensas pendentes: —', findRichText: true),
      findsOneWidget,
    );
    expect(
        find.bySemanticsLabel(RegExp('Recompensas pendentes: por confirmar')),
        findsOneWidget);
  });

  testWidgets('a card reads as one labelled button to a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(
            affiliate: sampleAffiliate(),
            referredCustomers: 3,
            pendingRewards: 2,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    // One label carrying every fact, rather than a handful of loose strings a
    // screen reader would read out of order.
    expect(
      find.bySemanticsLabel(RegExp(
        r'Afiliado Ana Silva\. Estado: Ativo\. Clientes indicados: 3\. '
        r'Recompensas pendentes: 2\.',
      )),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a staff member sees the number masked', (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(affiliate: sampleAffiliate()),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway, isOwner: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+258841234567'), findsNothing);
    expect(find.textContaining('4567'), findsOneWidget);
  });

  testWidgets('a staff member cannot start a creation the server would refuse',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: const AffiliateListView(items: []),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway, isOwner: false),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-add-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('says so when the list is only part of the answer',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(affiliate: sampleAffiliate()),
        ],
        truncated: true,
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-truncated-banner')), findsOneWidget);
  });

  testWidgets('offline keeps the add button, with an honest warning',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(affiliate: sampleAffiliate()),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway, online: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-offline-notice')), findsOneWidget);
    expect(find.textContaining('código provisório'), findsOneWidget);
    // Adding offline writes a provisional record and queues the real one, so
    // the button stays usable: telling an owner to come back later would lose
    // the affiliate they have in front of them.
    final button = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-add-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a cashier still cannot add an affiliate offline',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(affiliate: sampleAffiliate()),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway, online: false, isOwner: false),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-add-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a provisional affiliate says it is not confirmed yet',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(affiliate: sampleAffiliate()),
        ],
      ),
    );
    final offline = FakeAffiliateOfflineGateway(
      provisionalList: <ProvisionalAffiliate>[
        sampleProvisionalAffiliate(displayName: 'Beatriz Cossa'),
      ],
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(
          gateway: gateway,
          online: false,
          offlineGateway: offline,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('affiliate-provisional-section')),
      findsOneWidget,
    );
    expect(find.text('Beatriz Cossa'), findsOneWidget);
    expect(find.text('Por confirmar'), findsOneWidget);
    expect(find.textContaining('LOCAL-ANA-4F2A91'), findsOneWidget);
  });

  testWidgets('a refused offline affiliate keeps its row and says why',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(affiliate: sampleAffiliate()),
        ],
      ),
    );
    final offline = FakeAffiliateOfflineGateway(
      provisionalList: <ProvisionalAffiliate>[
        sampleProvisionalAffiliate(
          displayName: 'Beatriz Cossa',
          syncStatus: AffiliateSyncStatus.rejected,
          lastSyncError: 'Este afiliado já está ligado a este negócio.',
        ),
      ],
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway, offlineGateway: offline),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recusado'), findsOneWidget);
    expect(
      find.text('Este afiliado já está ligado a este negócio.'),
      findsOneWidget,
    );
  });

  testWidgets('an inactive affiliate is told apart by more than colour',
      (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(
            affiliate: sampleAffiliate(
              linkStatus: AffiliateMerchantStatus.inactive,
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateListScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inativo'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('survives a 200% text scale without overflowing', (tester) async {
    final gateway = FakeAffiliateGateway(
      listView: AffiliateListView(
        items: <AffiliateListItem>[
          AffiliateListItem(
            affiliate: sampleAffiliate(),
            referredCustomers: 3,
            pendingRewards: 2,
          ),
        ],
      ),
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapScreen(
        textScaled(const AffiliateListScreen(), 2),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ana Silva'), findsOneWidget);
  });
}
