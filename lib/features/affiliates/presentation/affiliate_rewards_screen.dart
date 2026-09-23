import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/affiliate_reward.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../providers/affiliate_providers.dart';
import 'widgets/affiliate_widgets.dart';

/// What the business owes its affiliates, and the decision on each.
///
/// Approval is an owner's call and an online one. Both buttons stay on screen
/// when either condition fails, disabled with the reason underneath: hiding
/// them would leave a staff member believing the queue is empty of actions when
/// it is only empty of their actions.
class AffiliateRewardsScreen extends ConsumerWidget {
  const AffiliateRewardsScreen({super.key, this.affiliateId});

  final String? affiliateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewardsAsync = ref.watch(affiliateRewardsProvider(affiliateId));
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull ?? false;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const MaisUmAppBar(
        title: 'Recompensas',
        fallbackLocation: '/affiliates',
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(affiliateRewardsProvider(affiliateId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            if (!online) ...[
              const AffiliateOfflineNotice(
                message: 'Sem ligação. Aprovar ou cancelar uma recompensa só é '
                    'possível online, porque é o sistema que regista a decisão.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (!isOwner) ...[
              const AffiliateOfflineNotice(
                message: 'Só o responsável do negócio pode aprovar ou cancelar '
                    'recompensas.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AffiliateAsyncView<AffiliatePage<MerchantAffiliateReward>>(
              value: rewardsAsync,
              loadingLabel: 'A carregar recompensas',
              onRetry: () =>
                  ref.invalidate(affiliateRewardsProvider(affiliateId)),
              builder: (context, page) {
                if (page.isEmpty) {
                  return const _EmptyRewards();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (page.truncated) ...[
                      const AffiliateTruncatedBanner(
                        detail:
                            'Há mais recompensas do que conseguimos mostrar '
                            'de uma vez. Aprove as que vê e volte a abrir.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    for (final reward in page.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _RewardCard(
                          reward: reward,
                          canDecide: isOwner && online,
                          isOwner: isOwner,
                          online: online,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRewards extends StatelessWidget {
  const _EmptyRewards();

  @override
  Widget build(BuildContext context) {
    return const MaisUmSurface(
      key: Key('affiliate-rewards-empty'),
      width: double.infinity,
      radius: AppRadius.lg,
      padding: EdgeInsets.all(AppSpacing.xl),
      animationDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Nenhuma recompensa ainda',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Assim que um cliente novo usar um código numa compra, a '
            'recompensa do afiliado aparece aqui para aprovar.',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends ConsumerStatefulWidget {
  const _RewardCard({
    required this.reward,
    required this.canDecide,
    required this.isOwner,
    required this.online,
  });

  final MerchantAffiliateReward reward;
  final bool canDecide;
  final bool isOwner;
  final bool online;

  @override
  ConsumerState<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends ConsumerState<_RewardCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = ref.read(affiliateAdminControllerProvider.notifier);
    try {
      if (approve) {
        await controller.approveReward(
          rewardId: widget.reward.id,
          affiliateId: widget.reward.affiliateId,
        );
      } else {
        await controller.cancelReward(
          rewardId: widget.reward.id,
          affiliateId: widget.reward.affiliateId,
        );
      }
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: approve ? 'Recompensa aprovada' : 'Recompensa cancelada',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: AppErrorMapper.describe(error).message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.reward;
    final status = _statusLabel(reward.status);
    final points = reward.value == reward.value.roundToDouble()
        ? reward.value.round().toString()
        : reward.value.toStringAsFixed(2);
    final unit =
        reward.valueType == AffiliateRewardValueType.points ? 'pontos' : 'MT';

    return MaisUmSurface(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      animationDuration: Duration.zero,
      semanticLabel: 'Recompensa de $points $unit. '
          'Motivo: ${_typeLabel(reward.type)}. Estado: $status.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$points $unit',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              AffiliateStatusChip(
                label: status,
                icon: _statusIcon(reward.status),
                color: _statusColor(reward.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _typeLabel(reward.type),
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
          if (reward.createdAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Criada em ${PtDateFormat.dayMonthYearTime(reward.createdAt!)}',
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          if (reward.isDecidable) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: MaisUmButton(
                    key: Key('reward-approve-${reward.id}'),
                    label: 'Aprovar',
                    isLoading: _busy,
                    onPressed: widget.canDecide && !_busy
                        ? () => _decide(approve: true)
                        : null,
                    animationDuration: Duration.zero,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MaisUmButton(
                    key: Key('reward-cancel-${reward.id}'),
                    label: 'Cancelar',
                    variant: MaisUmButtonVariant.outlined,
                    foregroundColor: AppColors.error,
                    onPressed: widget.canDecide && !_busy
                        ? () => _decide(approve: false)
                        : null,
                    animationDuration: Duration.zero,
                  ),
                ),
              ],
            ),
            if (!widget.canDecide) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.isOwner
                    ? 'Sem ligação: a decisão fica para quando houver rede.'
                    : 'Só o responsável do negócio pode decidir.',
                key: const Key('reward-disabled-reason'),
                style: const TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _statusLabel(AffiliateRewardStatus status) => switch (status) {
        AffiliateRewardStatus.pending => 'Pendente',
        AffiliateRewardStatus.approved => 'Aprovada',
        AffiliateRewardStatus.paid => 'Paga',
        AffiliateRewardStatus.cancelled => 'Cancelada',
      };

  static IconData _statusIcon(AffiliateRewardStatus status) => switch (status) {
        AffiliateRewardStatus.pending => Icons.schedule_rounded,
        AffiliateRewardStatus.approved => Icons.check_circle_outline_rounded,
        AffiliateRewardStatus.paid => Icons.payments_rounded,
        AffiliateRewardStatus.cancelled => Icons.cancel_outlined,
      };

  static Color _statusColor(AffiliateRewardStatus status) => switch (status) {
        AffiliateRewardStatus.pending => AppColors.warning,
        AffiliateRewardStatus.approved => AppColors.success,
        AffiliateRewardStatus.paid => AppColors.primary,
        AffiliateRewardStatus.cancelled => AppColors.onSurfaceVariant,
      };

  static String _typeLabel(AffiliateRewardType type) => switch (type) {
        AffiliateRewardType.firstQualifyingSale => 'Primeiro cliente trazido',
        AffiliateRewardType.customerReturn => 'Cliente voltou',
      };
}
