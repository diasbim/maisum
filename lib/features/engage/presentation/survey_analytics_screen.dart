import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class SurveyAnalyticsScreen extends ConsumerWidget {
  const SurveyAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(engageAccessProvider);
    final analyticsAsync = ref.watch(engageSurveyAnalyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: 'Resultados dos questionários',
        fallbackLocation: '/engage',
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
              actionLabel: 'Ver opções',
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
            data: (analytics) {
              if (analytics.responsesTotal == 0) {
                return const EmptyState(
                  title: 'Ainda sem respostas',
                  subtitle:
                      'Assim que registar a primeira resposta a um questionário, '
                      'os resultados aparecem aqui.',
                );
              }

              return RefreshIndicator(
                color: AppColors.secondaryDark,
                onRefresh: () =>
                    ref.read(engageSurveyAnalyticsProvider.notifier).refresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    _MetricCard(
                      title: 'Total de respostas',
                      value: '${analytics.responsesTotal}',
                      caption:
                          '${_decimal(analytics.responsesPerSurvey)} por questionário ativo',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _MetricCard(
                      title: 'Satisfação média',
                      value: analytics.ratedResponses == 0
                          ? '—'
                          : _decimal(analytics.customerSatisfaction),
                      // An average of one rating must not look as solid as an
                      // average of fifty, so the count is always alongside it.
                      caption: analytics.ratedResponses == 0
                          ? 'Nenhuma pergunta de nota respondida ainda'
                          : 'Média de ${analytics.ratedResponses} '
                              '${analytics.ratedResponses == 1 ? 'nota' : 'notas'} de 1 a 5',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _TopAnswersCard(answers: analytics.topAnswers),
                    const SizedBox(height: AppSpacing.md),
                    _RatingBreakdownCard(
                      breakdown: analytics.ratingBreakdown,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    this.caption,
  });

  final String title;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                caption!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What customers picked most often, with the count beside it — "Preço" alone
/// says nothing about whether two people said it or forty.
class _TopAnswersCard extends StatelessWidget {
  const _TopAnswersCard({required this.answers});

  final List<SurveyAnswerTally> answers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount = answers.isEmpty
        ? 0
        : answers.map((a) => a.count).reduce((a, b) => a > b ? a : b);

    return _SectionCard(
      title: 'Respostas mais escolhidas',
      subtitle: 'Só das perguntas com opções.',
      emptyMessage:
          'Ainda sem respostas a perguntas de escolha. Acrescente uma pergunta '
          'com opções para ver os motivos mais comuns.',
      isEmpty: answers.isEmpty,
      children: [
        for (final answer in answers)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Semantics(
              label: '${answer.label}: ${answer.count} '
                  '${answer.count == 1 ? 'resposta' : 'respostas'}',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            answer.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${answer.count}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: maxCount == 0 ? 0 : answer.count / maxCount,
                        minHeight: 6,
                        backgroundColor: AppColors.g100,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.secondaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The spread behind the average: a 3.0 made of 1s and 5s is a different shop
/// from a 3.0 where everybody said 3.
class _RatingBreakdownCard extends StatelessWidget {
  const _RatingBreakdownCard({required this.breakdown});

  final List<SurveyRatingTally> breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = {for (final tally in breakdown) tally.score: tally.count};
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);

    return _SectionCard(
      title: 'Distribuição das notas',
      subtitle: 'Quantas pessoas deram cada nota.',
      emptyMessage:
          'Ainda sem notas. Acrescente uma pergunta de nota de 1 a 5 a um '
          'questionário para acompanhar a satisfação.',
      isEmpty: total == 0,
      children: [
        for (var score = 5; score >= 1; score--)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Semantics(
              label: 'Nota $score: ${counts[score] ?? 0} de $total',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '$score',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : (counts[score] ?? 0) / total,
                          minHeight: 8,
                          backgroundColor: AppColors.g100,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.secondaryDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${counts[score] ?? 0}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.isEmpty,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final bool isEmpty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (isEmpty)
              Text(
                emptyMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.4,
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

/// One decimal place with the Portuguese separator. `toStringAsFixed` always
/// emits a point, which reads as a thousands separator here.
String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
