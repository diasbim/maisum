import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../subscription/domain/feature_keys.dart';
import '../domain/retention_metric.dart';

class RetentionDashboardData {
  const RetentionDashboardData({
    required this.recurring,
    required this.inactive,
  });

  final List<RecurringCustomerSummary> recurring;
  final List<InactiveCustomerSummary> inactive;
}

final recurringCustomersProvider =
    FutureProvider<List<RecurringCustomerSummary>>((ref) {
  return ref.read(retentionRepositoryProvider).getRecurringCustomers(limit: 50);
});

final inactiveCustomersProvider =
    FutureProvider<List<InactiveCustomerSummary>>((ref) {
  return ref.read(retentionRepositoryProvider).getInactiveCustomers(limit: 50);
});

final retentionPremiumAccessProvider = FutureProvider<bool>((ref) async {
  final gate = ref.read(featureGateProvider);
  final decision = await gate.check(featureKey: FeatureKeys.engageViewRisk);
  return decision.allowed;
});

class RetentionDashboardController
    extends AsyncNotifier<RetentionDashboardData> {
  @override
  Future<RetentionDashboardData> build() => _load();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> recalculate() async {
    await ref.read(retentionRepositoryProvider).calculateRetention();
    ref.read(syncServiceProvider).processQueue();
    state = await AsyncValue.guard(_load);
  }

  Future<void> updateCustomerRisk({
    required String customerId,
    required String riskLevel,
  }) async {
    await ref.read(retentionRepositoryProvider).updateCustomerRisk(
          customerId: customerId,
          riskLevel: riskLevel,
        );
    ref.read(syncServiceProvider).processQueue();
    state = await AsyncValue.guard(_load);
  }

  Future<RetentionDashboardData> _load() async {
    final repo = ref.read(retentionRepositoryProvider);
    final recurring = await repo.getRecurringCustomers(limit: 50);
    final inactive = await repo.getInactiveCustomers(limit: 50);
    return RetentionDashboardData(recurring: recurring, inactive: inactive);
  }
}

final retentionDashboardProvider =
    AsyncNotifierProvider<RetentionDashboardController, RetentionDashboardData>(
  RetentionDashboardController.new,
);
