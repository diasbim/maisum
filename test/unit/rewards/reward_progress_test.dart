import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/rewards/domain/reward.dart';
import 'package:maisum/features/rewards/domain/reward_progress.dart';

void main() {
  group('RewardProgress', () {
    test('calculates progress toward next reward', () {
      final rewards = [
        Reward(
          id: 'r1',
          name: 'Corte Gratis',
          pointsRequired: 50,
          createdAt: DateTime(2026, 5, 1),
        ),
      ];

      final progress = RewardProgress.fromRewards(
        currentPoints: 20,
        rewards: rewards,
      );

      expect(progress.progressPercentage, 40);
      expect(progress.pointsRemaining, 30);
      expect(progress.nextRewardName, 'Corte Gratis');
      expect(progress.unlockedRewardName, isNull);
    });

    test('handles progress near completion', () {
      final rewards = [
        Reward(
          id: 'r1',
          name: 'Corte Gratis',
          pointsRequired: 50,
          createdAt: DateTime(2026, 5, 1),
        ),
      ];

      final progress = RewardProgress.fromRewards(
        currentPoints: 45,
        rewards: rewards,
      );

      expect(progress.progressPercentage, 90);
      expect(progress.pointsRemaining, 5);
    });

    test('returns unlocked reward when points exceed target', () {
      final rewards = [
        Reward(
          id: 'r1',
          name: 'Corte Gratis',
          pointsRequired: 50,
          createdAt: DateTime(2026, 5, 1),
        ),
      ];

      final progress = RewardProgress.fromRewards(
        currentPoints: 60,
        rewards: rewards,
      );

      expect(progress.progressPercentage, 100);
      expect(progress.pointsRemaining, 0);
      expect(progress.nextRewardName, isNull);
      expect(progress.unlockedRewardName, 'Corte Gratis');
    });

    test('selects the next reward in a tiered list', () {
      final rewards = [
        Reward(
          id: 'r1',
          name: 'Cafe',
          pointsRequired: 10,
          createdAt: DateTime(2026, 5, 1),
        ),
        Reward(
          id: 'r2',
          name: 'Corte Gratis',
          pointsRequired: 50,
          createdAt: DateTime(2026, 5, 1),
        ),
      ];

      final progress = RewardProgress.fromRewards(
        currentPoints: 15,
        rewards: rewards,
      );

      expect(progress.nextRewardName, 'Corte Gratis');
      expect(progress.unlockedRewardName, 'Cafe');
      expect(progress.pointsRemaining, 35);
    });
  });
}
