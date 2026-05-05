import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/reward_card.dart';
import 'rewards_controller.dart';

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewards = ref.watch(rewardsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.recompensasTitle)),
      body: rewards.when(
        data: (list) => list.isEmpty
            ? EmptyState(
                title: AppStrings.semRecompensas,
                assetPath: 'assets/images/empty_state.png',
                assetHeight: 220,
                actionLabel: AppStrings.criarRecompensa,
                onAction: () => context.push('/rewards/new'),
              )
            : RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () =>
                    ref.read(rewardsControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => RewardCard(
                    name: list[i].name,
                    pointsRequired: list[i].pointsRequired,
                    description: list[i].description,
                  ),
                ),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (e, _) => Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text(AppStrings.tentar),
            onPressed: () =>
                ref.read(rewardsControllerProvider.notifier).refresh(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/rewards/new'),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
