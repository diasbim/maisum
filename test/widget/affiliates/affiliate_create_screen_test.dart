import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_create_screen.dart';

import 'affiliate_test_support.dart';

/// Adding an affiliate ends in a code, and the code is the product.
///
/// The tests that matter are about what happens after the server answers: the
/// owner has to see the code that was actually minted, and sharing has to be
/// impossible for a code that is not yet usable — a shared code that is refused
/// at the counter costs the affiliate's trust, not the shop's.
void main() {
  testWidgets('sends what the owner typed, with the defaults intact',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(created: sampleAffiliate());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('affiliate-name-field')),
      'Ana Silva',
    );
    await tester.enterText(
      find.byKey(const Key('affiliate-phone-field')),
      '841234567',
    );
    await tapControl(tester, find.byKey(const Key('affiliate-create-submit')));
    await tester.pumpAndSettle();

    final draft = gateway.lastDraft;
    expect(draft, isNotNull);
    expect(draft!.name, 'Ana Silva');
    expect(draft.phone, '+258841234567');
    expect(draft.benefitType, ReferralBenefitType.fixedAmount.storageValue);
    expect(draft.benefitValue, 50);
    expect(draft.firstVisitOnly, isTrue);
    expect(draft.usageLimit, isNull);
    expect(draft.expiresAt, isNotNull);
  });

  testWidgets('refuses an invalid number instead of letting the server do it',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(created: sampleAffiliate());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('affiliate-name-field')),
      'Ana Silva',
    );
    await tester.enterText(
      find.byKey(const Key('affiliate-phone-field')),
      '12345',
    );
    await tapControl(tester, find.byKey(const Key('affiliate-create-submit')));
    await tester.pumpAndSettle();

    expect(gateway.lastDraft, isNull);
  });

  testWidgets('shows the confirmed code and offers to share it',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(created: sampleAffiliate());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('affiliate-name-field')),
      'Ana Silva',
    );
    await tester.enterText(
      find.byKey(const Key('affiliate-phone-field')),
      '841234567',
    );
    await tapControl(tester, find.byKey(const Key('affiliate-create-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-created-panel')), findsOneWidget);
    expect(find.text('AFI-ANA-7K2P'), findsOneWidget);

    final share = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-share-button')),
    );
    expect(share.onPressed, isNotNull);
  });

  testWidgets('withholds sharing for a code that is not usable yet',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      created: sampleAffiliate(
        code: sampleCode(status: AffiliateCodeStatus.disabled),
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('affiliate-name-field')),
      'Ana Silva',
    );
    await tester.enterText(
      find.byKey(const Key('affiliate-phone-field')),
      '841234567',
    );
    await tapControl(tester, find.byKey(const Key('affiliate-create-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-share-button')), findsNothing);
    expect(
      find.textContaining('ainda não está confirmado'),
      findsOneWidget,
    );
  });

  testWidgets('a staff member is told why the form is closed to them',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(created: sampleAffiliate());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(gateway: gateway, isOwner: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Só o responsável do negócio'),
      findsOneWidget,
    );
    final submit = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-create-submit')),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('offline creates a provisional code that cannot be shared',
      (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(created: sampleAffiliate());
    final offline = FakeAffiliateOfflineGateway(
      provisional: sampleProvisionalAffiliate(),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(
          gateway: gateway,
          online: false,
          offlineGateway: offline,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('affiliate-create-offline-notice')),
      findsOneWidget,
    );
    final submit = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-create-submit')),
    );
    // Offline is no longer a reason to refuse: the record is written here and
    // the server is asked when there is a server to ask.
    expect(submit.onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const Key('affiliate-name-field')),
      'Ana Silva',
    );
    await tester.enterText(
      find.byKey(const Key('affiliate-phone-field')),
      '841234567',
    );
    await tapControl(tester, find.byKey(const Key('affiliate-create-submit')));
    await tester.pumpAndSettle();

    // Nothing reached the API; the draft went to the local path instead.
    expect(gateway.lastDraft, isNull);
    expect(offline.drafts, hasLength(1));
    expect(offline.drafts.single.name, 'Ana Silva');

    expect(
      find.byKey(const Key('affiliate-provisional-panel')),
      findsOneWidget,
    );
    final code = tester
        .widget<SelectableText>(
          find.byKey(const Key('affiliate-provisional-code')),
        )
        .data!;
    // A provisional code is never in the AFI- namespace the server owns, so it
    // cannot be mistaken for one that works at a counter.
    expect(code, startsWith('LOCAL-'));
    expect(code, isNot(startsWith('AFI-')));

    final share = tester.widget<MaisUmButton>(
      find.byKey(const Key('affiliate-share-button-disabled')),
    );
    expect(share.onPressed, isNull);
    expect(find.byKey(const Key('affiliate-share-button')), findsNothing);
    expect(find.textContaining('não pode ser partilhado'), findsOneWidget);
  });

  testWidgets('keeps the form when the server refuses', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      createError: StateError('conflito'),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateCreateScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('affiliate-name-field')),
      'Ana Silva',
    );
    await tester.enterText(
      find.byKey(const Key('affiliate-phone-field')),
      '841234567',
    );
    await tapControl(tester, find.byKey(const Key('affiliate-create-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('affiliate-created-panel')), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('affiliate-name-field')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'Ana Silva',
    );
  });

  testWidgets('holds together at a 200% text scale', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(created: sampleAffiliate());

    await tester.pumpWidget(
      wrapScreen(
        textScaled(const AffiliateCreateScreen(), 2),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
