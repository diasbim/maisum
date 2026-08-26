import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class EngageDashboardScreen extends ConsumerWidget {
  const EngageDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(engageAccessProvider);
    final overviewAsync = ref.watch(engageOverviewProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: 'MaisUm Engage',
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => EmptyState(
          title: 'Não foi possível carregar o Engage',
          subtitle: 'Verifique a ligação e tente novamente.',
          actionLabel: 'Tentar de novo',
          onAction: () => ref.invalidate(engageAccessProvider),
        ),
        data: (access) {
          if (access.isBlocked) {
            return EmptyState(
              title: 'Engage indisponível no seu plano',
              subtitle:
                  'Atualize para Pro ou Business para acompanhar risco e recuperar clientes.',
              actionLabel: 'Ver opções',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageViewRisk,
                  featureName: 'MaisUm Engage',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }

          return overviewAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => EmptyState(
              title: 'Não foi possível carregar os dados do Engage',
              subtitle: 'Tente novamente para atualizar risco e fila.',
              actionLabel: 'Atualizar',
              onAction: () =>
                  ref.read(engageOverviewProvider.notifier).refresh(),
            ),
            data: (overview) => RefreshIndicator(
              color: AppColors.secondary,
              onRefresh: () =>
                  ref.read(engageOverviewProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  if (access.isReadOnly)
                    const _ReadOnlyBanner(
                      text:
                          'Plano Pro: visualização ativa. Ações de recuperação e visitas exigem o plano Business.',
                    )
                  else
                    const _ReadOnlyBanner(
                      text:
                          'Plano Business: acesso completo a recuperação, visitas e questionários do Engage.',
                      isSuccess: true,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  _KpiCard(
                    title: 'Clientes em risco',
                    value: '${overview.dashboard.customersAtRisk}',
                    subtitle:
                        '${overview.dashboard.customersActive} clientes ativos',
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _KpiCard(
                    title: 'Clientes críticos',
                    value: '${overview.dashboard.criticalCustomers}',
                    subtitle:
                        'Receita em risco: ${_formatMoney(overview.dashboard.revenueAtRisk)}',
                    icon: Icons.crisis_alert_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _KpiCard(
                    title: 'Clientes recuperados',
                    value: '${overview.dashboard.recoveredCustomers}',
                    subtitle: 'Atualizado com dados locais',
                    icon: Icons.favorite_rounded,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ActionCard(
                    title: 'Fila de recuperação',
                    subtitle: access.canManageRecovery
                        ? 'Criar e executar tarefas de recuperação.'
                        : 'Somente leitura no plano atual.',
                    icon: Icons.playlist_add_check_circle_outlined,
                    enabled: access.canManageRecovery,
                    onTap: () => access.canManageRecovery
                        ? context.push('/engage/actions')
                        : context.push(featureUpsellLocation(
                            featureKey: FeatureKeys.engageManageRecovery,
                            featureName: 'Fila de recuperação',
                            reason: 'plan_restricted',
                          )),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActionCard(
                    title: 'Relatórios de visitas',
                    subtitle: access.canManageVisits
                        ? 'Registar visitas e resultados de recuperação.'
                        : 'Disponível apenas no plano Business.',
                    icon: Icons.assignment_turned_in_outlined,
                    enabled: access.canManageVisits,
                    onTap: () => access.canManageVisits
                        ? context.push('/engage/visit-report')
                        : context.push(featureUpsellLocation(
                            featureKey: FeatureKeys.engageManageVisits,
                            featureName: 'Relatórios de visitas',
                            reason: 'plan_restricted',
                          )),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActionCard(
                    title: 'Criar questionário',
                    subtitle: access.canManageSurveys
                        ? 'Criação rápida com modelos e um máximo de 5 perguntas.'
                        : 'Disponível apenas no plano Business.',
                    icon: Icons.quiz_outlined,
                    enabled: access.canManageSurveys,
                    onTap: () => access.canManageSurveys
                        ? context.push('/engage/surveys/new')
                        : context.push(featureUpsellLocation(
                            featureKey: FeatureKeys.engageManageSurveys,
                            featureName: 'Criar questionário',
                            reason: 'plan_restricted',
                          )),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActionCard(
                    title: 'Submeter resposta ao questionário',
                    subtitle: access.canManageSurveys
                        ? 'Envio manual para o fluxo de recuperação e acompanhamento.'
                        : 'Disponível apenas no plano Business.',
                    icon: Icons.send_outlined,
                    enabled: access.canManageSurveys,
                    onTap: () => access.canManageSurveys
                        ? context.push('/engage/surveys/respond')
                        : context.push(featureUpsellLocation(
                            featureKey: FeatureKeys.engageManageSurveys,
                            featureName: 'Submeter resposta ao questionário',
                            reason: 'plan_restricted',
                          )),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActionCard(
                    title: 'Análise de questionários',
                    subtitle:
                        'Taxa de resposta, satisfação e principais motivos.',
                    icon: Icons.insights_outlined,
                    enabled: access.canManageSurveys,
                    onTap: () => access.canManageSurveys
                        ? context.push('/engage/surveys/analytics')
                        : context.push(featureUpsellLocation(
                            featureKey: FeatureKeys.engageManageSurveys,
                            featureName: 'Análise de questionários',
                            reason: 'plan_restricted',
                          )),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Tarefas pendentes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (overview.pendingTasks.isEmpty)
                    const EmptyState(
                      title: 'Nenhuma tarefa pendente',
                      subtitle:
                          'Escolha um cliente prioritário para iniciar a recuperação.',
                    )
                  else
                    ...overview.pendingTasks.take(5).map(
                          (item) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _PendingTaskTile(
                              item: item,
                              enabled: access.canManageRecovery,
                              onTap: () => context.push('/engage/actions'),
                            ),
                          ),
                        ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Clientes em risco prioritários',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (overview.queue.isEmpty)
                    const EmptyState(
                      title: 'Sem clientes em risco agora',
                      subtitle:
                          'Quando houver risco amarelo/laranja/vermelho eles aparecem aqui.',
                    )
                  else
                    ...overview.queue.take(8).map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _RecoveryQueueTile(item: item),
                          ),
                        ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed:
                        (!access.canManageRecovery || overview.queue.isEmpty)
                            ? null
                            : () => _createRecoveryTask(
                                  context,
                                  ref,
                                  overview,
                                ),
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text('Escolher cliente e criar tarefa'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatMoney(double value) => '${value.toStringAsFixed(0)} MZN';

Future<void> _createRecoveryTask(
  BuildContext context,
  WidgetRef ref,
  EngageOverview overview,
) async {
  final openCustomerIds =
      overview.pendingTasks.map((item) => item.task.customerId).toSet();
  final available = overview.queue
      .where((item) => !openCustomerIds.contains(item.customerId))
      .toList();
  if (available.isEmpty) {
    AppFeedback.showMessage(
      context,
      message: 'Todos os clientes prioritários já têm uma tarefa pendente.',
    );
    return;
  }

  final selected = await showDialog<RecoveryQueueItem>(
    context: context,
    builder: (dialogContext) {
      RecoveryQueueItem? choice;
      return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Escolher cliente'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: available
                  .map(
                    (item) => ListTile(
                      selected: choice == item,
                      leading: Icon(
                        choice == item
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: AppColors.primary,
                      ),
                      title: Text(item.customerName),
                      subtitle: Text(
                        'Risco ${item.riskLevel.toUpperCase()} • Prioridade ${_taskPriorityLabel(item.recommendedPriority)}',
                      ),
                      onTap: () => setDialogState(() => choice = item),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: choice == null
                  ? null
                  : () => Navigator.pop(dialogContext, choice),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
    },
  );
  if (selected == null || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Confirmar nova tarefa'),
      content: Text(
        'Criar uma tarefa de prioridade ${_taskPriorityLabel(selected.recommendedPriority)} para ${selected.customerName}?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Confirmar e criar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final result =
        await ref.read(engageRepositoryProvider).createRecoveryTaskWithResult(
              customerId: selected.customerId,
              priority: selected.recommendedPriority,
              notes: 'Criado a partir da fila prioritária Engage.',
            );
    if (!context.mounted) return;
    if (result.wasAlreadyOpen) {
      AppFeedback.showMessage(
        context,
        message: 'Este cliente já tem uma tarefa pendente.',
      );
    } else {
      AppFeedback.showSuccessToast(
        context,
        message: 'Tarefa de recuperação criada',
        subtitle: selected.customerName,
      );
    }
    await ref.read(engageOverviewProvider.notifier).softRefresh();
  } on RecoveryTaskAlreadyOpenException {
    if (context.mounted) {
      AppFeedback.showMessage(
        context,
        message: 'Este cliente já tem uma tarefa pendente.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppFeedback.showMessage(
        context,
        message: 'Não foi possível criar a tarefa. Tente novamente.',
        isError: true,
      );
    }
  }
}

String _taskPriorityLabel(String priority) => switch (priority) {
      RecoveryTaskPriority.high => 'alta',
      RecoveryTaskPriority.low => 'baixa',
      _ => 'média',
    };

class _PendingTaskTile extends StatelessWidget {
  const _PendingTaskTile({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  final RecoveryTaskQueueItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        onTap: enabled ? onTap : null,
        title: Text(item.customerName),
        subtitle: Text(
          'Prioridade ${_taskPriorityLabel(item.task.priority)} • Pendente',
        ),
        trailing: Icon(
          enabled ? Icons.chevron_right : Icons.lock_outline,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _RecoveryQueueTile extends StatelessWidget {
  const _RecoveryQueueTile({required this.item});

  final RecoveryQueueItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ListTile(
        title: Text(item.customerName),
        subtitle: Text(
          'Risco ${item.riskLevel.toUpperCase()} • ${item.daysSinceVisit} dias • ${_formatMoney(item.totalSpent)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'P${item.priorityScore}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
            ),
            Text(
              '${item.totalPoints} pts',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.text, this.isSuccess = false});

  final String text;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final background = isSuccess
        ? AppColors.secondary.withValues(alpha: 0.15)
        : Colors.orange.withValues(alpha: 0.14);
    final iconColor = isSuccess ? AppColors.secondary : Colors.orange.shade800;

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        leading: Icon(
          icon,
          color: enabled ? AppColors.primary : AppColors.onSurfaceVariant,
        ),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(subtitle),
        ),
        trailing: Icon(
          enabled
              ? Icons.arrow_forward_ios_rounded
              : Icons.lock_outline_rounded,
          size: enabled ? 16 : 20,
          color: enabled ? AppColors.primary : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
