import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../design_system/design_system.dart';
import '../domain/return_bonus.dart';

/// F1 Bónus de Regresso, shown on the customer detail screen.
///
/// Job: the merchant is looking at this customer (often right after a sale,
/// or while deciding what to say to them) and needs to know, at a glance,
/// whether there is an active return incentive and how long it lasts — so
/// they can mention it, or redeem it on the spot if the customer is buying
/// again right now. Primary action of this card: "Resgatar bónus".
///
/// Renders nothing when there is no active bonus: an empty state here would
/// repeat for every customer without one, which is most customers most of
/// the time, and would compete with the reward-progress panel already
/// covering "nothing to show yet" for the loyalty programme itself.
class ReturnBonusCard extends StatelessWidget {
  const ReturnBonusCard({
    super.key,
    required this.bonus,
    required this.isOnline,
    required this.isRedeeming,
    this.onRedeem,
    this.now,
  });

  final ReturnBonus bonus;
  final bool isOnline;
  final bool isRedeeming;
  final VoidCallback? onRedeem;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTime = now ?? DateTime.now();
    final remaining = bonus.expiresAt.difference(currentTime);
    final isExpired = !bonus.expiresAt.isAfter(currentTime);
    final isExpiringSoon = !isExpired && remaining.inHours < 24;
    final accentColor = isExpired
        ? AppColors.onSurfaceVariant
        : isExpiringSoon
            ? AppColors.warning
            : AppColors.primary;

    final subtitleParts = <String>[
      if (isExpired)
        'Expirou'
      else if (isExpiringSoon)
        'Expira em ${_formatRemaining(remaining)}'
      else
        'Válido até ${PtDateFormat.dayMonthTime(bonus.expiresAt)}',
    ];

    return MaisUmSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      radius: 18,
      borderColor: isExpiringSoon
          ? AppColors.warning.withValues(alpha: 0.35)
          : AppColors.g100,
      shadows: [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 10),
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.redeem_rounded, color: accentColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bónus de Regresso',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _valueLabel(bonus),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleParts.join(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if (!isOnline)
                  Text(
                    'Ligue-se à internet para resgatar',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: LoadingButton(
                      label: 'Resgatar bónus',
                      loadingLabel: 'A resgatar…',
                      isLoading: isRedeeming,
                      enabled: !isExpired && onRedeem != null,
                      onPressed: onRedeem,
                      height: 40,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _valueLabel(ReturnBonus bonus) {
    switch (bonus.type) {
      case ReturnBonusType.discount:
        return '${bonus.value.toStringAsFixed(0)} MT de desconto';
      case ReturnBonusType.extraPoints:
        return '${bonus.value.toStringAsFixed(0)} pontos extra';
      case ReturnBonusType.freeService:
        return 'Serviço grátis';
      default:
        // A bonus type the server added and this build does not know yet:
        // still say something in Portuguese rather than leaking the raw enum.
        return 'Bónus disponível';
    }
  }

  String _formatRemaining(Duration remaining) {
    if (remaining.inHours >= 1) return '${remaining.inHours}h';
    return '${remaining.inMinutes.clamp(1, 59)}min';
  }
}
