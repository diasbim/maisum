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
            expandedHeight: 160,
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
                        const SizedBox(height: 8),
                        Text(
                          'Bom dia! Aqui esta o resumo.',
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 14,
                          ),
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
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
            sliver: SliverToBoxAdapter(
              child: RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () =>
                    ref.read(dashboardControllerProvider.notifier).refresh(),
                child: stats.when(
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Stats grid ────────────────────────────────────────
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
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: AppStrings.totalClientes,
                              value: '${s.totalCustomers}',
                              accent: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => context.push('/pending-sync'),
                              child: _StatCard(
                                label: AppStrings.pendentes,
                                value: '${syncStatus.pendingCount}',
                                accent: syncStatus.pendingCount > 0
                                    ? AppColors.amber
                                    : AppColors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // ── Quick actions ─────────────────────────────────────
                      const _SectionLabel('Acoes rapidas'),
                      const SizedBox(height: 12),
                      _ActionTile(
                        label: AppStrings.novaVenda,
                        subtitle: 'Registe uma venda e atribua pontos',
                        gold: true,
                        onTap: () async {
                          await context.push('/new-sale');
                          ref
                              .read(dashboardControllerProvider.notifier)
                              .refresh();
                        },
                      ),
                      const SizedBox(height: 10),
                      _ActionTile(
                        label: AppStrings.clientes,
                        subtitle: 'Gerir e pesquisar clientes',
                        onTap: () => context.push('/customers'),
                      ),
                      const SizedBox(height: 10),
                      _ActionTile(
                        label: AppStrings.recompensas,
                        subtitle: 'Configurar premios e resgates',
                        onTap: () => context.push('/rewards'),
                      ),
                      const SizedBox(height: 10),
                      _ActionTile(
                        label: AppStrings.historicoVendas,
                        subtitle: 'Ver todas as vendas registadas',
                        onTap: () => context.push('/sales'),
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
    final bg = dark ? AppColors.secondary : AppColors.white;
    final fgStrong = dark ? AppColors.primary : AppColors.onSurface;
    final fgMuted = dark
        ? AppColors.primary.withValues(alpha: 0.55)
        : AppColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: dark ? Colors.transparent : AppColors.g100, width: 1.5),
        boxShadow: dark ? AppTheme.shadowMd : AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const BrandMark(
              size: 18,
              padding: EdgeInsets.all(8),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.bricolageGrotesque(
                fontSize: 22, fontWeight: FontWeight.w800, color: fgStrong),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: fgMuted, letterSpacing: 0),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.gold = false,
  });

  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: gold ? AppColors.primary : AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: gold ? null : Border.all(color: AppColors.g100, width: 1.5),
            boxShadow: gold ? AppTheme.shadowMd : AppTheme.shadowSm,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: gold
                      ? AppColors.secondary
                      : AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const BrandMark(
                  size: 22,
                  padding: EdgeInsets.all(10),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: gold ? Colors.white : AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: gold
                            ? Colors.white.withValues(alpha: 0.55)
                            : AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    gold ? Colors.white.withValues(alpha: 0.6) : AppColors.g300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
