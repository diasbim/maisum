import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../domain/retention_metric.dart';

class InactiveCustomerCard extends StatelessWidget {
  const InactiveCustomerCard({
    super.key,
    required this.customer,
    required this.onSendReminder,
  });

  final InactiveCustomerSummary customer;
  final VoidCallback onSendReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _riskColor(customer.riskLevel).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _riskColor(customer.riskLevel).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  customer.riskLevel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _riskColor(customer.riskLevel),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _MetricRow(
            label: 'Dias sem voltar',
            value: '${customer.daysInactive}',
          ),
          _MetricRow(
            label: 'Ultima visita',
            value: _formatDate(customer.lastVisitAt),
          ),
          _MetricRow(
            label: 'Ticket medio',
            value: '${customer.averageTicket.toStringAsFixed(0)} MZN',
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onSendReminder,
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: const Text('Enviar lembrete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  Color _riskColor(String riskLevel) {
    switch (riskLevel) {
      case RetentionRiskLevel.attention:
        return const Color(0xFFF59E0B);
      case RetentionRiskLevel.risk:
        return const Color(0xFFEF4444);
      case RetentionRiskLevel.lost:
        return const Color(0xFFB91C1C);
      default:
        return AppColors.green;
    }
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
