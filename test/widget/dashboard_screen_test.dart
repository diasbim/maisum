import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/features/dashboard/presentation/dashboard_controller.dart';
import 'package:maisum/features/dashboard/presentation/dashboard_screen.dart';
import 'package:maisum/features/sync/sync_controller.dart';
import 'package:maisum/features/sync/sync_service.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

// Must extend the real controller so overrideWith type-checks pass.
class _FakeDashboardController extends DashboardController {
  _FakeDashboardController(this._stats);
  final DashboardStats _stats;

  @override
  Future<DashboardStats> build() async => _stats;
}

class _FakeSyncController extends SyncController {
  @override
  SyncStatus build() => const SyncStatus();
}

class _SlowDashboardController extends DashboardController {
  @override
  Future<DashboardStats> build() => Completer<DashboardStats>().future;
}

// ── Helper ───────────────────────────────────────────────────────────────────

// overrideWith requires () => Controller; capture stats via closure.
extension on DashboardStats {
  Widget buildDashboard({bool isOnline = true}) => ProviderScope(
        overrides: [
          dashboardControllerProvider.overrideWith(
            () => _FakeDashboardController(this),
          ),
          syncControllerProvider.overrideWith(_FakeSyncController.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(isOnline)),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('DashboardScreen — stat cards', () {
    testWidgets('displays the today stat labels', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 1).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.vendasHoje), findsOneWidget);
      expect(find.text(AppStrings.pontosHoje), findsOneWidget);
      expect(find.text('1 clientes registados'), findsOneWidget);
    });

    testWidgets('shows correct numeric values from stats', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(
          todaySaleCount: 7,
          todayPoints: 14,
          pendingSyncCount: 3,
          totalCustomers: 1,
        ).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('1 clientes registados'), findsOneWidget);
    });

    testWidgets('shows the empty-state onboarding for empty stats',
        (tester) async {
      await tester.pumpWidget(
        const DashboardStats(
          todaySaleCount: 0,
          todayPoints: 0,
          pendingSyncCount: 0,
        ).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tudo pronto para a primeira venda.'), findsOneWidget);
      expect(find.text(AppStrings.adicionarCliente), findsOneWidget);
    });
  });

  group('DashboardScreen — primary action', () {
    testWidgets('renders a dominant Nova Venda card', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 1).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.novaVenda), findsOneWidget);
      expect(find.text('Registar venda'), findsOneWidget);
      expect(
        find.text('Registe em segundos com uma única ação.'),
        findsOneWidget,
      );
    });
  });

  group('DashboardScreen — shortcuts', () {
    testWidgets('renders support shortcuts below the primary action', (
      tester,
    ) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 1).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.clientes), findsOneWidget);
      expect(find.text(AppStrings.recompensas), findsOneWidget);
      expect(find.text(AppStrings.historicoVendas), findsOneWidget);
      expect(find.textContaining(AppStrings.pendentes), findsOneWidget);
    });
  });

  group('DashboardScreen — section headers', () {
    testWidgets('shows Rápido and Hoje headers', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 1).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOJE'), findsOneWidget);
      expect(find.text('RÁPIDO'), findsOneWidget);
    });
  });

  group('DashboardScreen — app bar', () {
    testWidgets('app bar title shows LoyaltyOS', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 1).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appName), findsOneWidget);
    });

    testWidgets('settings icon is present', (tester) async {
      await tester.pumpWidget(
        const DashboardStats(totalCustomers: 1).buildDashboard(),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });
  });

  group('DashboardScreen — loading state', () {
    testWidgets('shows CircularProgressIndicator while loading', (
      tester,
    ) async {
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
      await tester
          .pump(); // one pump — don't settle so loading state is visible

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

