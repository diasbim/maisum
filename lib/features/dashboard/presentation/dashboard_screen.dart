import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/sync_status_bar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_service.dart';
import '../../../app/providers.dart' as app_providers;
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardControllerProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final isOnline =
        ref.watch(app_providers.isOnlineProvider).valueOrNull ?? true;
    final session = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      bottomNavigationBar: SyncStatusBar(
        status: syncStatus,
        isOnline: isOnline,
        onTap: () => context.push('/pending-sync'),
      ),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () =>
            ref.read(dashboardControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _DashboardHeader(
                session: session,
                syncStatus: syncStatus,
                isOnline: isOnline,
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
                    onNewSale: () async {
                      await context.push('/new-sale');
                      ref.read(dashboardControllerProvider.notifier).refresh();
                    },
                  ),
                  loading: () => const SizedBox(
                    height: 220,
                    child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.secondary),
                    ),
                  ),
                  error: (e, _) => EmptyState(
                    title: 'Não foi possível abrir o painel.',
                    subtitle:
                        'Puxe para atualizar ou tente novamente em alguns segundos.',
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
  });

  final dynamic session;
  final SyncStatus syncStatus;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              if (session != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  session.merchantName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _SubscriptionChip(
                      label:
                          _formatSubscriptionStatus(session.subscriptionStatus),
                    ),
                    _HeaderMetaChip(label: session.phone),
                    _SyncStatusChip(
                      status: syncStatus,
                      isOnline: isOnline,
                    ),
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.stats,
    required this.syncStatus,
    required this.onNewSale,
  });

  final DashboardStats stats;
  final SyncStatus syncStatus;
  final VoidCallback onNewSale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showEmpty = stats.totalCustomers == 0 &&
        stats.todaySaleCount == 0 &&
        stats.todayPoints == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrimarySaleCard(onTap: onNewSale),
        const SizedBox(height: AppSpacing.xxl),
        if (showEmpty)
          EmptyState(
            title: 'Tudo pronto para a primeira venda.',
            subtitle:
                'Adicione o primeiro cliente e registe uma venda em menos de 3 toques.',
            actionLabel: AppStrings.adicionarCliente,
            onAction: () => context.push('/customers'),
          )
        else ...[
          const _SectionLabel('Hoje'),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;
              final cardWidth = isNarrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - AppSpacing.md) / 2;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _DailySalesCard(
                      saleCount: stats.todaySaleCount,
                      points: stats.todayPoints,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _MerchantStreakCard(
                      streakDays: stats.streakDays,
                      atRisk: stats.streakAtRisk,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ReturningCustomersCard(
                      count: stats.returningCustomers,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${stats.totalCustomers} clientes registados',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _SectionLabel('Rápido'),
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
                      subtitle: 'Abrir lista',
                      icon: Icons.people_alt_rounded,
                      onTap: () => context.push('/customers'),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _MiniActionTile(
                      label: AppStrings.historicoVendas,
                      subtitle: 'Últimas vendas',
                      icon: Icons.receipt_long_rounded,
                      onTap: () => context.push('/sales'),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _MiniActionTile(
                      label: AppStrings.recompensas,
                      subtitle: 'Criar ou resgatar',
                      icon: Icons.card_giftcard_rounded,
                      onTap: () => context.push('/rewards'),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _MiniActionTile(
                      label: AppStrings.pendentes,
                      subtitle: syncStatus.lastError != null
                          ? AppStrings.syncInterrompida
                          : syncStatus.pendingCount > 0
                              ? '${syncStatus.pendingCount} por enviar'
                              : 'Tudo sincronizado',
                      icon: syncStatus.lastError != null
                          ? Icons.sync_problem_rounded
                          : syncStatus.pendingCount > 0
                              ? Icons.cloud_upload_rounded
                              : Icons.cloud_done_rounded,
                      onTap: () => context.push('/pending-sync'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

String _formatSubscriptionStatus(String status) {
  if (status.trim().isEmpty) {
    return 'Sem estado';
  }
  return status
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
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
      label = 'A tentar novamente';
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
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            boxShadow: AppTheme.shadowMd,
          ),
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
                'Registe em segundos com uma única ação.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Registar venda',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailySalesCard extends StatelessWidget {
  const _DailySalesCard({required this.saleCount, required this.points});

  final int saleCount;
  final int points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            '$saleCount',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.vendasHoje,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '+$points ${AppStrings.pontosHoje.toLowerCase()}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MerchantStreakCard extends StatelessWidget {
  const _MerchantStreakCard({required this.streakDays, required this.atRisk});

  final int streakDays;
  final bool atRisk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = streakDays == 1 ? 'dia seguido' : 'dias seguidos';
    final status = atRisk ? 'Em risco' : 'Estável';
    final statusColor = atRisk ? AppColors.amber : AppColors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_fire_department_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            '$streakDays',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primary.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: theme.textTheme.labelSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturningCustomersCard extends StatelessWidget {
  const _ReturningCustomersCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.repeat_rounded,
                color: AppColors.secondaryDark, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            '$count',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Clientes recorrentes',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.accent,
    this.dark = false,
  });

  final String label;
  final String value;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = dark ? AppColors.secondary : AppColors.white;
    final valueColor = dark ? AppColors.primary : AppColors.onSurface;
    final labelColor = dark
        ? AppColors.primary.withValues(alpha: 0.62)
        : AppColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? AppColors.secondary.withValues(alpha: 0.2)
              : AppColors.g100,
        ),
        boxShadow: dark ? AppTheme.shadowMd : AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const BrandMark(size: 18, padding: EdgeInsets.all(8)),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(height: 14),
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
