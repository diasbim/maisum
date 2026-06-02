import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/presentation/recovery_actions_screen.dart';
import 'package:maisum/features/engage/presentation/visit_report_screen.dart';
import 'package:maisum/features/engage/providers/engage_providers.dart';

Widget _wrap(Widget child, EngageAccess access) {
  return ProviderScope(
    overrides: [engageAccessProvider.overrideWith((ref) async => access)],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('Business-only engage workflow screens', () {
    testWidgets('RecoveryActionsScreen blocks non-business access', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RecoveryActionsScreen(),
          const EngageAccess(
            canViewRisk: true,
            canManageRecovery: false,
            canManageVisits: false,
            canManageSurveys: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ações indisponíveis no seu plano'), findsOneWidget);
    });

    testWidgets('RecoveryActionsScreen shows form for business access', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RecoveryActionsScreen(),
          const EngageAccess(
            canViewRisk: true,
            canManageRecovery: true,
            canManageVisits: true,
            canManageSurveys: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Salvar ação'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
    });

    testWidgets('VisitReportScreen blocks non-business visits access', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const VisitReportScreen(),
          const EngageAccess(
            canViewRisk: true,
            canManageRecovery: false,
            canManageVisits: false,
            canManageSurveys: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Visitas indisponíveis no seu plano'), findsOneWidget);
    });

    testWidgets('VisitReportScreen shows submission controls for business', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const VisitReportScreen(),
          const EngageAccess(
            canViewRisk: true,
            canManageRecovery: true,
            canManageVisits: true,
            canManageSurveys: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Salvar relatório'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });
  });
}
