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

class RecoveryActionsScreen extends ConsumerStatefulWidget {
  const RecoveryActionsScreen({super.key});

  @override
  ConsumerState<RecoveryActionsScreen> createState() =>
      _RecoveryActionsScreenState();
}

class _RecoveryActionsScreenState extends ConsumerState<RecoveryActionsScreen> {
  final _notesController = TextEditingController();
  RecoveryTaskQueueItem? _selected;
  String _actionType = RecoveryActionType.whatsapp;
  bool _submitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: 'Fila de recuperação',
        fallbackLocation: '/engage',
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => const EmptyState(
          title: 'Não foi possível validar acesso',
          subtitle: 'Tente novamente em alguns segundos.',
        ),
        data: (access) {
          if (!access.canManageRecovery) {
            return EmptyState(
              title: 'Ações indisponíveis no seu plano',
              subtitle:
                  'A criação de ações de recuperação é exclusiva do plano Business.',
              actionLabel: 'Ver opções',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageManageRecovery,
                  featureName: 'Ações de recuperação',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }
          return _buildQueue(ref.watch(engageOverviewProvider));
        },
      ),
    );
  }

  Widget _buildQueue(AsyncValue<EngageOverview> overviewAsync) {
    return overviewAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
      error: (_, __) => EmptyState(
        title: 'Não foi possível carregar a fila',
        subtitle: 'Os dados locais continuam seguros. Tente novamente.',
        actionLabel: 'Tentar de novo',
        onAction: () => ref.read(engageOverviewProvider.notifier).refresh(),
      ),
      data: (overview) {
        final tasks = overview.pendingTasks;
        if (tasks.isEmpty) {
          return EmptyState(
            title: 'Nenhuma tarefa pendente',
            subtitle:
                'Crie uma tarefa no painel Engage ao escolher um cliente em risco.',
            actionLabel: 'Voltar ao painel',
            onAction: () => context.go('/engage'),
          );
        }

        final selected = _selected == null
            ? null
            : tasks
                .where((item) => item.task.id == _selected!.task.id)
                .firstOrNull;
        return RefreshIndicator(
          color: AppColors.secondary,
          onRefresh: () => ref.read(engageOverviewProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text(
                'Tarefas pendentes (${tasks.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text('Selecione um cliente para registar uma ação.'),
              const SizedBox(height: AppSpacing.lg),
              ...tasks.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TaskTile(
                    item: item,
                    selected: selected?.task.id == item.task.id,
                    onTap: () {
                      setState(() {
                        _selected = item;
                        _notesController.clear();
                      });
                    },
                  ),
                ),
              ),
              if (selected != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _ActionPanel(
                  item: selected,
                  actionType: _actionType,
                  notesController: _notesController,
                  submitting: _submitting,
                  onActionTypeChanged: (value) =>
                      setState(() => _actionType = value),
                  onLogAction: _logAction,
                  onComplete: _confirmCompletion,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _logAction() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _submitting = true);
    try {
      final result =
          await ref.read(engageRepositoryProvider).logRecoveryActionWithResult(
        customerId: selected.task.customerId,
        actionType: _actionType,
        taskId: selected.task.id,
        payload: {
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
        },
      );
      if (!mounted) return;
      _notesController.clear();
      AppFeedback.showSuccessToast(
        context,
        message: result.isQueued
            ? 'Ação guardada para sincronizar'
            : 'Ação registada',
        subtitle: selected.customerName,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showRetryableError(
        context,
        message:
            'Não foi possível registar a ação. Os dados continuam preenchidos.',
        onRetry: _logAction,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmCompletion() async {
    final selected = _selected;
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Concluir tarefa?'),
        content: Text(
          'Confirma que a recuperação de ${selected.customerName} foi tratada?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final completed = await ref
          .read(engageRepositoryProvider)
          .completeRecoveryTask(selected.task.id);
      if (!mounted) return;
      if (completed == null) {
        throw StateError('Recovery task no longer exists');
      }
      setState(() => _selected = null);
      AppFeedback.showSuccessToast(
        context,
        message: 'Tarefa concluída',
        subtitle: selected.customerName,
      );
      await ref.read(engageOverviewProvider.notifier).softRefresh();
    } catch (_) {
      if (mounted) {
        AppFeedback.showMessage(
          context,
          message: 'Não foi possível concluir a tarefa. Tente novamente.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final RecoveryTaskQueueItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: selected ? AppColors.secondary.withValues(alpha: 0.12) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: selected
            ? const BorderSide(color: AppColors.secondary)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          item.customerName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (item.customerPhone.isNotEmpty) item.customerPhone,
            'Prioridade ${_priorityLabel(item.task.priority)}',
            'Pendente',
          ].join(' • '),
        ),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.chevron_right,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.item,
    required this.actionType,
    required this.notesController,
    required this.submitting,
    required this.onActionTypeChanged,
    required this.onLogAction,
    required this.onComplete,
  });

  final RecoveryTaskQueueItem item;
  final String actionType;
  final TextEditingController notesController;
  final bool submitting;
  final ValueChanged<String> onActionTypeChanged;
  final VoidCallback onLogAction;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ação para ${item.customerName}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (item.task.notes?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(item.task.notes!),
            ],
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: actionType,
              items: RecoveryActionType.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_actionLabel(value)),
                    ),
                  )
                  .toList(),
              decoration: const InputDecoration(labelText: 'Tipo de ação'),
              onChanged: submitting
                  ? null
                  : (value) {
                      if (value != null) onActionTypeChanged(value);
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: notesController,
              enabled: !submitting,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas',
                hintText: 'Detalhes do contacto, oferta ou visita',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: submitting ? null : onLogAction,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar ação'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: submitting ? null : onComplete,
              icon: const Icon(Icons.task_alt),
              label: const Text('Concluir tarefa'),
            ),
          ],
        ),
      ),
    );
  }
}

String _priorityLabel(String priority) => switch (priority) {
      RecoveryTaskPriority.high => 'alta',
      RecoveryTaskPriority.low => 'baixa',
      _ => 'média',
    };

String _actionLabel(String action) => switch (action) {
      RecoveryActionType.whatsapp => 'WhatsApp',
      RecoveryActionType.call => 'Ligação',
      RecoveryActionType.offer => 'Oferta',
      RecoveryActionType.visit => 'Visita',
      _ => action,
    };
