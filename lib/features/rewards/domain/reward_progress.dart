import 'reward.dart';

class RewardProgress {
  const RewardProgress({
    required this.currentPoints,
    required this.pointsRemaining,
    required this.progressPercentage,
    required this.targetPoints,
    required this.nextRewardName,
    required this.unlockedRewardName,
  });

  final int currentPoints;
  final int pointsRemaining;
  final int progressPercentage;
  final int? targetPoints;
  final String? nextRewardName;
  final String? unlockedRewardName;

  double get progressFraction {
    final safeTarget = targetPoints ?? 0;
    if (safeTarget <= 0) return 0;
    return (currentPoints / safeTarget).clamp(0.0, 1.0);
  }

  static RewardProgress empty() => const RewardProgress(
        currentPoints: 0,
        pointsRemaining: 0,
        progressPercentage: 0,
        targetPoints: null,
        nextRewardName: null,
        unlockedRewardName: null,
      );

  static RewardProgress fromRewards({
    required int currentPoints,
    required List<Reward> rewards,
  }) {
    if (rewards.isEmpty) {
      return RewardProgress(
        currentPoints: currentPoints,
        pointsRemaining: 0,
        progressPercentage: 0,
        targetPoints: null,
        nextRewardName: null,
        unlockedRewardName: null,
      );
    }

    final sortedRewards = [...rewards]
      ..sort((a, b) => a.pointsRequired.compareTo(b.pointsRequired));

    Reward? nextReward;
    Reward? unlockedReward;

    for (final reward in sortedRewards) {
      if (reward.pointsRequired > currentPoints) {
        nextReward ??= reward;
      } else {
        unlockedReward = reward;
      }
    }

    final pointsRemaining = nextReward == null
        ? 0
        : (nextReward.pointsRequired - currentPoints).clamp(0, 999999);
    final targetPoints =
        nextReward?.pointsRequired ?? unlockedReward?.pointsRequired;
    final safeTarget = (targetPoints ?? 0) <= 0 ? 1 : targetPoints!;
    final progressFraction = (currentPoints / safeTarget).clamp(0.0, 1.0);

    return RewardProgress(
      currentPoints: currentPoints,
      pointsRemaining: pointsRemaining,
      progressPercentage: (progressFraction * 100).round(),
      targetPoints: targetPoints,
      nextRewardName: nextReward?.name,
      unlockedRewardName: unlockedReward?.name,
    );
  }
}
