import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/design_system.dart';
import '../../../app/providers.dart';
import '../domain/sale.dart';
import 'new_sale_screen.dart';
import 'sale_cancellation_dialog.dart';
import 'package:go_router/go_router.dart';

class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(allSalesWithCustomerProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Histórico de Vendas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allSalesWithCustomerProvider),
          ),
        ],
      ),
      body: salesAsync.when(
        data: (list) => list.isEmpty
            ? const EmptyState(title: 'Nenhuma venda ainda')
            : RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () async =>
                    ref.invalidate(allSalesWithCustomerProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _HistorySummary(totalSales: list.length);
                    }
                    return _SaleHistoryTile(data: list[i - 1]);
                  },
                ),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MaisUmButton(
              label: 'Tentar novamente',
              leadingIcon: Icons.refresh_rounded,
              variant: MaisUmButtonVariant.outlined,
              onPressed: () => ref.invalidate(allSalesWithCustomerProvider),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.totalSales});

  final int totalSales;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MaisUmSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: AppRadius.lg,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalSales vendas registadas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Histórico simples para conferência rápida.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
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

class _SaleHistoryTile extends ConsumerWidget {
  const _SaleHistoryTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      data['created_at'] as int,
    );
    final amount = (data['amount'] as num).toDouble();
    final points = data['points'] as int;
    final customerName = data['customer_name'] as String? ?? 'Cliente';
    final synced = (data['synced'] as int? ?? 0) == 1;
    final sale = saleFromMap(data);
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['name_snapshot'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return MaisUmSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: AppRadius.lg,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${amount.toStringAsFixed(0)} MZN · ${PtDateFormat.dayMonthYearTime(createdAt)}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sale.isCancelled &&
                    sale.cancellationReason?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Motivo: ${sale.cancellationReason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    items.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: sale.isCancelled
                      ? AppColors.error.withValues(alpha: 0.08)
                      : AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  sale.isCancelled ? 'Anulada' : '+$points pts',
                  style: TextStyle(
                    color: sale.isCancelled
                        ? AppColors.error
                        : AppColors.secondaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Icon(
                synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                size: 14,
                color: synced ? AppColors.green : AppColors.amber,
              ),
              if (!sale.isCancelled)
                PopupMenuButton<String>(
                  tooltip: 'Ações da venda',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  onSelected: (value) async {
                    if (value != 'cancel') return;
                    final cancelled =
                        await showSaleCancellationDialog(context, ref, sale);
                    if (!cancelled || !context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Venda anulada com sucesso.'),
                        action: SnackBarAction(
                          label: 'Registar correta',
                          onPressed: () => context.push(
                            '/new-sale',
                            extra: NewSaleArgs(
                              preselectedCustomerId: sale.customerId,
                              replacesSaleId: sale.id,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cancel_outlined),
                        title: Text('Anular venda'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
