import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../app/providers.dart';
import '../domain/sync_item.dart';
import '../sync_controller.dart';

class PendingSyncScreen extends ConsumerWidget {
  const PendingSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncControllerProvider);
    final itemsAsync = ref.watch(pendingSyncItemsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Sincronização'),
        actions: [
          if (syncStatus.isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'Sincronizar agora',
              onPressed: () async {
                await ref.read(syncControllerProvider.notifier).sync();
                ref.invalidate(pendingSyncItemsProvider);
              },
            ),
        ],
      ),
      body: itemsAsync.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.cloud_done_rounded,
                title: 'Tudo sincronizado!',
              )
            : RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () async =>
                    ref.invalidate(pendingSyncItemsProvider),
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _SyncItemTile(item: items[i]),
                ),
              ),
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.secondary)),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }
}

class _SyncItemTile extends StatelessWidget {
  const _SyncItemTile({required this.item});
  final SyncItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('dd MMM, HH:mm', 'pt');
    final isPending = item.status == 'pending';
    final isFailed = item.status == 'failed';

    IconData icon;
    Color iconColor;
    Color iconBg;
    String typeLabel;

    switch (item.entityType) {
      case 'sale':
        icon = Icons.receipt_rounded;
        iconColor = AppColors.primary;
        iconBg = AppColors.primary.withValues(alpha: 0.07);
        typeLabel = 'Venda';
        break;
      case 'customer':
        icon = Icons.person_rounded;
        iconColor = AppColors.secondaryDark;
        iconBg = AppColors.secondaryLight;
        typeLabel = 'Cliente';
        break;
      default:
        icon = Icons.sync_rounded;
        iconColor = AppColors.g500;
        iconBg = AppColors.g100;
        typeLabel = item.entityType;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFailed
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.g100,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$typeLabel · ${item.operation}',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: AppColors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(fmt.format(item.createdAt),
                    style: theme.textTheme.bodySmall),
                if (item.retryCount > 0)
                  Text(
                    '${item.retryCount} tentativa(s)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.amber),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isFailed
                  ? AppColors.errorContainer
                  : isPending
                      ? AppColors.secondaryLight
                      : AppColors.g100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isFailed ? 'Falhou' : isPending ? 'Pendente' : item.status,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isFailed ? AppColors.error : AppColors.secondaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
