import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/retention/domain/retention_metric.dart';
import 'package:maisum/features/retention/widgets/inactive_customer_card.dart';
import 'package:maisum/features/retention/widgets/recurring_customer_card.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

InactiveCustomerSummary _inactive(String riskLevel) => InactiveCustomerSummary(
      customerId: 'c1',
      name: 'Ana Cumbe',
      daysInactive: 45,
      lastVisitAt: DateTime(2026, 7, 26),
      averageTicket: 850,
      riskLevel: riskLevel,
    );

void main() {
  group('InactiveCustomerCard', () {
    testWidgets('names the risk level in Portuguese, never the stored value',
        (tester) async {
      for (final level in RetentionRiskLevel.values) {
        await tester.pumpWidget(
          _wrap(
            InactiveCustomerCard(
              customer: _inactive(level),
              onSendReminder: () {},
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text(level),
          findsNothing,
          reason: 'raw "$level" reached the screen',
        );
      }
    });

    testWidgets('leads with how long the customer has been away',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          InactiveCustomerCard(
            customer: _inactive(RetentionRiskLevel.risk),
            onSendReminder: () {},
          ),
        ),
      );

      expect(find.text('Em risco'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('dias sem voltar'), findsOneWidget);
    });

    testWidgets('disables the reminder while one is being prepared',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          InactiveCustomerCard(
            customer: _inactive(RetentionRiskLevel.risk),
            isSending: true,
            onSendReminder: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('A preparar lembrete…'), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('survives 200% text without clipping', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InactiveCustomerCard(
            customer: _inactive(RetentionRiskLevel.lost),
            onSendReminder: () {},
          ),
          textScale: 2.0,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('RecurringCustomerCard', () {
    testWidgets('shows the return rhythm and a Portuguese badge',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecurringCustomerCard(
            customer: RecurringCustomerSummary(
              customerId: 'c2',
              name: 'João Matola',
              totalVisits: 12,
              lastVisitAt: DateTime(2026, 9, 1),
              averageVisitInterval: 14,
              totalSpent: 4200,
            ),
          ),
        ),
      );

      expect(find.text('Campeão'), findsOneWidget);
      expect(find.text('Volta a cada'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('says so plainly when there is no pattern yet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecurringCustomerCard(
            customer: RecurringCustomerSummary(
              customerId: 'c3',
              name: 'Sara Nhaca',
              totalVisits: 2,
              lastVisitAt: DateTime(2026, 9, 1),
              averageVisitInterval: 0,
              totalSpent: 300,
            ),
          ),
        ),
      );

      expect(find.text('Ainda a formar um padrão de visitas'), findsOneWidget);
      expect(find.text('-'), findsNothing);
    });
  });
}
