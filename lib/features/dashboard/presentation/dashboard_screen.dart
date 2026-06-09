import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/sync_status_bar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_service.dart';
import '../../../app/providers.dart' as app_providers;
import 'dashboard_controller.dart';
import 'widgets/customer_conversion_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardControllerProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final isOnline =
        ref.watch(app_providers.isOnlineProvider).valueOrNull ?? true;
    final session = ref.watch(authControllerProvider).valueOrNull;
    final statsValue = stats.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      bottomNavigationBar: SyncStatusBar(
        status: syncStatus,
        isOnline: isOnline,
        onTap: () => context.push('/pending-sync'),
        onRetry: () => ref.read(syncControllerProvider.notifier).sync(),
      ),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () async {
          HapticFeedback.selectionClick();
          await ref.read(dashboardControllerProvider.notifier).refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _DashboardHeader(
                session: session,
                syncStatus: syncStatus,
                isOnline: isOnline,
                stats: statsValue,
              ),
            ),
            if (!isOnline)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    0,
                  ),
                  child: _OfflineStatusBanner(),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xxxl,
              ),
              sliver: SliverToBoxAdapter(
                child: stats.when(
                  data: (s) => _DashboardBody(
                    stats: s,
                    syncStatus: syncStatus,
                    onRetrySync: () =>
                        ref.read(syncControllerProvider.notifier).sync(),
                    onNewSale: () async {
                      await _handleNewSaleEntry(context, ref);
                    },
                  ),
                  loading: () => const _DashboardBodySkeleton(),
                  error: (e, _) => EmptyState(
                    title: AppStrings.dashboardLoadErrorTitle,
                    subtitle: AppStrings.dashboardLoadErrorSubtitle,
                    actionLabel: AppStrings.tentar,
                    onAction: () => ref
                        .read(dashboardControllerProvider.notifier)
                        .refresh(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.session,
    required this.syncStatus,
    required this.isOnline,
    required this.stats,
  });

  final dynamic session;
  final SyncStatus syncStatus;
  final bool isOnline;
  final DashboardStats? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final merchantName = session?.merchantName?.toString().trim();
    final greetingName = merchantName == null || merchantName.isEmpty
        ? AppStrings.dashboardGreetingFallback
        : merchantName;
    final salesToday = stats?.todaySaleCount ?? 0;
    final pointsToday = stats?.todayPoints ?? 0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          width: 36,
                          height: 36,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            AppStrings.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppStrings.dashboardGreetingPrefix} $greetingName',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          AppStrings.dashboardGreetingSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _HeaderTodaySummaryCard(
                    salesToday: salesToday,
                    pointsToday: pointsToday,
                  ),
                ],
              ),
              if (session != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _SubscriptionChip(
                      label: _formatSubscriptionStatus(
                        session.subscriptionStatus,
                      ),
                    ),
                    _HeaderMetaChip(
                      label: MozPhoneUtils.maskForDisplay(session.phone),
                    ),
                    _SyncStatusChip(status: syncStatus, isOnline: isOnline),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.stats,
    required this.syncStatus,
    required this.onRetrySync,
    required this.onNewSale,
  });

  final DashboardStats stats;
  final SyncStatus syncStatus;
  final VoidCallback onRetrySync;
  final VoidCallback onNewSale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrimarySaleCard(onTap: onNewSale),
        if (syncStatus.viewState == SyncViewState.failed) ...[
          const SizedBox(height: AppSpacing.lg),
          SyncStatusBanner(
            message: syncStatus.lastError ??
                'A sincronização falhou. Toque para tentar novamente.',
            icon: Icons.sync_problem_rounded,
            onTap: onRetrySync,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        const _SectionLabel('Atalhos'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            final tileWidth = isNarrow
                ? constraints.maxWidth
                : (constraints.maxWidth - AppSpacing.md) / 2;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _MiniActionTile(
                    label: AppStrings.clientes,
                    subtitle: AppStrings.dashboardQuickClientsSubtitle,
                    icon: Icons.people_alt_rounded,
                    onTap: () => context.push('/customers'),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MiniActionTile(
                    label: AppStrings.recompensas,
                    subtitle: AppStrings.dashboardQuickRewardsSubtitle,
                    icon: Icons.card_giftcard_rounded,
                    onTap: () => context.push('/rewards'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

Future<void> _handleNewSaleEntry(BuildContext context, WidgetRef ref) async {
  final customersCount =
      await ref.read(app_providers.customerRepositoryProvider).count();

  if (customersCount == 0) {
    try {
      unawaited(
        ref
            .read(app_providers.analyticsServiceProvider)
            .record(
              eventType: 'customer_required_modal_shown',
              source: 'dashboard',
            )
            .catchError((_) {}),
      );
    } catch (_) {
      // Keep modal flow working even if analytics is unavailable.
    }

    if (!context.mounted) return;
    final shouldCreateCustomer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nenhum cliente registado'),
        content: const Text(
          'Para registrar uma venda,\nprimeiro precisa adicionar um cliente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Adicionar Cliente'),
          ),
        ],
      ),
    );

    if (shouldCreateCustomer == true && context.mounted) {
      final targetRoute = Uri.encodeComponent('/new-sale');
      await context.push(
        '/customers/create?resumeSaleFlow=1&returnTo=$targetRoute',
      );
      if (context.mounted) {
        ref.read(dashboardControllerProvider.notifier).refresh();
      }
    }
    return;
  }

  try {
    await ref.read(app_providers.analyticsServiceProvider).record(
      eventType: 'sale_registration_started',
      source: 'dashboard',
      properties: {'entry_point': 'primary_sale_card'},
    );
  } catch (_) {
    // Do not block the sale flow if analytics fails.
  }
  if (!context.mounted) return;
  await context.push('/new-sale');
  if (!context.mounted) return;
  ref.read(dashboardControllerProvider.notifier).refresh();
}

String _formatSubscriptionStatus(String status) {
  if (status.trim().isEmpty) {
    return AppStrings.subscriptionNoStatus;
  }
  return status
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _formatStreakLabel(int days) {
  final suffix = days == 1
      ? AppStrings.dashboardStreakDaySingular
      : AppStrings.dashboardStreakDayPlural;
  return '$days $suffix';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
      );
}

class _SubscriptionChip extends StatelessWidget {
  const _SubscriptionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _HeaderMetaChip extends StatelessWidget {
  const _HeaderMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _HeaderTodaySummaryCard extends StatelessWidget {
  const _HeaderTodaySummaryCard({
    required this.salesToday,
    required this.pointsToday,
  });

  final int salesToday;
  final int pointsToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.vendasHoje,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$salesToday vendas',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.pontosHoje,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$pointsToday ${AppStrings.pontosAbrev}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineStatusBanner extends StatelessWidget {
  const _OfflineStatusBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.semLigacao,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.status, required this.isOnline});

  final SyncStatus status;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;

    if (!isOnline) {
      label = AppStrings.offline;
      bg = Colors.white.withValues(alpha: 0.12);
      fg = Colors.white;
    } else if (status.lastError != null) {
      label = AppStrings.syncInterrompida;
      bg = AppColors.errorContainer.withValues(alpha: 0.9);
      fg = AppColors.error;
    } else if (status.phase == SyncPhase.retrying) {
      label = AppStrings.syncRetrying;
      bg = Colors.white.withValues(alpha: 0.18);
      fg = Colors.white;
    } else if (status.isSyncing) {
      label = AppStrings.sincronizando;
      bg = Colors.white.withValues(alpha: 0.2);
      fg = Colors.white;
    } else if (status.pendingCount > 0) {
      label = '${status.pendingCount} ${AppStrings.pendentesSync}';
      bg = Colors.white.withValues(alpha: 0.2);
      fg = Colors.white;
    } else {
      label = AppStrings.sincronizado;
      bg = Colors.white.withValues(alpha: 0.16);
      fg = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PrimarySaleCard extends StatelessWidget {
  const _PrimarySaleCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final artWidth = constraints.maxWidth < 360 ? 110.0 : 140.0;
        return Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 280),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                boxShadow: AppTheme.shadowMd,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned(
                      right: -28,
                      top: -36,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 14,
                      bottom: 16,
                      child: _SaleIllustrationBadge(),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(22, 22, artWidth, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.add_shopping_cart_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            AppStrings.novaVenda,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppStrings.dashboardSaleCardSubtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppStrings.dashboardSaleCta,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SaleIllustrationBadge extends StatelessWidget {
  const _SaleIllustrationBadge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
        ),
        Positioned(
          right: -6,
          bottom: -6,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.secondary, width: 1.4),
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 16,
              color: AppColors.secondaryDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _DailySalesCard extends StatelessWidget {
  const _DailySalesCard({required this.saleCount, required this.points});

  final int saleCount;
  final int points;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      icon: Icons.bar_chart_rounded,
      iconBg: AppColors.primary.withValues(alpha: 0.12),
      iconColor: AppColors.primary,
      value: '$saleCount',
      label: AppStrings.vendasHoje,
      helper: '+$points ${AppStrings.pontosAbrev}',
      helperColor: AppColors.secondaryDark,
    );
  }
}

class _PointsTodayCard extends StatelessWidget {
  const _PointsTodayCard({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      icon: Icons.stars_rounded,
      iconBg: AppColors.secondaryLight,
      iconColor: AppColors.secondaryDark,
      value: '$points',
      label: AppStrings.pontosHoje,
    );
  }
}

class _TotalCustomersCard extends StatelessWidget {
  const _TotalCustomersCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      icon: Icons.people_alt_rounded,
      iconBg: AppColors.primary.withValues(alpha: 0.1),
      iconColor: AppColors.primary,
      value: '$count',
      label: AppStrings.totalClientes,
      helper: AppStrings.dashboardRegistered,
    );
  }
}

class _ReturningCustomersCard extends StatelessWidget {
  const _ReturningCustomersCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      icon: Icons.repeat_rounded,
      iconBg: AppColors.secondary.withValues(alpha: 0.15),
      iconColor: AppColors.secondaryDark,
      value: '$count',
      label: AppStrings.dashboardReturningCustomers,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
    this.helper,
    this.helperColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String label;
  final String? helper;
  final Color? helperColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 152),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100, width: 1.2),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Text(
              value,
              key: ValueKey<String>(value),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(
              helper!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: helperColor ?? AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else
            const SizedBox(height: 22),
        ],
      ),
    );
  }
}

class _DashboardBodySkeleton extends StatelessWidget {
  const _DashboardBodySkeleton();

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonBlock(height: 180, radius: AppRadius.xl),
          const SizedBox(height: AppSpacing.xxl),
          const _SkeletonBlock(height: 10, width: 72, radius: AppRadius.sm),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - AppSpacing.md) / 2;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: List.generate(
                  4,
                  (_) => _SkeletonBlock(
                    width: cardWidth,
                    height: 152,
                    radius: AppRadius.lg,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SkeletonBlock(height: 84, radius: AppRadius.lg),
        ],
      ),
    );
  }
}

class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final color = Color.lerp(
          AppColors.g100,
          Colors.white,
          _controller.value,
        )!;
        return ColoredBox(
          color: Colors.transparent,
          child: Theme(
            data: Theme.of(context).copyWith(cardColor: color),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: color),
              child: IconTheme.merge(
                data: IconThemeData(color: color),
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    required this.radius,
    this.width,
  });

  final double height;
  final double radius;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final pulseColor = Theme.of(context).cardColor;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: pulseColor,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _StreakBanner extends StatelessWidget {
  const _StreakBanner({required this.streakDays, required this.atRisk});

  final int streakDays;
  final bool atRisk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = atRisk
        ? AppStrings.dashboardStreakStatusRisk
        : AppStrings.dashboardStreakStatusStable;
    final statusColor = atRisk ? AppColors.amber : AppColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.dashboardStreakTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatStreakLabel(streakDays),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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

class _MiniActionTile extends StatelessWidget {
  const _MiniActionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.g100, width: 1.5),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 20),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.g300,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
