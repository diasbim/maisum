import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../app/providers.dart';

class DashboardStats {
  const DashboardStats({
    this.todaySaleCount = 0,
    this.todayPoints = 0,
    this.pendingSyncCount = 0,
    this.totalCustomers = 0,
  });

  final int todaySaleCount;
  final int todayPoints;
  final int pendingSyncCount;
  final int totalCustomers;
}

class DashboardController extends AsyncNotifier<DashboardStats> {
  @override
  Future<DashboardStats> build() => _load();

  Future<DashboardStats> _load() async {
    final salesStats =
        await ref.read(saleRepositoryProvider).getTodayStats();
    final pendingCount = await ref.read(syncDaoProvider).getPendingCount();
    final totalCustomers = await ref.read(customerDaoProvider).getCount();

    return DashboardStats(
      todaySaleCount: salesStats['count'] as int? ?? 0,
      todayPoints: salesStats['total_points'] as int? ?? 0,
      pendingSyncCount: pendingCount,
      totalCustomers: totalCustomers,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardStats>(
        DashboardController.new);
