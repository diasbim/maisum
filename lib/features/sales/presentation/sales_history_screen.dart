import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../app/providers.dart';

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
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
            onPressed: () => ref.invalidate(allSalesWithCustomerProvider),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100, width: 1.5),
      ),
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

class _SaleHistoryTile extends StatelessWidget {
  const _SaleHistoryTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      data['created_at'] as int,
    );
    final amount = (data['amount'] as num).toDouble();
    final points = data['points'] as int;
    final customerName = data['customer_name'] as String? ?? 'Cliente';
    final synced = (data['synced'] as int? ?? 0) == 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100, width: 1.5),
      ),
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
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '+$points pts',
                  style: const TextStyle(
                    color: AppColors.secondaryDark,
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
            ],
          ),
        ],
      ),
    );
  }
}
