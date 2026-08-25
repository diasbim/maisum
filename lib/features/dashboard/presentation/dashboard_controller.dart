import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../app/providers.dart';
import '../../customers/domain/customer.dart';

class DashboardStats {
  const DashboardStats({
    this.todaySaleCount = 0,
    this.todayPoints = 0,
    this.pendingSyncCount = 0,
    this.totalCustomers = 0,
    this.returningCustomers = 0,
    this.regularCustomers = 0,
    this.atRiskCustomers = 0,
    this.inactiveCustomers = 0,
    this.retentionRate = 0,
    this.averageVisitsPerCustomer = 0,
    this.streakDays = 0,
    this.streakAtRisk = false,
  });

  final int todaySaleCount;
  final int todayPoints;
  final int pendingSyncCount;
  final int totalCustomers;
  final int returningCustomers;
  final int regularCustomers;
  final int atRiskCustomers;
  final int inactiveCustomers;
  final double retentionRate;
  final double averageVisitsPerCustomer;
  final int streakDays;
  final bool streakAtRisk;
}

class DashboardQuickCustomer {
  const DashboardQuickCustomer({
    required this.customer,
    this.scheduledDate,
  });

  final Customer customer;
  final DateTime? scheduledDate;
}

class DashboardController extends AsyncNotifier<DashboardStats> {
  @override
  Future<DashboardStats> build() => _load();

  Future<DashboardStats> _load() async {
    final salesFuture = ref.read(saleRepositoryProvider).getTodayStats();
    final pendingFuture = ref.read(syncDaoProvider).getPendingCount();
    final customersFuture = ref.read(customerDaoProvider).getAll();
    final recentReturningFuture =
        ref.read(saleDaoProvider).getReturningCustomersCount(days: 30);
    final streakFuture = ref.read(streakServiceProvider).getCurrentStreak();

    final salesStats = await salesFuture;
    final pendingCount = await pendingFuture;
    final customers = await customersFuture;
    final totalCustomers = customers.length;
    final lifecycleReturningCustomers = customers
        .where((customer) => switch (customer.lifecycleStage) {
              CustomerLifecycleStage.returning ||
              CustomerLifecycleStage.regular ||
              CustomerLifecycleStage.loyal ||
              CustomerLifecycleStage.vip ||
              CustomerLifecycleStage.advocate =>
                true,
              _ => false,
            })
        .length;
    final recentReturningCustomers = await recentReturningFuture;
    final returningCustomers =
        lifecycleReturningCustomers > recentReturningCustomers
            ? lifecycleReturningCustomers
            : recentReturningCustomers;
    final regularCustomers = customers
        .where((customer) => switch (customer.lifecycleStage) {
              CustomerLifecycleStage.regular ||
              CustomerLifecycleStage.loyal ||
              CustomerLifecycleStage.vip ||
              CustomerLifecycleStage.advocate =>
                true,
              _ => false,
            })
        .length;
    final atRiskCustomers = customers
        .where(
          (customer) =>
              customer.retentionStatus == CustomerRetentionStatus.atRisk,
        )
        .length;
    final inactiveCustomers = customers
        .where(
          (customer) =>
              customer.retentionStatus == CustomerRetentionStatus.inactive ||
              customer.retentionStatus == CustomerRetentionStatus.lost,
        )
        .length;
    final totalVisits =
        customers.fold<int>(0, (sum, customer) => sum + customer.totalVisits);
    final retentionRate =
        totalCustomers == 0 ? 0.0 : returningCustomers / totalCustomers;
    final averageVisitsPerCustomer =
        totalCustomers == 0 ? 0.0 : totalVisits / totalCustomers;
    final streak = await streakFuture;

    return DashboardStats(
      todaySaleCount: salesStats['count'] as int? ?? 0,
      todayPoints: salesStats['total_points'] as int? ?? 0,
      pendingSyncCount: pendingCount,
      totalCustomers: totalCustomers,
      returningCustomers: returningCustomers,
      regularCustomers: regularCustomers,
      atRiskCustomers: atRiskCustomers,
      inactiveCustomers: inactiveCustomers,
      retentionRate: retentionRate.clamp(0, 1),
      averageVisitsPerCustomer: averageVisitsPerCustomer,
      streakDays: streak.days,
      streakAtRisk: streak.isAtRisk,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardStats>(
        DashboardController.new);

final scheduledCustomersTodayProvider =
    FutureProvider<List<DashboardQuickCustomer>>((ref) async {
  final startOfDay = DateTime.now().copyWith(
    hour: 0,
    minute: 0,
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
  final appointments = await ref.read(appointmentDaoProvider).getUpcoming(
        from: startOfDay,
        limit: 8,
      );

  final result = <DashboardQuickCustomer>[];
  for (final appointment in appointments) {
    final customer =
        await ref.read(customerDaoProvider).getById(appointment.customerId);
    if (customer == null) continue;
    result.add(
      DashboardQuickCustomer(
        customer: customer,
        scheduledDate: appointment.scheduledDate,
      ),
    );
  }
  return result;
});

final recentQuickCustomersProvider =
    FutureProvider<List<DashboardQuickCustomer>>((ref) async {
  final recentCustomers =
      await ref.read(customerDaoProvider).getRecent(limit: 8);
  return recentCustomers
      .map((customer) => DashboardQuickCustomer(customer: customer))
      .toList();
});

final lastSaleAmountProvider = FutureProvider<double?>((ref) async {
  final amount = await ref.read(saleDaoProvider).getLastSaleAmount();
  return amount?.toDouble();
});
