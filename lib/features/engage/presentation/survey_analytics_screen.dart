import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../providers/engage_providers.dart';

class SurveyAnalyticsScreen extends ConsumerWidget {
  const SurveyAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(engageAccessProvider);
    final analyticsAsync = ref.watch(engageSurveyAnalyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Análise de questionários'),
        backgroundColor: AppColors.offWhite,
        elevation: 0,
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => const EmptyState(
          title: 'Não foi possível validar o acesso',
          subtitle: 'Tente novamente em alguns segundos.',
        ),
        data: (access) {
          if (!access.canManageSurveys) {
            return EmptyState(
              title: 'Análises indisponíveis no seu plano',
              subtitle:
                  'A análise completa dos questionários é exclusiva do plano Business.',
              actionLabel: 'Falar no WhatsApp',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageManageSurveys,
                  featureName: 'Análise de questionários',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }

          return analyticsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => EmptyState(
              title: 'Não foi possível carregar as análises',
              subtitle: 'Atualize para tentar novamente.',
              actionLabel: 'Atualizar',
              onAction: () =>
                  ref.read(engageSurveyAnalyticsProvider.notifier).refresh(),
            ),
            data: (analytics) => ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                _MetricCard(
                  title: 'Taxa de resposta',
                  value: '${analytics.responseRate.toStringAsFixed(1)}%',
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetricCard(
                  title: 'Satisfação dos clientes',
                  value: analytics.customerSatisfaction.toStringAsFixed(1),
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetricCard(
                  title: 'Total de respostas',
                  value: '${analytics.responsesTotal}',
                ),
                const SizedBox(height: AppSpacing.lg),
                _ListCard(
                  title: 'Principais motivos para não voltar',
                  items: analytics.topChurnReasons,
                ),
                const SizedBox(height: AppSpacing.md),
                _ListCard(
                  title: 'Motivos que promovem o regresso',
                  items: analytics.topRecoveryIncentives,
                ),
                const SizedBox(height: AppSpacing.md),
                _ListCard(
                  title: 'Desempenho da equipa',
                  items: analytics.staffRatings,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              const Text('Sem dados suficientes ainda.')
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('• $item'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
