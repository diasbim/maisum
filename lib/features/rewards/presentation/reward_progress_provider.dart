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
    final balance =
        await ref.read(loyaltyLedgerDaoProvider).getCustomerBalance(customerId);
    final rewards = await ref.read(rewardRepositoryProvider).getRewards();
    return RewardProgress.fromRewards(
      currentPoints: balance.projectedPoints,
      rewards: rewards,
    );
  },
);
