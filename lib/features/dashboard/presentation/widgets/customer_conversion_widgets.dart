import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../dashboard_controller.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({
    super.key,
    required this.message,
    required this.icon,
    this.onTap,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScheduledCustomersCarousel extends StatelessWidget {
  const ScheduledCustomersCarousel({
    super.key,
    required this.customers,
    required this.onRegisterSale,
    required this.onOpenCustomer,
    required this.onSendMessage,
  });

  final List<DashboardQuickCustomer> customers;
  final ValueChanged<DashboardQuickCustomer> onRegisterSale;
  final ValueChanged<DashboardQuickCustomer> onOpenCustomer;
  final ValueChanged<DashboardQuickCustomer> onSendMessage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 222,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: customers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) {
          final customer = customers[index];
          return SizedBox(
            width: 272,
            child: CustomerQuickActionCard(
              customer: customer,
              highlightScheduled: true,
              onRegisterSale: () => onRegisterSale(customer),
              onOpenCustomer: () => onOpenCustomer(customer),
              onSendMessage: () => onSendMessage(customer),
            ),
          );
        },
      ),
    );
  }
}

class RecentCustomersSection extends StatelessWidget {
  const RecentCustomersSection({
    super.key,
    required this.customers,
    required this.onRegisterSale,
    required this.onOpenCustomer,
    required this.onSendMessage,
  });

  final List<DashboardQuickCustomer> customers;
  final ValueChanged<DashboardQuickCustomer> onRegisterSale;
  final ValueChanged<DashboardQuickCustomer> onOpenCustomer;
  final ValueChanged<DashboardQuickCustomer> onSendMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: customers
          .map(
            (customer) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CustomerQuickActionCard(
                customer: customer,
                onRegisterSale: () => onRegisterSale(customer),
                onOpenCustomer: () => onOpenCustomer(customer),
                onSendMessage: () => onSendMessage(customer),
              ),
            ),
          )
          .toList(),
    );
  }
}

class CustomerQuickActionCard extends StatelessWidget {
  const CustomerQuickActionCard({
    super.key,
    required this.customer,
    required this.onRegisterSale,
    required this.onOpenCustomer,
    required this.onSendMessage,
    this.highlightScheduled = false,
  });

  final DashboardQuickCustomer customer;
  final VoidCallback onRegisterSale;
  final VoidCallback onOpenCustomer;
  final VoidCallback onSendMessage;
  final bool highlightScheduled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduled = customer.scheduledDate;
    final subtitle = scheduled == null
        ? 'Cliente recente'
        : 'Agendado para ${_formatTime(scheduled)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlightScheduled
              ? AppColors.secondary.withValues(alpha: 0.35)
              : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  customer.customer.name.isEmpty
                      ? 'C'
                      : customer.customer.name[0].toUpperCase(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${customer.customer.totalPoints} pts',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          QuickSaleButton(onPressed: onRegisterSale),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenCustomer,
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: const Text('Ver cliente'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSendMessage,
                  icon: const Icon(Icons.sms_outlined, size: 18),
                  label: const Text('Mensagem'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class QuickSaleButton extends StatelessWidget {
  const QuickSaleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.point_of_sale_rounded, size: 18),
        label: const Text('Registrar venda'),
      ),
    );
  }
}

class EmptyCustomersState extends StatelessWidget {
  const EmptyCustomersState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryAction,
    required this.primaryLabel,
    this.secondaryAction,
    this.secondaryLabel,
  });

  final String title;
  final String subtitle;
  final VoidCallback primaryAction;
  final String primaryLabel;
  final VoidCallback? secondaryAction;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: primaryAction,
                child: Text(primaryLabel),
              ),
              if (secondaryAction != null && secondaryLabel != null)
                OutlinedButton(
                  onPressed: secondaryAction,
                  child: Text(secondaryLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
