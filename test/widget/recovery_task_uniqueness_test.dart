import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/engage/data/engage_dao.dart';
import 'package:maisum/features/engage/data/engage_repository.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/presentation/engage_dashboard_screen.dart';
import 'package:maisum/features/engage/providers/engage_providers.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

class _OverviewController extends EngageOverviewController {
  @override
  Future<EngageOverview> build() async => const EngageOverview(
        dashboard: EngageDashboardData(
          customersActive: 1,
          customersAtRisk: 1,
          criticalCustomers: 0,
          revenueAtRisk: 100,
          recoveredCustomers: 0,
        ),
        queue: [
          RecoveryQueueItem(
            customerId: 'customer-1',
            customerName: 'Ana',
            daysSinceVisit: 45,
            riskLevel: EngageRiskLevel.orange,
            priorityScore: 40,
            totalSpent: 100,
            totalPoints: 10,
            recommendedPriority: RecoveryTaskPriority.medium,
          ),
        ],
        pendingTasks: [],
      );

  @override
  Future<void> softRefresh() async {}
}

class _ExistingTaskRepository extends EngageRepository {
  _ExistingTaskRepository()
      : super(
          EngageDao(AppDatabase.instance, merchantId: 'merchant-1'),
          SyncDao(AppDatabase.instance, merchantId: 'merchant-1'),
        );

  @override
  Future<RecoveryTaskCreationResult> createRecoveryTaskWithResult({
    required String customerId,
    required String priority,
    DateTime? dueAt,
    String? notes,
  }) async {
    final now = DateTime(2026, 8, 27);
    return RecoveryTaskCreationResult(
      task: RecoveryTask(
        id: 'task-existing',
        customerId: customerId,
        priority: priority,
        status: RecoveryTaskStatus.open,
        createdAt: now,
        updatedAt: now,
        synced: true,
      ),
      outcome: RecoveryTaskCreationOutcome.alreadyOpen,
    );
  }
}

void main() {
  testWidgets('dashboard treats an existing remote task as informational',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engageAccessProvider.overrideWith(
            (ref) async => const EngageAccess(
              canViewRisk: true,
              canManageRecovery: true,
              canManageVisits: true,
              canManageSurveys: true,
            ),
          ),
          engageOverviewProvider.overrideWith(_OverviewController.new),
          engageRepositoryProvider.overrideWithValue(_ExistingTaskRepository()),
        ],
        child: const MaterialApp(home: EngageDashboardScreen()),
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
    await tester.tap(find.text('Ana').last);
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e criar'));
    await tester.pumpAndSettle();

    expect(
        find.text('Este cliente já tem uma tarefa pendente.'), findsOneWidget);
    expect(find.text('Tarefa de recuperação criada'), findsNothing);
  });
}
