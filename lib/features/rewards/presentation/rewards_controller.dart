import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../app/providers.dart';
import '../../customers/presentation/customers_controller.dart';
import '../domain/reward.dart';

class RewardsController extends AsyncNotifier<List<Reward>> {
  @override
  Future<List<Reward>> build() => _load();

  Future<List<Reward>> _load() =>
      ref.read(rewardRepositoryProvider).getRewards();

  Future<Reward> createReward({
    required String name,
    required int pointsRequired,
    String? description,
  }) async {
    final reward = await ref.read(rewardRepositoryProvider).createReward(
          name: name,
          pointsRequired: pointsRequired,
          description: description,
        );
    state = await AsyncValue.guard(_load);

    // Trigger background sync
    ref.read(syncServiceProvider).processQueue();
    return reward;
  }

  Future<void> redeemReward({
    required String customerId,
    required String rewardId,
    required int pointsRequired,
  }) async {
    await ref.read(redemptionRepositoryProvider).redeemReward(
          customerId: customerId,
          rewardId: rewardId,
          pointsRequired: pointsRequired,
        );
    ref.invalidate(customerDetailProvider(customerId));
    ref.read(syncServiceProvider).processQueue();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

final rewardsControllerProvider =
    AsyncNotifierProvider<RewardsController, List<Reward>>(
        RewardsController.new);
