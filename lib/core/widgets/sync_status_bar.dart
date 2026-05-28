import 'package:flutter/material.dart';

import '../../features/sync/sync_service.dart';
import '../constants/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../utils/pt_date_format.dart';

class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({
    super.key,
    required this.status,
    required this.isOnline,
    this.onTap,
    this.onRetry,
  });

  final SyncStatus status;
  final bool isOnline;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _foregroundColor();
    final background = _backgroundColor();
    final icon = _icon();
    final title = _title();
    final subtitle = _subtitle();

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: foreground.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: status.isSyncing
                      ? SizedBox(
                          key: const ValueKey('syncing'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: foreground,
                          ),
                        )
                      : Icon(
                          icon,
                          key: ValueKey(icon),
                          color: foreground,
                          size: 18,
                        ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  if (status.viewState == SyncViewState.failed &&
                      onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text(AppStrings.syncRetryNow),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: foreground.withValues(alpha: 0.7),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _foregroundColor() {
    if (!isOnline) {
      return AppColors.offline;
    }
    if (status.viewState == SyncViewState.failed) {
      return AppColors.error;
    }
    if (status.viewState == SyncViewState.syncing) {
      return AppColors.amber;
    }
    if (status.pendingCount > 0) {
      return AppColors.secondaryDark;
    }
    return AppColors.green;
  }

  Color _backgroundColor() {
    if (!isOnline) {
      return AppColors.offlineBg;
    }
    if (status.viewState == SyncViewState.failed) {
      return AppColors.errorContainer;
    }
    if (status.pendingCount > 0 || status.viewState == SyncViewState.syncing) {
      return AppColors.secondaryLight;
    }
    return AppColors.white;
  }

  IconData _icon() {
    if (!isOnline) {
      return Icons.wifi_off_rounded;
    }
    if (status.viewState == SyncViewState.failed) {
      return Icons.sync_problem_rounded;
    }
    if (status.pendingCount > 0) {
      return Icons.cloud_upload_rounded;
    }
    return Icons.cloud_done_rounded;
  }

  String _title() {
    if (!isOnline) {
      return AppStrings.semLigacao;
    }
    if (status.viewState == SyncViewState.failed) {
      return AppStrings.syncInterrompida;
    }
    if (status.viewState == SyncViewState.syncing) {
      return AppStrings.sincronizando;
    }
    if (status.pendingCount > 0) {
      return '${status.pendingCount} ${AppStrings.pendentesSync}';
    }
    return AppStrings.sincronizado;
  }

  String _subtitle() {
    if (!isOnline) {
      return AppStrings.syncOfflineSavedSubtitle;
    }
    if (status.viewState == SyncViewState.failed) {
      return status.lastError ?? AppStrings.syncFailedActionable;
    }
    if (status.viewState == SyncViewState.syncing) {
      return AppStrings.syncRunningSubtitle;
    }
    if (status.pendingCount > 0) {
      return AppStrings.syncPendingSubtitle;
    }
    if (status.lastSyncAt != null) {
      return 'Última sincronização em ${PtDateFormat.dayMonthTime(status.lastSyncAt!)}.';
    }
    return AppStrings.syncReadySubtitle;
  }
}
