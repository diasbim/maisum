import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/design_system.dart';
import '../domain/retention_labels.dart';
import '../domain/retention_metric.dart';
import 'retention_metric_row.dart';

/// One customer who stopped coming back.
///
/// Job: the merchant is scanning the "Em risco" list deciding who to contact
/// first. The card has to answer "how bad is this one?" before it answers
/// anything else — so the days without returning is the hero, the risk level is
/// named in words, and the single action is right there.
class InactiveCustomerCard extends StatelessWidget {
  const InactiveCustomerCard({
    super.key,
    required this.customer,
    required this.onSendReminder,
    this.isSending = false,
  });

  final InactiveCustomerSummary customer;
  final VoidCallback onSendReminder;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final risk = RetentionRiskPresentation.of(customer.riskLevel);

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
              _RiskBadge(risk: risk),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _DaysAway(days: customer.daysInactive, risk: risk),
          const SizedBox(height: AppSpacing.sm),
          Text(
            risk.meaning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RetentionMetricRow(
            label: 'Última visita',
            value: _formatDate(customer.lastVisitAt),
          ),
          RetentionMetricRow(
            label: 'Gasta por visita',
            value: '${customer.averageTicket.toStringAsFixed(0)} MZN',
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: LoadingButton(
              label: 'Lembrar no WhatsApp',
              loadingLabel: 'A preparar lembrete…',
              isLoading: isSending,
              enabled: !isSending,
              onPressed: onSendReminder,
              height: AppControlSize.iconButton,
              radius: AppRadius.md,
              backgroundColor: AppColors.secondary,
              foregroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Abre o WhatsApp com a mensagem escrita. Envia quando quiser.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
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

/// The one number that decides who gets contacted first.
class _DaysAway extends StatelessWidget {
  const _DaysAway({required this.days, required this.risk});

  final int days;
  final RetentionRiskPresentation risk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Sem voltar há $days ${days == 1 ? 'dia' : 'dias'}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$days',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: risk.foreground,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                days == 1 ? 'dia sem voltar' : 'dias sem voltar',
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

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.risk});

  final RetentionRiskPresentation risk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: risk.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(risk.icon, size: 14, color: risk.foreground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            risk.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: risk.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
