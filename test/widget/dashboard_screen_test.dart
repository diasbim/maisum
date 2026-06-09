import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/dashboard/presentation/dashboard_controller.dart';
import 'package:maisum/features/dashboard/presentation/dashboard_screen.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/sync_controller.dart';
import 'package:maisum/features/sync/sync_service.dart';

class _FakeDashboardController extends DashboardController {
  _FakeDashboardController(this._stats);
  final DashboardStats _stats;

  @override
  Future<DashboardStats> build() async => _stats;
}

class _FakeSyncController extends SyncController {
  @override
  SyncStatus build() => const SyncStatus(isOnline: true);
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository(this.customersCount)
      : super(CustomerDao(AppDatabase.instance), SyncDao(AppDatabase.instance));

  final int customersCount;

  @override
  Future<int> count() async => customersCount;
}

class _SlowDashboardController extends DashboardController {
  @override
  Future<DashboardStats> build() => Completer<DashboardStats>().future;
}

extension on DashboardStats {
  Widget buildDashboard({
    bool isOnline = true,
    int customersCount = 1,
  }) =>
      ProviderScope(
        overrides: [
          dashboardControllerProvider.overrideWith(
            () => _FakeDashboardController(this),
          ),
          syncControllerProvider.overrideWith(_FakeSyncController.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(isOnline)),
          customerRepositoryProvider.overrideWithValue(
            _FakeCustomerRepository(customersCount),
          ),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      );
}

void main() {
  group('DashboardScreen — sales-first layout', () {
    testWidgets('shows dual header metrics for sales and points',
        (tester) async {
      await tester.pumpWidget(
        const DashboardStats(
          todaySaleCount: 12,
          todayPoints: 35,
          totalCustomers: 3,
        ).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.vendasHoje), findsOneWidget);
      expect(find.text(AppStrings.pontosHoje), findsOneWidget);
      expect(find.text('12 vendas'), findsOneWidget);
      expect(find.text('35 ${AppStrings.pontosAbrev}'), findsOneWidget);
    });

    testWidgets('removes first-sale empty state card', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(
          todaySaleCount: 0,
          todayPoints: 0,
          totalCustomers: 0,
        ).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tudo pronto para a primeira venda.'), findsNothing);
      expect(find.text(AppStrings.dashboardEmptySubtitle), findsNothing);
    });

    testWidgets('keeps Nova Venda as primary hero CTA', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 2).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.novaVenda), findsOneWidget);
      expect(find.text(AppStrings.dashboardSaleCardSubtitle), findsOneWidget);
      expect(find.text(AppStrings.dashboardSaleCta), findsOneWidget);
    });

    testWidgets('shows only Clientes and Recompensas shortcuts',
        (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 3).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.clientes), findsOneWidget);
      expect(find.text(AppStrings.recompensas), findsOneWidget);
      expect(find.text(AppStrings.historicoVendas), findsNothing);
      expect(find.textContaining(AppStrings.pendentes), findsNothing);
    });
  });

  group('DashboardScreen — customer prerequisite', () {
    testWidgets('shows required-customer modal before sale when count is zero',
        (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 0).buildDashboard(
          customersCount: 0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.dashboardSaleCta));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum cliente registado'), findsOneWidget);
      expect(
        find.text(
            'Para registrar uma venda,\nprimeiro precisa adicionar um cliente.'),
        findsOneWidget,
      );
      expect(find.text('Adicionar Cliente'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });
  });

  group('DashboardScreen — loading state', () {
    testWidgets('keeps scaffold visible while loading stats', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardControllerProvider.overrideWith(
              _SlowDashboardController.new,
            ),
            syncControllerProvider.overrideWith(_FakeSyncController.new),
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text(AppStrings.appName), findsOneWidget);
    });
  });
}
