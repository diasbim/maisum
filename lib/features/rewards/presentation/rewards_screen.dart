import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/reward.dart';
import 'rewards_controller.dart';

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewards = ref.watch(rewardsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.primaryDarker,
      body: rewards.when(
        data: (list) => RefreshIndicator(
          color: AppColors.secondary,
          onRefresh: () =>
              ref.read(rewardsControllerProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _RewardsHeader(
                onBack: () => context.pop(),
                onInfo: () => context.push('/privacy'),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 360;
                          final title = Text(
                            AppStrings.recompensasSection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          );
                          final action = TextButton.icon(
                            onPressed: list.isEmpty ? null : () {},
                            icon: const Icon(Icons.sort_rounded, size: 18),
                            label: const Text(AppStrings.recompensasOrdenar),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.secondaryDark,
                            ),
                          );
                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 8),
                                action,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: title),
                              action,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (list.isEmpty)
                        EmptyState(
                          title: AppStrings.semRecompensas,
                          assetPath: 'assets/images/empty_state.png',
                          assetHeight: 200,
                          actionLabel: AppStrings.criarRecompensa,
                          onAction: () => context.push('/rewards/new'),
                        )
                      else ...[
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 360;
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isNarrow ? 1 : 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: isNarrow ? 1.35 : 0.82,
                              ),
                              itemCount: list.length,
                              itemBuilder: (_, i) =>
                                  _RewardTile(reward: list[i]),
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        const _InsightBanner(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/rewards/new'),
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          AppStrings.novaRecompensa,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

class _RewardsHeader extends StatelessWidget {
  const _RewardsHeader({required this.onBack, required this.onInfo});

  final VoidCallback onBack;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDarker, AppColors.primary],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppStrings.recompensasTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: onInfo,
                    icon: const Icon(Icons.info_outline_rounded,
                        color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _HeroBanner(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: AppColors.secondary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.recompensasHeroTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.recompensasHeroBody,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.star_rounded,
                color: AppColors.primary, size: 28),
          ),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.reward});

  final Reward reward;

  @override
  Widget build(BuildContext context) {
    final icon = _rewardIcon(reward.name);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.secondaryDark, size: 22),
              ),
              if (reward.active)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.greenLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.circle, color: AppColors.green, size: 8),
                      SizedBox(width: 6),
                      Text(
                        AppStrings.recompensaAtiva,
                        style: TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reward.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.pontosNecessarios,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${reward.pointsRequired} pts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (reward.description != null && reward.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reward.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _rewardIcon(String name) {
    final seed = name.trim().toLowerCase().hashCode;
    const icons = [
      Icons.content_cut_rounded,
      Icons.percent_rounded,
      Icons.shower_rounded,
      Icons.local_cafe_rounded,
      Icons.card_giftcard_rounded,
      Icons.star_rounded,
    ];
    return icons[seed.abs() % icons.length];
  }
}

class _InsightBanner extends StatelessWidget {
  const _InsightBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded,
                color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.recompensasInsightTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.recompensasInsightBody,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
