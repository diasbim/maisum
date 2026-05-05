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
                      _PrimarySaleCard(
                        onTap: () async {
                          await context.push('/new-sale');
                          ref.read(dashboardControllerProvider.notifier).refresh();
                        },
                      ),
                      const SizedBox(height: 28),
                      const _SectionLabel('Atalhos'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniActionTile(
                              label: AppStrings.clientes,
                              subtitle: 'Pesquisar e editar',
                              icon: Icons.people_alt_rounded,
                              onTap: () => context.push('/customers'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniActionTile(
                              label: AppStrings.recompensas,
                              subtitle: 'Definir resgates',
                              icon: Icons.card_giftcard_rounded,
                              onTap: () => context.push('/rewards'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniActionTile(
                              label: AppStrings.historicoVendas,
                              subtitle: 'Conferência rápida',
                              icon: Icons.receipt_long_rounded,
                              onTap: () => context.push('/sales'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniActionTile(
                              label: AppStrings.pendentes,
                              subtitle: '${syncStatus.pendingCount} por sincronizar',
                              icon: syncStatus.pendingCount > 0
                                  ? Icons.cloud_upload_rounded
                                  : Icons.cloud_done_rounded,
                              accent: syncStatus.pendingCount > 0
                                  ? AppColors.amber
                                  : AppColors.green,
                              onTap: () => context.push('/pending-sync'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

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
                'Registe uma venda em segundos e atribua pontos no momento.',
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
                      'Começar agora',
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
    final bg = dark ? AppColors.secondary : AppColors.white;
    final fgStrong = dark ? AppColors.primary : AppColors.onSurface;
    final fgMuted = dark
        ? AppColors.primary.withValues(alpha: 0.55)
        : AppColors.onSurfaceVariant;

    return Container(
  class _MiniActionTile extends StatelessWidget {
    const _MiniActionTile({
        color: bg,
        borderRadius: BorderRadius.circular(18),
      required this.icon,
        border: Border.all(
      this.accent = AppColors.primary,
        boxShadow: dark ? AppTheme.shadowMd : AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
    final IconData icon;
        children: [
    final Color accent;
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.primary.withValues(alpha: 0.12)
        color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const BrandMark(
              size: 18,
              padding: EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          const SizedBox(height: 10),
              border: Border.all(color: AppColors.g100, width: 1.5),
              boxShadow: AppTheme.shadowSm,
            style: GoogleFonts.bricolageGrotesque(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
          ),
          const SizedBox(height: 2),
                  width: 40,
                  height: 40,
            style: Theme.of(context)
                    color: accent.withValues(alpha: 0.1),
            maxLines: 2,
          ),
                  child: Icon(
                    icon,
                    color: accent,
                    size: 20,
  }
}
                const SizedBox(height: 14),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.4,
                  ),
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
