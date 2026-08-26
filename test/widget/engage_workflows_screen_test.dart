import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/presentation/engage_dashboard_screen.dart';
import 'package:maisum/features/engage/presentation/recovery_actions_screen.dart';
import 'package:maisum/features/engage/presentation/visit_report_screen.dart';
import 'package:maisum/features/engage/providers/engage_providers.dart';

class _FakeOverviewController extends EngageOverviewController {
  _FakeOverviewController(this.overview);

  final EngageOverview overview;

  @override
  Future<EngageOverview> build() async => overview;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> softRefresh() async {}
}

class _ErrorOverviewController extends EngageOverviewController {
  @override
  Future<EngageOverview> build() => Future.error('queue failed');

  @override
  Future<void> refresh() async {}
}

class _SlowOverviewController extends EngageOverviewController {
  @override
  Future<EngageOverview> build() => Completer<EngageOverview>().future;
}

const _businessAccess = EngageAccess(
  canViewRisk: true,
  canManageRecovery: true,
  canManageVisits: true,
  canManageSurveys: true,
);

EngageOverview _overview({
  List<RecoveryTaskQueueItem> tasks = const [],
  List<RecoveryQueueItem> candidates = const [],
}) =>
    EngageOverview(
      dashboard: const EngageDashboardData(
        customersActive: 3,
        customersAtRisk: 1,
        criticalCustomers: 0,
        revenueAtRisk: 100,
        recoveredCustomers: 2,
      ),
      queue: candidates,
      pendingTasks: tasks,
    );

RecoveryTaskQueueItem _task() => RecoveryTaskQueueItem(
      task: RecoveryTask(
        id: 'internal-task-id',
        customerId: 'internal-customer-id',
        priority: RecoveryTaskPriority.high,
        status: RecoveryTaskStatus.open,
        notes: 'Ligar ainda hoje',
        createdAt: DateTime(2026, 8, 26),
        updatedAt: DateTime(2026, 8, 26),
      ),
      customerName: 'Ana Matola',
      customerPhone: '841234567',
    );

Widget _wrap(
  Widget child,
  EngageAccess access, {
  EngageOverviewController? overviewController,
}) {
  return ProviderScope(
    overrides: [
      engageAccessProvider.overrideWith((ref) async => access),
      if (overviewController != null)
        engageOverviewProvider.overrideWith(() => overviewController),
    ],
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

    testWidgets('shows pending task context and no raw identifiers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RecoveryActionsScreen(),
          _businessAccess,
          overviewController: _FakeOverviewController(
            _overview(tasks: [_task()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana Matola'), findsOneWidget);
      expect(find.textContaining('Prioridade alta'), findsOneWidget);
      expect(find.textContaining('Pendente'), findsOneWidget);
      expect(find.text('Guardar ação'), findsNothing);

      await tester.tap(find.text('Ana Matola'));
      await tester.pumpAndSettle();

      expect(find.text('Guardar ação'), findsOneWidget);
      expect(find.text('Concluir tarefa'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Customer ID'), findsNothing);
      expect(find.textContaining('internal-task-id'), findsNothing);
      expect(find.textContaining('internal-customer-id'), findsNothing);
    });

    testWidgets('RecoveryActionsScreen shows empty queue', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RecoveryActionsScreen(),
          _businessAccess,
          overviewController: _FakeOverviewController(_overview()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma tarefa pendente'), findsOneWidget);
    });

    testWidgets('RecoveryActionsScreen shows queue loading', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RecoveryActionsScreen(),
          _businessAccess,
          overviewController: _SlowOverviewController(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('RecoveryActionsScreen shows queue error and retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RecoveryActionsScreen(),
          _businessAccess,
          overviewController: _ErrorOverviewController(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível carregar a fila'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('dashboard requires customer choice and confirmation', (
      tester,
    ) async {
      const candidate = RecoveryQueueItem(
        customerId: 'hidden-customer-id',
        customerName: 'Carlos João',
        daysSinceVisit: 60,
        riskLevel: EngageRiskLevel.orange,
        priorityScore: 40,
        totalSpent: 1200,
        totalPoints: 80,
        recommendedPriority: RecoveryTaskPriority.medium,
      );
      await tester.pumpWidget(
        _wrap(
          const EngageDashboardScreen(),
          _businessAccess,
          overviewController: _FakeOverviewController(
            _overview(candidates: [candidate]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final createButton = find.text('Escolher cliente e criar tarefa');
      await tester.scrollUntilVisible(
        createButton,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(find.text('Escolher cliente'), findsOneWidget);
      expect(find.text('Confirmar nova tarefa'), findsNothing);
      expect(find.textContaining('hidden-customer-id'), findsNothing);

      await tester.tap(find.text('Carlos João').last);
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar nova tarefa'), findsOneWidget);
      expect(find.text('Confirmar e criar'), findsOneWidget);
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
        _wrap(const VisitReportScreen(), _businessAccess),
      );
      await tester.pumpAndSettle();

      expect(find.text('Guardar relatório'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });
  });
}
