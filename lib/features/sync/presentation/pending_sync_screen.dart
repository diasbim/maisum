import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/sync_status_bar.dart';
import '../../../core/constants/app_strings.dart';
import '../../../app/providers.dart';
import '../domain/sync_item.dart';
import '../sync_controller.dart';
import '../sync_service.dart';

class PendingSyncScreen extends ConsumerStatefulWidget {
  const PendingSyncScreen({super.key});

  @override
  ConsumerState<PendingSyncScreen> createState() => _PendingSyncScreenState();
}

class _PendingSyncScreenState extends ConsumerState<PendingSyncScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen<SyncStatus>(syncStatusProvider, (previous, next) {
      final syncFinished = (previous?.isSyncing ?? false) && !next.isSyncing;
      final pendingChanged = previous?.pendingCount != next.pendingCount;
      if (syncFinished || pendingChanged) {
        ref.invalidate(pendingSyncItemsProvider);
      }
    });

    final syncStatus = ref.watch(syncStatusProvider);
    final itemsAsync = ref.watch(pendingSyncItemsProvider);
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

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
      bottomNavigationBar: SyncStatusBar(
        status: syncStatus,
        isOnline: isOnline,
      ),
      body: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            if (syncStatus.lastError != null) {
              return EmptyState(
                title: AppStrings.syncInterrompida,
                subtitle: syncStatus.lastError,
                actionLabel: AppStrings.tentar,
                onAction: () =>
                    ref.read(syncControllerProvider.notifier).sync(),
              );
            }
            return const EmptyState(
              title: 'Fila limpa e pronta.',
              subtitle:
                  'Quando estiver sem internet, as alterações aparecem aqui e seguem automaticamente depois.',
            );
          }
          return RefreshIndicator(
            color: AppColors.secondary,
            onRefresh: () async => ref.invalidate(pendingSyncItemsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _SyncItemTile(
                item: items[i],
                onRetry: items[i].status == 'failed'
                    ? () => ref.read(syncControllerProvider.notifier).sync()
                    : null,
              ),
            ),
          );
        },
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.secondary)),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.read(syncControllerProvider.notifier).sync(),
        ),
      ),
    );
  }
}

class _SyncItemTile extends StatelessWidget {
  const _SyncItemTile({required this.item, this.onRetry});
  final SyncItem item;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    final nextAttempt = item.nextAttemptAt;
    final showNextAttempt =
        nextAttempt != null && isPending && item.retryCount > 0;

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
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(11)),
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
                Text(PtDateFormat.dayMonthTime(item.createdAt),
                    style: theme.textTheme.bodySmall),
                if (item.retryCount > 0)
                  Text(
                    '${item.retryCount} tentativa(s)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.amber),
                  ),
                if (showNextAttempt)
                  Text(
                    'Proxima tentativa: ${PtDateFormat.dayMonthTime(nextAttempt)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isFailed
                      ? AppColors.errorContainer
                      : isPending
                          ? AppColors.secondaryLight
                          : AppColors.g100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFailed
                      ? 'Falhou'
                      : isPending
                          ? 'Pendente'
                          : item.status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isFailed ? AppColors.error : AppColors.secondaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isFailed && onRetry != null) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Tentar agora'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
