import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/affiliates/presentation/affiliate_metrics_screen.dart';

import 'affiliate_test_support.dart';

/// Six numbers, one of which can be a division by zero.
///
/// A programme with no attempts has no conversion rate. Printing "0%" would say
/// it is failing; saying "Sem dados" says it has not started, and those lead an
/// owner to opposite decisions.
void main() {
  testWidgets('shows the six metrics', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(metrics: sampleMetrics());

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateMetricsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('metric-referred')), findsOneWidget);
    expect(find.byKey(const Key('metric-returned')), findsOneWidget);
    expect(find.byKey(const Key('metric-attempts')), findsOneWidget);
    expect(find.byKey(const Key('metric-conversion')), findsOneWidget);
    expect(find.byKey(const Key('metric-pending')), findsOneWidget);
    expect(find.byKey(const Key('metric-approved')), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('never prints a percentage it could not compute', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      metrics: sampleMetrics(
        attempts: 0,
        confirmed: 0,
        returned: 0,
        pendingCount: 0,
        pendingPoints: 0,
        approvedCount: 0,
        approvedPoints: 0,
        conversionRate: 0,
      ),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateMetricsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem dados'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('Nenhum código foi tentado ainda.'), findsOneWidget);
    expect(find.text('Ainda não há atividade registada.'), findsOneWidget);
  });

  testWidgets('says when the totals are only a floor', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(
      metrics: sampleMetrics(truncated: true),
    );

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateMetricsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-truncated-banner')), findsOneWidget);
  });

  testWidgets('a failed load is retryable', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(metricsError: StateError('boom'));

    await tester.pumpWidget(
      wrapScreen(
        const AffiliateMetricsScreen(),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('affiliate-error-state')), findsOneWidget);
  });

  testWidgets('holds together at a 200% text scale', (tester) async {
    usePhoneSurface(tester);
    final gateway = FakeAffiliateGateway(metrics: sampleMetrics());

    await tester.pumpWidget(
      wrapScreen(
        textScaled(const AffiliateMetricsScreen(), 2),
        affiliateOverrides(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
