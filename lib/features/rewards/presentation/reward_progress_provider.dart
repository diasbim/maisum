import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/reward_progress.dart';

final rewardProgressProvider = FutureProvider.family<RewardProgress, String>(
  (ref, customerId) async {
    final customer =
        await ref.read(customerRepositoryProvider).getById(customerId);
    if (customer == null) {
      return RewardProgress.empty();
    }
    final rewards = await ref.read(rewardRepositoryProvider).getRewards();
    return RewardProgress.fromRewards(
      currentPoints: customer.totalPoints,
      rewards: rewards,
    );
  },
);
