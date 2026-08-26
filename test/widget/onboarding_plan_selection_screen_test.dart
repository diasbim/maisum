import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/app_colors.dart';
import 'package:maisum/features/subscription/data/firestore_plan_offers.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_snapshot.dart';
import 'package:maisum/features/subscription/domain/subscription_status.dart';
import 'package:maisum/features/subscription/domain/usage_quota.dart';
import 'package:maisum/features/subscription/presentation/onboarding_plan_selection_screen.dart';
import 'package:maisum/features/subscription/services/remote_config_reader.dart';

class _FakeSubscriptionSnapshotController
    extends SubscriptionSnapshotController {
  _FakeSubscriptionSnapshotController(this.snapshot);

  final SubscriptionSnapshot snapshot;

  @override
  Future<SubscriptionSnapshot> build() async => snapshot;

  @override
  Future<void> refresh() async {}
}

Widget _buildScreen({
  Plan selectedPlan = Plan.starter,
  List<PlanOffer>? planOffers,
}) {
  final snapshot = SubscriptionSnapshot(
    plan: selectedPlan,
    status: SubscriptionStatus.active,
    entitlements: const [],
    flags: const [],
    usageBalances: const [],
    whatsappQuota: UsageQuotaSummary(
      metricKey: 'whatsapp_messages',
      used: 0,
      limit: 1200,
      resetAt: DateTime(2099, 1, 1),
    ),
  );

  final offers = planOffers ??
      <PlanOffer>[
        const PlanOffer(
          plan: Plan.free,
          code: 'free',
          displayName: 'FREE',
          priceCents: 0,
          currency: 'MZN',
          billingInterval: 'monthly',
          features: {'whatsapp_automation'},
          whatsappMonthlyLimit: 150,
          sortOrder: 1,
        ),
        const PlanOffer(
          plan: Plan.starter,
          code: 'starter',
          displayName: 'STARTER',
          priceCents: 9900,
          currency: 'MZN',
          billingInterval: 'monthly',
          features: {'customers', 'loyalty', 'rewards'},
          whatsappMonthlyLimit: 1200,
          sortOrder: 2,
        ),
        const PlanOffer(
          plan: Plan.business,
          code: 'business',
          displayName: 'BUSINESS',
          priceCents: 39900,
          currency: 'MZN',
          billingInterval: 'monthly',
          features: {'campaigns', 'reports'},
          whatsappMonthlyLimit: 6000,
          sortOrder: 3,
        ),
      ];

  return ProviderScope(
    overrides: [
      subscriptionSnapshotProvider.overrideWith(
        () => _FakeSubscriptionSnapshotController(snapshot),
      ),
      onboardingPlanOffersProvider.overrideWith((ref) async => offers),
    ],
    child: const MaterialApp(home: OnboardingPlanSelectionScreen()),
  );
}

Widget _buildRoutedScreen({required List<PlanOffer> planOffers}) {
  final snapshot = SubscriptionSnapshot(
    plan: Plan.starter,
    status: SubscriptionStatus.active,
    entitlements: const [],
    flags: const [],
    usageBalances: const [],
    whatsappQuota: UsageQuotaSummary(
      metricKey: 'whatsapp_messages',
      used: 0,
      limit: 1200,
      resetAt: DateTime(2099, 1, 1),
    ),
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const OnboardingPlanSelectionScreen(),
      ),
      GoRoute(
        path: '/feature-upsell',
        builder: (_, __) => const Scaffold(
            body: Center(child: Text('Business contact opened'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      subscriptionSnapshotProvider.overrideWith(
        () => _FakeSubscriptionSnapshotController(snapshot),
      ),
      onboardingPlanOffersProvider.overrideWith((ref) async => planOffers),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  test('uses the active catalog and only falls back when it is empty',
      () async {
    var fallbackRequested = false;
    const activeOffer = PlanOffer(
      plan: Plan.starter,
      code: 'starter',
      displayName: 'STARTER',
      priceCents: 9900,
      currency: 'MZN',
      billingInterval: 'monthly',
      features: {'customers'},
      whatsappMonthlyLimit: 1200,
      sortOrder: 1,
    );

    final catalogOffers = await resolveOnboardingPlanOffers(
      fetchActiveOffers: () async => [activeOffer],
      getPricingOverride: (_) async {
        fallbackRequested = true;
        return null;
      },
    );

    expect(catalogOffers, [activeOffer]);
    expect(fallbackRequested, isFalse);

    final fallbackOffers = await resolveOnboardingPlanOffers(
      fetchActiveOffers: () async => const [],
      getPricingOverride: (_) async {
        fallbackRequested = true;
        return null;
      },
    );

    expect(fallbackRequested, isTrue);
    expect(fallbackOffers, isNotEmpty);
    expect(fallbackOffers.every((offer) => offer.currency == 'MZN'), isTrue);
    final fallbackFree =
        fallbackOffers.singleWhere((offer) => offer.plan == Plan.free);
    expect(fallbackFree.priceCents, 0);
    expect(canConfirmOnboardingPlanOffer(fallbackFree), isTrue);
  });

  test('fallback retains a valid configured currency and otherwise uses MZN',
      () async {
    final offers = await buildOnboardingFallbackPlanOffers(
      getPricingOverride: (planCode) async {
        if (planCode == Plan.starter.code) {
          return const PricingOverride(currency: 'usd', priceCents: 1200);
        }
        if (planCode == Plan.pro.code) {
          return const PricingOverride(currency: 'invalid', priceCents: 3400);
        }
        return const PricingOverride(currency: 'invalid');
      },
    );

    expect(
      offers.singleWhere((offer) => offer.plan == Plan.starter).currency,
      'USD',
    );
    expect(
      offers
          .where((offer) => offer.plan != Plan.starter)
          .every((offer) => offer.currency == 'MZN'),
      isTrue,
    );
    expect(
      offers.singleWhere((offer) => offer.plan == Plan.pro).priceCents,
      isNull,
    );
  });

  test('only confirms offers with trustworthy paid pricing', () {
    const freeOffer = PlanOffer(
      plan: Plan.free,
      code: 'free',
      displayName: 'FREE',
      priceCents: 0,
      currency: 'MZN',
      billingInterval: 'monthly',
      features: {},
      whatsappMonthlyLimit: 150,
      sortOrder: 1,
    );
    const businessOffer = PlanOffer(
      plan: Plan.business,
      code: 'business',
      displayName: 'BUSINESS',
      priceCents: 39900,
      currency: 'MZN',
      billingInterval: 'monthly',
      features: {},
      whatsappMonthlyLimit: 6000,
      sortOrder: 1,
    );
    final untrustedPaidOffers = [
      const PlanOffer(
        plan: Plan.starter,
        code: 'starter',
        displayName: 'STARTER',
        priceCents: null,
        currency: 'MZN',
        billingInterval: 'monthly',
        features: {},
        whatsappMonthlyLimit: 1200,
        sortOrder: 1,
      ),
      const PlanOffer(
        plan: Plan.starter,
        code: 'starter',
        displayName: 'STARTER',
        priceCents: 0,
        currency: 'MZN',
        billingInterval: 'monthly',
        features: {},
        whatsappMonthlyLimit: 1200,
        sortOrder: 1,
      ),
      const PlanOffer(
        plan: Plan.starter,
        code: 'starter',
        displayName: 'STARTER',
        priceCents: -1,
        currency: 'MZN',
        billingInterval: 'monthly',
        features: {},
        whatsappMonthlyLimit: 1200,
        sortOrder: 1,
      ),
      const PlanOffer(
        plan: Plan.starter,
        code: 'starter',
        displayName: 'STARTER',
        priceCents: 1200,
        currency: 'invalid',
        billingInterval: 'monthly',
        features: {},
        whatsappMonthlyLimit: 1200,
        sortOrder: 1,
      ),
      const PlanOffer(
        plan: Plan.starter,
        code: 'starter',
        displayName: 'STARTER',
        priceCents: 1200,
        currency: 'MZN',
        billingInterval: 'quarterly',
        features: {},
        whatsappMonthlyLimit: 1200,
        sortOrder: 1,
      ),
    ];

    expect(canConfirmOnboardingPlanOffer(freeOffer), isTrue);
    expect(canConfirmOnboardingPlanOffer(businessOffer), isFalse);
    for (final offer in untrustedPaidOffers) {
      expect(canConfirmOnboardingPlanOffer(offer), isFalse);
    }
  });

  testWidgets('shows starter highlight badge and selected state',
      (tester) async {
    await tester.pumpWidget(_buildScreen(selectedPlan: Plan.starter));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan_badge_starter')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan_selected_starter')), findsOneWidget);
  });

  testWidgets('renders only plans supplied by the active catalog',
      (tester) async {
    const starterOffer = PlanOffer(
      plan: Plan.starter,
      code: 'starter',
      displayName: 'STARTER',
      priceCents: 9900,
      currency: 'MZN',
      billingInterval: 'monthly',
      features: {'customers'},
      whatsappMonthlyLimit: 1200,
      sortOrder: 1,
    );
    await tester.pumpWidget(_buildScreen(planOffers: [starterOffer]));
    await tester.pumpAndSettle();

    expect(find.text('STARTER'), findsOneWidget);
    expect(find.text('FREE'), findsNothing);
    expect(find.text('BUSINESS'), findsNothing);
    expect(find.textContaining('MZN 99', findRichText: true), findsOneWidget);
  });

  testWidgets('empty-catalog fallback Free remains confirmable, not contact',
      (tester) async {
    final fallbackOffers = await resolveOnboardingPlanOffers(
      fetchActiveOffers: () async => const [],
      getPricingOverride: (_) async => null,
    );
    final fallbackFree =
        fallbackOffers.singleWhere((offer) => offer.plan == Plan.free);

    await tester.pumpWidget(_buildScreen(planOffers: [fallbackFree]));
    await tester.pumpAndSettle();

    expect(find.text('Começar grátis'), findsOneWidget);
    expect(find.text('Falar Connosco'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar plano'), findsOneWidget);
  });

  testWidgets('selecting a plan waits for explicit confirmation',
      (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Começar grátis'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan_selected_free')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar plano'), findsOneWidget);
    expect(find.text('Plano confirmado'), findsNothing);
  });

  testWidgets('Business contact opens the existing contact flow',
      (tester) async {
    const businessOffer = PlanOffer(
      plan: Plan.business,
      code: 'business',
      displayName: 'BUSINESS',
      priceCents: null,
      currency: 'MZN',
      billingInterval: 'monthly',
      features: {'reports'},
      whatsappMonthlyLimit: 6000,
      sortOrder: 1,
    );
    await tester.pumpWidget(_buildRoutedScreen(planOffers: [businessOffer]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Falar Connosco').first);
    await tester.pumpAndSettle();

    expect(find.text('Business contact opened'), findsOneWidget);
    expect(find.text('Plano confirmado'), findsNothing);
  });

  testWidgets('an untrusted paid offer opens contact instead of confirmation',
      (tester) async {
    const starterOffer = PlanOffer(
      plan: Plan.starter,
      code: 'starter',
      displayName: 'STARTER',
      priceCents: 0,
      currency: 'MZN',
      billingInterval: 'monthly',
      features: {'customers'},
      whatsappMonthlyLimit: 1200,
      sortOrder: 1,
    );
    await tester.pumpWidget(_buildRoutedScreen(planOffers: [starterOffer]));
    await tester.pumpAndSettle();

    expect(find.text('Preço sob consulta'), findsOneWidget);
    await tester.tap(find.text('Falar Connosco').first);
    await tester.pumpAndSettle();

    expect(find.text('Business contact opened'), findsOneWidget);
    expect(find.text('Plano confirmado'), findsNothing);
  });

  testWidgets('updates selected state when another plan card is tapped',
      (tester) async {
    await tester.pumpWidget(_buildScreen(selectedPlan: Plan.starter));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FREE'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan_selected_free')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan_selected_starter')), findsNothing);
  });

  testWidgets('uses high-contrast app bar colors', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, AppColors.primaryDarker);
    expect(appBar.foregroundColor, Colors.white);
  });

  testWidgets('applies bottom-safe scroll padding', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final padding = listView.padding as EdgeInsets;

    expect(padding.left, 24);
    expect(padding.top, 24);
    expect(padding.right, 24);
    expect(padding.bottom, greaterThanOrEqualTo(80));
  });
}
