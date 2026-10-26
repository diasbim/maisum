import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/widgets/customer_picker_field.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../domain/engage_labels.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class VisitReportScreen extends ConsumerStatefulWidget {
  const VisitReportScreen({super.key});

  @override
  ConsumerState<VisitReportScreen> createState() => _VisitReportScreenState();
}

class _VisitReportScreenState extends ConsumerState<VisitReportScreen> {
  final _notesController = TextEditingController();
  Customer? _customer;

  /// The open recovery task this visit closes, chosen from the tasks that
  /// belong to [_customer]. Never typed: task ids are UUIDs too.
  RecoveryTaskQueueItem? _linkedTask;
  String _result = VisitResultType.interested;
  bool _completeLinkedTask = false;
  bool _submitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);
    // A failed overview must not block the report: the task picker simply
    // disappears and the visit is still recordable.
    final openTasks =
        ref.watch(engageOverviewProvider).valueOrNull?.pendingTasks ??
            const <RecoveryTaskQueueItem>[];

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: 'Relatório de visita',
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
          if (!access.canManageVisits) {
            return EmptyState(
              title: 'Visitas indisponíveis no seu plano',
              subtitle:
                  'Relatórios de visita são exclusivos do plano Business.',
              actionLabel: 'Ver opções',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageManageVisits,
                  featureName: 'Relatórios de visitas',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const Text(
                'Registar visita',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              CustomerPickerField(
                label: 'Cliente visitado',
                selected: _customer,
                hintText: 'Escolher o cliente visitado',
                onChanged: (customer) => setState(() {
                  _customer = customer;
                  // The previous task belonged to the previous customer.
                  _linkedTask = null;
                  _completeLinkedTask = false;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              ..._taskSection(openTasks),
              DropdownButtonFormField<String>(
                initialValue: _result,
                items: VisitResultType.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(EngageLabels.visitResult(value)),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Como correu a visita?',
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _result = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  hintText: 'Observações da visita',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_linkedTask != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _completeLinkedTask,
                  onChanged: (value) {
                    setState(() => _completeLinkedTask = value ?? false);
                  },
                  title: const Text('Concluir a tarefa ao guardar'),
                  subtitle: Text(
                    'A tarefa de ${_linkedTask!.customerName} passa a concluída.',
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.assignment_turned_in_outlined),
                label: Text(_submitting ? 'A gravar...' : 'Guardar relatório'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The open recovery tasks of the chosen customer, offered as a choice
  /// rather than as an id to transcribe. Shown only once a customer is picked,
  /// and only when that customer actually has open tasks — otherwise the
  /// section is noise.
  List<Widget> _taskSection(List<RecoveryTaskQueueItem> openTasks) {
    final customer = _customer;
    if (customer == null) return const [];

    final tasks = openTasks
        .where((item) => item.task.customerId == customer.id)
        .toList();
    if (tasks.isEmpty) return const [];

    return [
      Text(
        'Tarefa de recuperação (opcional)',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
      ),
      const SizedBox(height: AppSpacing.sm),
      DropdownButtonFormField<String?>(
        initialValue: _linkedTask?.task.id,
        decoration: const InputDecoration(
          labelText: 'Esta visita fecha alguma tarefa?',
        ),
        items: [
          const DropdownMenuItem<String?>(
            child: Text('Nenhuma tarefa'),
          ),
          ...tasks.map(
            (item) => DropdownMenuItem<String?>(
              value: item.task.id,
              // Priority plus the day it was opened: a customer can have more
              // than one task, and the priority alone would not tell them apart.
              child: Text(
                'Prioridade ${EngageLabels.taskPriority(item.task.priority)} '
                '• ${PtDateFormat.dayMonthTime(item.task.createdAt)}',
              ),
            ),
          ),
        ],
        onChanged: (value) => setState(() {
          _linkedTask = value == null
              ? null
              : tasks.firstWhere((item) => item.task.id == value);
          if (_linkedTask == null) _completeLinkedTask = false;
        }),
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final customerId = _customer?.id ?? '';
    final taskId = _linkedTask?.task.id ?? '';

    if (customerId.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Escolha o cliente visitado.',
        isError: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final saveResult =
          await ref.read(engageRepositoryProvider).submitVisitReportWithResult(
                customerId: customerId,
                result: _result,
                visitedAt: DateTime.now(),
                taskId: taskId.isEmpty ? null : taskId,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              );

      if (_completeLinkedTask && taskId.isNotEmpty) {
        try {
          final completed = await ref
              .read(engageRepositoryProvider)
              .completeRecoveryTask(taskId);
          if (completed == null) {
            throw StateError('A tarefa vinculada não foi encontrada.');
          }
        } catch (_) {
          if (!mounted) return;
          AppFeedback.showRetryableError(
            context,
            message: saveResult.isQueued
                ? 'Relatório guardado para sincronizar, mas a tarefa não foi concluída.'
                : 'Relatório guardado, mas a tarefa não foi concluída.',
            onRetry: () => _completeLinkedTaskAfterSave(taskId),
          );
          return;
        }
      }

      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: saveResult.isQueued
            ? 'Relatório guardado para sincronizar'
            : 'Relatório guardado',
        // Never the raw VisitResultType: that would read "Needs Promotion".
        subtitle:
            '${_customer?.name ?? 'Cliente'} • ${EngageLabels.visitResult(_result)}',
      );
      _notesController.clear();
      setState(() {
        _linkedTask = null;
        _completeLinkedTask = false;
      });
      // A completed task must leave the pending queue the picker reads from.
      unawaited(ref.read(engageOverviewProvider.notifier).softRefresh());
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showRetryableError(
        context,
        message:
            'Não foi possível guardar o relatório. Os dados continuam preenchidos.',
        onRetry: _submit,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _completeLinkedTaskAfterSave(String taskId) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final completed =
          await ref.read(engageRepositoryProvider).completeRecoveryTask(taskId);
      if (completed == null) {
        throw StateError('A tarefa vinculada não foi encontrada.');
      }
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: 'Tarefa vinculada concluída',
      );
      _notesController.clear();
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showRetryableError(
        context,
        message:
            'Não foi possível concluir a tarefa vinculada. Tente novamente.',
        onRetry: () => _completeLinkedTaskAfterSave(taskId),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
