import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/components/maisum_button.dart';
import '../../../../design_system/components/maisum_surface.dart';
import '../../domain/customer_models.dart';

String formatCustomerPoints(int points) =>
    NumberFormat.decimalPattern('pt_PT').format(points);

enum CustomerStatusTone { neutral, accent, success, warning, error }

class CustomerStatusChip extends StatelessWidget {
  const CustomerStatusChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = CustomerStatusTone.neutral,
  });

  final String label;
  final IconData? icon;
  final CustomerStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      CustomerStatusTone.accent => (
          background: AppColors.secondaryLight,
          foreground: AppColors.secondaryForeground,
        ),
      CustomerStatusTone.success => (
          background: AppColors.successLight,
          foreground: AppColors.success,
        ),
      CustomerStatusTone.warning => (
          background: AppColors.warningLight,
          foreground: AppColors.primaryDarker,
        ),
      CustomerStatusTone.error => (
          background: AppColors.errorLight,
          foreground: AppColors.error,
        ),
      CustomerStatusTone.neutral => (
          background: AppColors.g100,
          foreground: AppColors.onSurfaceVariant,
        ),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: colors.foreground),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerDemoModeBanner extends StatelessWidget {
  const CustomerDemoModeBanner({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: 'Modo demonstração. Dados fictícios. Toque para saber mais.',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                icon: const Icon(LucideIcons.flaskConical),
                title: const Text('Modo demonstração'),
                content: const Text(
                  'Os pontos e movimentos apresentados são dados fictícios e '
                  'não representam um saldo real.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Entendi'),
                  ),
                ],
              ),
            ),
            child: const CustomerStatusChip(
              label: 'DEMO · Dados fictícios',
              icon: LucideIcons.flaskConical,
              tone: CustomerStatusTone.accent,
            ),
          ),
        ),
      );
}

class CustomerOfflineBanner extends StatelessWidget {
  const CustomerOfflineBanner({
    super.key,
    this.message = 'Está sem ligação · Os dados podem estar desatualizados',
  });

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: AppColors.primaryDarker,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primaryDarker,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}

class CustomerSectionHeader extends StatelessWidget {
  const CustomerSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primaryDarker,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      );
}

class CustomerPointsBalanceCard extends StatelessWidget {
  const CustomerPointsBalanceCard({
    super.key,
    required this.totalPoints,
    required this.businessCount,
    required this.availableRewardCount,
    required this.onRewards,
    required this.onQr,
  });

  final int totalPoints;
  final int businessCount;
  final int availableRewardCount;
  final VoidCallback onRewards;
  final VoidCallback? onQr;

  @override
  Widget build(BuildContext context) {
    final businessLabel = businessCount == 1 ? 'negócio' : 'negócios';
    final rewardLabel =
        availableRewardCount == 1 ? 'prémio disponível' : 'prémios disponíveis';
    return Semantics(
      label:
          '${formatCustomerPoints(totalPoints)} pontos disponíveis para usar. '
          '$businessCount $businessLabel. '
          '$availableRewardCount $rewardLabel.',
      child: MaisUmSurface(
        radius: AppRadius.xl,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        backgroundGradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDarker, AppColors.primary],
        ),
        borderColor: AppColors.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CARTEIRA MAISUM',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            ExcludeSemantics(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(
                    formatCustomerPoints(totalPoints),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          color: AppColors.white,
                          fontSize: 46,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.8,
                          height: 1,
                        ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      'pts',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Disponíveis para usar',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$businessCount $businessLabel · '
              '$availableRewardCount $rewardLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white.withValues(alpha: 0.76),
                  ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackActions = constraints.maxWidth < 320;
                final rewardsButton = MaisUmButton(
                  label: 'Ver prémios',
                  onPressed: onRewards,
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.primaryDarker,
                  leadingIcon: LucideIcons.gift,
                );
                final qrButton = MaisUmButton(
                  label: 'Meu código',
                  onPressed: onQr,
                  variant: MaisUmButtonVariant.outlined,
                  foregroundColor: AppColors.white,
                  leadingIcon: LucideIcons.qrCode,
                );
                if (stackActions) {
                  return Column(
                    children: [
                      rewardsButton,
                      const SizedBox(height: AppSpacing.sm),
                      qrButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: rewardsButton),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: qrButton),
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

enum CustomerRewardState { available, inProgress, locked, expired }

CustomerRewardState customerRewardState(CustomerReward reward) {
  if (reward.expiresAt != null && !reward.expiresAt!.isAfter(DateTime.now())) {
    return CustomerRewardState.expired;
  }
  if (reward.eligible) return CustomerRewardState.available;
  if (reward.confirmedPoints <= 0) return CustomerRewardState.locked;
  return CustomerRewardState.inProgress;
}

class CustomerRewardCard extends StatelessWidget {
  const CustomerRewardCard({
    super.key,
    required this.reward,
    this.businessName,
    this.onPrimaryAction,
    this.primaryActionLabel,
    this.compact = false,
  });

  final CustomerReward reward;
  final String? businessName;
  final VoidCallback? onPrimaryAction;
  final String? primaryActionLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = customerRewardState(reward);
    final progress = reward.pointsRequired <= 0
        ? 0.0
        : (reward.confirmedPoints / reward.pointsRequired).clamp(0.0, 1.0);
    final status = switch (state) {
      CustomerRewardState.available => (
          label: 'Disponível agora',
          tone: CustomerStatusTone.success,
          icon: LucideIcons.circleCheck,
        ),
      CustomerRewardState.inProgress => (
          label: 'Faltam ${formatCustomerPoints(reward.pointsRemaining)} pts',
          tone: CustomerStatusTone.accent,
          icon: LucideIcons.trendingUp,
        ),
      CustomerRewardState.locked => (
          label:
              '${formatCustomerPoints(reward.pointsRequired)} pontos necessários',
          tone: CustomerStatusTone.neutral,
          icon: LucideIcons.lockKeyhole,
        ),
      CustomerRewardState.expired => (
          label: 'Expirado',
          tone: CustomerStatusTone.error,
          icon: LucideIcons.clockAlert,
        ),
    };
    return MaisUmSurface(
      semanticLabel: '${reward.name}. ${status.label}.',
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      radius: AppRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CustomerIconTile(
                icon: state == CustomerRewardState.available
                    ? LucideIcons.gift
                    : LucideIcons.trophy,
                tone: state == CustomerRewardState.available
                    ? CustomerStatusTone.success
                    : CustomerStatusTone.accent,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (businessName != null) ...[
                      Text(
                        businessName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      reward.name,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primaryDarker,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${formatCustomerPoints(reward.pointsRequired)} pts',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primaryDarker,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          if (reward.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              reward.description!,
              maxLines: compact ? 2 : 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          CustomerStatusChip(
            label: status.label,
            tone: status.tone,
            icon: status.icon,
          ),
          if (state == CustomerRewardState.inProgress ||
              state == CustomerRewardState.available) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: '${formatCustomerPoints(reward.confirmedPoints)} de '
                  '${formatCustomerPoints(reward.pointsRequired)} pontos',
              value: '${(progress * 100).round()} por cento',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${formatCustomerPoints(reward.confirmedPoints)} / '
                          '${formatCustomerPoints(reward.pointsRequired)} pts',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.g100,
                      color: state == CustomerRewardState.available
                          ? AppColors.success
                          : AppColors.secondaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (onPrimaryAction != null &&
              state != CustomerRewardState.expired) ...[
            const SizedBox(height: AppSpacing.lg),
            MaisUmButton(
              label: primaryActionLabel ??
                  (state == CustomerRewardState.available
                      ? 'Resgatar prémio'
                      : 'Ganhar pontos'),
              onPressed: onPrimaryAction,
              variant: state == CustomerRewardState.available
                  ? MaisUmButtonVariant.primary
                  : MaisUmButtonVariant.outlined,
              leadingIcon: state == CustomerRewardState.available
                  ? LucideIcons.ticketCheck
                  : LucideIcons.qrCode,
            ),
          ],
        ],
      ),
    );
  }
}

class CustomerBusinessCard extends StatelessWidget {
  const CustomerBusinessCard({
    super.key,
    required this.business,
    required this.onTap,
    this.compact = false,
  });

  final CustomerBusiness business;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        semanticLabel:
            '${business.name}, ${formatCustomerPoints(business.confirmedPoints)} pontos',
        semanticButton: true,
        onTap: onTap,
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Row(
          children: [
            const _CustomerIconTile(
              icon: LucideIcons.store,
              tone: CustomerStatusTone.accent,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (!compact &&
                      business.address?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      business.address!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCustomerPoints(business.confirmedPoints),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primaryDarker,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text('pts', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
      );
}

class CustomerActivityItem extends StatelessWidget {
  const CustomerActivityItem({
    super.key,
    required this.activity,
    this.businessName,
    this.rewardName,
  });

  final CustomerActivity activity;
  final String? businessName;
  final String? rewardName;

  @override
  Widget build(BuildContext context) {
    final earned = activity.pointsDelta >= 0;
    final contextName = earned ? businessName : (rewardName ?? businessName);
    final movementLabel = earned ? 'Pontos ganhos' : 'Prémio utilizado';
    final date = _formatCustomerDate(activity.occurredAt);
    return MaisUmSurface(
      semanticLabel:
          '${contextName == null ? '' : '$contextName. '}$movementLabel, '
          '${earned ? 'mais' : 'menos'} '
          '${formatCustomerPoints(activity.pointsDelta.abs())} pontos, $date.',
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          _CustomerIconTile(
            icon: earned ? LucideIcons.circlePlus : LucideIcons.ticketCheck,
            tone:
                earned ? CustomerStatusTone.success : CustomerStatusTone.accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contextName ?? movementLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  contextName == null ? date : '$movementLabel · $date',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${earned ? '+' : '-'}${formatCustomerPoints(activity.pointsDelta.abs())} pts',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: earned ? AppColors.success : AppColors.primaryDarker,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class CustomerQrCodeCard extends StatelessWidget {
  const CustomerQrCodeCard({
    super.key,
    required this.token,
    required this.expiresAt,
    this.customerName,
    this.offline = false,
    this.onCopy,
  });

  final String token;
  final DateTime expiresAt;
  final String? customerName;
  final bool offline;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        radius: AppRadius.xl,
        child: Column(
          children: [
            Text(
              'Mostre este código no estabelecimento\npara ganhar pontos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.primaryDarker,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth.clamp(190.0, 260.0);
                return Semantics(
                  image: true,
                  label:
                      'Código QR MaisUm para identificação no estabelecimento',
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.g100),
                    ),
                    child: ExcludeSemantics(
                      child: QrImageView(
                        data: token,
                        version: QrVersions.auto,
                        size: size,
                        eyeStyle: const QrEyeStyle(
                          color: AppColors.primaryDarker,
                          eyeShape: QrEyeShape.square,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          color: AppColors.primaryDarker,
                          dataModuleShape: QrDataModuleShape.square,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            if (customerName?.trim().isNotEmpty == true) ...[
              Text(
                customerName!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            CustomerStatusChip(
              label: offline
                  ? 'Disponível offline'
                  : 'Válido até ${_formatCustomerTime(expiresAt)}',
              icon: offline ? LucideIcons.cloudOff : LucideIcons.shieldCheck,
              tone: offline
                  ? CustomerStatusTone.warning
                  : CustomerStatusTone.success,
            ),
            if (onCopy != null) ...[
              const SizedBox(height: AppSpacing.md),
              MaisUmButton(
                label: 'Copiar código manual',
                onPressed: onCopy,
                variant: MaisUmButtonVariant.ghost,
                leadingIcon: LucideIcons.copy,
              ),
            ],
          ],
        ),
      );
}

class CustomerAccountHeader extends StatelessWidget {
  const CustomerAccountHeader({
    super.key,
    required this.name,
    required this.phone,
    required this.linkedBusinessCount,
  });

  final String name;
  final String phone;
  final int linkedBusinessCount;

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        radius: AppRadius.xl,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CustomerIconTile(
              icon: LucideIcons.userRound,
              tone: CustomerStatusTone.accent,
              size: 52,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primaryDarker,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(phone, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.sm),
                  const CustomerStatusChip(
                    label: 'Conta autenticada por SMS',
                    icon: LucideIcons.badgeCheck,
                    tone: CustomerStatusTone.success,
                  ),
                ],
              ),
            ),
            CustomerStatusChip(
              label: '$linkedBusinessCount',
              icon: LucideIcons.store,
            ),
          ],
        ),
      );
}

class CustomerLoadingState extends StatelessWidget {
  const CustomerLoadingState({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'A carregar conteúdo',
        liveRegion: true,
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => Container(
            height: index == 0 ? 150 : 92,
            decoration: BoxDecoration(
              color: index.isEven
                  ? AppColors.surfaceContainerHigh
                  : AppColors.g100,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
          ),
        ),
      );
}

class CustomerStateView extends StatelessWidget {
  const CustomerStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          liveRegion: error,
          child: MaisUmSurface(
            variant: error
                ? MaisUmSurfaceVariant.error
                : MaisUmSurfaceVariant.standard,
            padding: const EdgeInsets.all(AppSpacing.xxl),
            radius: AppRadius.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CustomerIconTile(
                  icon: icon,
                  tone: error
                      ? CustomerStatusTone.error
                      : CustomerStatusTone.accent,
                  size: 64,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  MaisUmButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    variant: error
                        ? MaisUmButtonVariant.primary
                        : MaisUmButtonVariant.outlined,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class CustomerAppHeader extends StatelessWidget {
  const CustomerAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDarker, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: 'Voltar',
                    color: AppColors.white,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                else
                  const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subtitle!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      AppColors.white.withValues(alpha: 0.78),
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (action != null)
                  IconTheme.merge(
                    data: const IconThemeData(color: AppColors.white),
                    child: action!,
                  ),
              ],
            ),
          ),
        ),
      );
}

class CustomerBottomNavigation extends StatelessWidget {
  const CustomerBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const destinations = [
    NavigationDestination(
      icon: Icon(LucideIcons.house),
      selectedIcon: Icon(LucideIcons.house),
      label: 'Início',
    ),
    NavigationDestination(
      icon: Icon(LucideIcons.gift),
      selectedIcon: Icon(LucideIcons.gift),
      label: 'Prémios',
    ),
    NavigationDestination(
      icon: Icon(LucideIcons.history),
      selectedIcon: Icon(LucideIcons.history),
      label: 'Atividade',
    ),
    NavigationDestination(
      icon: Icon(LucideIcons.store),
      selectedIcon: Icon(LucideIcons.store),
      label: 'Negócios',
    ),
    NavigationDestination(
      icon: Icon(LucideIcons.userRound),
      selectedIcon: Icon(LucideIcons.userRound),
      label: 'Perfil',
    ),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          border: const Border(top: BorderSide(color: AppColors.g100)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDarker.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 72,
            backgroundColor: AppColors.white,
            surfaceTintColor: Colors.transparent,
            indicatorColor: AppColors.secondaryLight,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: selectedIndex,
            destinations: destinations,
            onDestinationSelected: onSelected,
          ),
        ),
      );
}

class _CustomerIconTile extends StatelessWidget {
  const _CustomerIconTile({
    required this.icon,
    required this.tone,
    this.size = 44,
  });

  final IconData icon;
  final CustomerStatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      CustomerStatusTone.success => (
          background: AppColors.successLight,
          foreground: AppColors.success,
        ),
      CustomerStatusTone.error => (
          background: AppColors.errorLight,
          foreground: AppColors.error,
        ),
      CustomerStatusTone.warning => (
          background: AppColors.warningLight,
          foreground: AppColors.primaryDarker,
        ),
      CustomerStatusTone.accent => (
          background: AppColors.secondaryLight,
          foreground: AppColors.primaryDarker,
        ),
      CustomerStatusTone.neutral => (
          background: AppColors.g100,
          foreground: AppColors.onSurfaceVariant,
        ),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: colors.foreground, size: size * 0.5),
    );
  }
}

String _formatCustomerDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatCustomerTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
