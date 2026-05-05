import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/sync_indicator.dart';
import '../../sync/sync_controller.dart';
import '../../../app/providers.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardControllerProvider);
    final syncStatus = ref.watch(syncControllerProvider);
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: CustomScrollView(
        slivers: [
          // ── Navy SliverAppBar ─────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppColors.primary,
            expandedHeight: 112,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Image.asset(
                                  'assets/images/logo.png',
                                  width: 34,
                                  height: 34,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  AppStrings.appName,
                                  style: GoogleFonts.bricolageGrotesque(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                SyncIndicator(
                                  state: syncStatus.isSyncing
                                      ? SyncState.syncing
                                      : syncStatus.pendingCount > 0
                                          ? SyncState.pending
                                          : SyncState.idle,
                                  pendingCount: syncStatus.pendingCount,
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.settings_outlined,
                                      color: Colors.white),
                                  onPressed: () => context.push('/settings'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Offline banner ────────────────────────────────────────────────
          SliverToBoxAdapter(child: OfflineBanner(visible: !isOnline)),

          // ── Body ─────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            sliver: SliverToBoxAdapter(
              child: RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () =>
                    ref.read(dashboardControllerProvider.notifier).refresh(),
                child: stats.when(
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PrimarySaleCard(
                        onTap: () async {
                          await context.push('/new-sale');
                          ref
                              .read(dashboardControllerProvider.notifier)
                              .refresh();
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('Hoje'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: AppStrings.vendasHoje,
                              value: '${s.todaySaleCount}',
                              accent: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: AppStrings.pontosHoje,
                              value: '${s.todayPoints}',
                              accent: AppColors.secondary,
                              dark: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${s.totalCustomers} clientes registados',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 24),
                      const _SectionLabel('Rápido'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniActionTile(
                              label: AppStrings.clientes,
                              subtitle: 'Abrir lista',
                              icon: Icons.people_alt_rounded,
                              onTap: () => context.push('/customers'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniActionTile(
                              label: AppStrings.historicoVendas,
                              subtitle: 'Últimas vendas',
                              icon: Icons.receipt_long_rounded,
                              onTap: () => context.push('/sales'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => context.push('/pending-sync'),
                              icon: Icon(
                                syncStatus.pendingCount > 0
                                    ? Icons.cloud_upload_rounded
                                    : Icons.cloud_done_rounded,
                                color: syncStatus.pendingCount > 0
                                    ? AppColors.amber
                                    : AppColors.green,
                              ),
                              label: Text(
                                '${AppStrings.pendentes}: ${syncStatus.pendingCount}',
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => context.push('/rewards'),
                              icon: const Icon(
                                Icons.card_giftcard_rounded,
                                color: AppColors.primary,
                              ),
                              label: const Text(AppStrings.recompensas),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  loading: () => const SizedBox(
                    height: 200,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.secondary)),
                  ),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 40),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text(AppStrings.tentar),
                          onPressed: () => ref
                              .read(dashboardControllerProvider.notifier)
                              .refresh(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
            child: const BrandMark(
              size: 18,
              padding: EdgeInsets.all(8),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.bricolageGrotesque(
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
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                label,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
