import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../customers/domain/customer.dart';
import '../domain/reward.dart';
import 'rewards_controller.dart';

class RedeemRewardSheet extends ConsumerStatefulWidget {
  const RedeemRewardSheet({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<RedeemRewardSheet> createState() => _RedeemRewardSheetState();
}

class _RedeemRewardSheetState extends ConsumerState<RedeemRewardSheet> {
  Reward? _selected;
  bool _loading = false;

  Future<void> _confirm() async {
    if (_selected == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(rewardsControllerProvider.notifier).redeemReward(
            customerId: widget.customer.id,
            rewardId: _selected!.id,
            pointsRequired: _selected!.pointsRequired,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rewardsAsync = ref.watch(rewardsControllerProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.g300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(AppStrings.resgatar, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '${widget.customer.name} · ${widget.customer.totalPoints} pts disponíveis',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          rewardsAsync.when(
            data: (rewards) {
              if (rewards.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(AppStrings.semRecompensas,
                        style: theme.textTheme.bodyMedium),
                  ),
                );
              }
              final eligible = rewards
                  .where((r) => r.pointsRequired <= widget.customer.totalPoints)
                  .toList();
              final ineligible = rewards
                  .where((r) => r.pointsRequired > widget.customer.totalPoints)
                  .toList();

              return ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (eligible.isNotEmpty) ...[
                      const _SectionLabel(AppStrings.recompensasDisponiveis),
                      ...eligible.map((r) => _RewardOption(
                            reward: r,
                            selected: _selected?.id == r.id,
                            eligible: true,
                            onTap: () => setState(() => _selected = r),
                          )),
                    ],
                    if (ineligible.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const _SectionLabel(AppStrings.recompensasInsuficientes),
                      ...ineligible.map((r) => _RewardOption(
                            reward: r,
                            selected: false,
                            eligible: false,
                            onTap: null,
                          )),
                    ],
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.secondary)),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: AppStrings.confirmarResgate,
            onPressed: _selected != null ? _confirm : null,
            loading: _loading,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _RewardOption extends StatelessWidget {
  const _RewardOption({
    required this.reward,
    required this.selected,
    required this.eligible,
    required this.onTap,
  });

  final Reward reward;
  final bool selected;
  final bool eligible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: eligible ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondaryLight : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.secondary : AppColors.g100,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                    ),
                    if (reward.description != null &&
                        reward.description!.isNotEmpty)
                      Text(
                        reward.description!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                '${reward.pointsRequired} pts',
                style: const TextStyle(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
