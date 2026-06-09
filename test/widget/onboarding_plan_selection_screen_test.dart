import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/app_colors.dart';
import 'package:maisum/features/subscription/data/firestore_plan_offers.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_snapshot.dart';
import 'package:maisum/features/subscription/domain/subscription_status.dart';
import 'package:maisum/features/subscription/domain/usage_quota.dart';
import 'package:maisum/features/subscription/presentation/onboarding_plan_selection_screen.dart';

class _FakeSubscriptionSnapshotController
    extends SubscriptionSnapshotController {
  _FakeSubscriptionSnapshotController(this.snapshot);

  final SubscriptionSnapshot snapshot;

  @override
  Future<SubscriptionSnapshot> build() async => snapshot;

  @override
  Future<void> refresh() async {}
}

Widget _buildScreen({Plan selectedPlan = Plan.starter}) {
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

  final offers = <PlanOffer>[
    const PlanOffer(
      plan: Plan.free,
      code: 'free',
      displayName: 'FREE',
      priceCents: 0,
      currency: 'BRL',
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
      currency: 'BRL',
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
      currency: 'BRL',
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

void main() {
  testWidgets('shows starter highlight badge and selected state',
      (tester) async {
    await tester.pumpWidget(_buildScreen(selectedPlan: Plan.starter));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan_badge_starter')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan_selected_starter')), findsOneWidget);
  });

  testWidgets('renders required plan action buttons', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(find.text('Comecar gratis'), findsOneWidget);
    expect(find.text('Escolher Plano'), findsOneWidget);
    expect(find.textContaining('Falar'), findsOneWidget);
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
