import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/design_system.dart';
import '../domain/retention_labels.dart';
import '../domain/retention_metric.dart';
import 'retention_metric_row.dart';

/// One customer who keeps coming back.
///
/// Job: the merchant is scanning the "Fiéis" list to know who deserves the
/// good treatment. The hero is how often the customer returns, because that is
/// the habit the loyalty programme is trying to protect.
class RecurringCustomerCard extends StatelessWidget {
  const RecurringCustomerCard({
    super.key,
    required this.customer,
  });

  final RecurringCustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = RecurringBadgePresentation.of(customer);

    return MaisUmSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadius.card,
      borderColor: AppColors.g100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  customer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _LoyaltyBadge(badge: badge),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _VisitRhythm(customer: customer),
          const SizedBox(height: AppSpacing.sm),
          Text(
            badge.meaning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RetentionMetricRow(
            label: 'Visitas até hoje',
            value: '${customer.totalVisits}',
          ),
          RetentionMetricRow(
            label: 'Última visita',
            value: _formatDate(customer.lastVisitAt),
          ),
          RetentionMetricRow(
            label: 'Já gastou',
            value: '${customer.totalSpent.toStringAsFixed(0)} MZN',
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Sem registo';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }
}

/// How often this customer comes back — the habit worth protecting.
class _VisitRhythm extends StatelessWidget {
  const _VisitRhythm({required this.customer});

  final RecurringCustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interval = customer.averageVisitInterval;

    if (interval <= 0) {
      return Text(
        'Ainda a formar um padrão de visitas',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      );
    }

    return Semantics(
      label: 'Volta a cada $interval ${interval == 1 ? 'dia' : 'dias'}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Volta a cada',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$interval',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.greenDark,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                interval == 1 ? 'dia' : 'dias',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoyaltyBadge extends StatelessWidget {
  const _LoyaltyBadge({required this.badge});

  final RecurringBadgePresentation badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 14, color: AppColors.secondaryForeground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            badge.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.secondaryForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
