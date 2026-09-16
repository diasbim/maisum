import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../design_system/design_system.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../providers/affiliate_providers.dart';
import 'widgets/affiliate_widgets.dart';

/// Whether the affiliate programme is working, in six numbers.
///
/// The conversion rate is the one that can lie. It is confirmed acquisitions
/// over codes tried, so with nothing tried it is `0/0` — and a screen that
/// printed "0%" there would tell an owner their programme is failing when in
/// fact it has not started.
class AffiliateMetricsScreen extends ConsumerWidget {
  const AffiliateMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(affiliateMetricsProvider);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const MaisUmAppBar(
        title: 'Métricas de afiliados',
        fallbackLocation: '/affiliates',
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(affiliateMetricsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            if (!online) ...[
              const AffiliateOfflineNotice(
                message: 'Sem ligação. Os números podem estar desatualizados.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AffiliateAsyncView<AffiliateMetricsSummary>(
              value: metricsAsync,
              loadingLabel: 'A carregar métricas',
              skeletonLines: 3,
              onRetry: () => ref.invalidate(affiliateMetricsProvider),
              builder: (context, metrics) => _MetricsBody(metrics: metrics),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsBody extends StatelessWidget {
  const _MetricsBody({required this.metrics});

  final AffiliateMetricsSummary metrics;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      AffiliateMetricTile(
        key: const Key('metric-referred'),
        label: 'Clientes indicados',
        value: '${metrics.confirmedAttributions}',
        icon: Icons.group_add_rounded,
      ),
      AffiliateMetricTile(
        key: const Key('metric-returned'),
        label: 'Clientes que voltaram',
        value: '${metrics.returnedCustomers}',
        icon: Icons.repeat_rounded,
      ),
      AffiliateMetricTile(
        key: const Key('metric-attempts'),
        label: 'Códigos tentados',
        value: '${metrics.uniqueValidationAttempts}',
        hint: '${metrics.rejectedAttributions} recusados',
        icon: Icons.password_rounded,
      ),
      AffiliateMetricTile(
        key: const Key('metric-conversion'),
        label: 'Taxa de conversão',
        value: _conversionValue,
        hint: _conversionHint,
        icon: Icons.trending_up_rounded,
      ),
      AffiliateMetricTile(
        key: const Key('metric-pending'),
        label: 'Recompensas pendentes',
        value: '${metrics.pendingRewardCount}',
        hint: '${metrics.pendingRewardPoints} pontos por aprovar',
        icon: Icons.pending_actions_rounded,
      ),
      AffiliateMetricTile(
        key: const Key('metric-approved'),
        label: 'Recompensas aprovadas',
        value: '${metrics.approvedRewardCount}',
        hint: '${metrics.approvedRewardPoints} pontos',
        icon: Icons.verified_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.truncated) ...[
          const AffiliateTruncatedBanner(
            detail: 'Estes números são um mínimo: há mais registos do que '
                'conseguimos somar de uma vez.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        // One column, always. Two metric tiles side by side stop fitting at
        // 200% text scale, and a number that wraps mid-digit is worse than a
        // longer page.
        for (final tile in tiles)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: tile,
          ),
        MaisUmSurface(
          variant: MaisUmSurfaceVariant.muted,
          radius: AppRadius.md,
          padding: const EdgeInsets.all(AppSpacing.md),
          animationDuration: Duration.zero,
          child: Text(
            metrics.lastActivityAt == null
                ? 'Ainda não há atividade registada.'
                : 'Última atividade: '
                    '${PtDateFormat.dayMonthYearTime(metrics.lastActivityAt!)}',
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  String get _conversionValue {
    if (!metrics.hasConversionRate) return 'Sem dados';
    return '${(metrics.conversionRate * 100).toStringAsFixed(0)}%';
  }

  String get _conversionHint {
    if (!metrics.hasConversionRate) {
      return 'Nenhum código foi tentado ainda.';
    }
    return '${metrics.confirmedAttributions} de '
        '${metrics.uniqueValidationAttempts} tentativas';
  }
}
