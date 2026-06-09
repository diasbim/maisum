import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class VisitReportScreen extends ConsumerStatefulWidget {
  const VisitReportScreen({super.key});

  @override
  ConsumerState<VisitReportScreen> createState() => _VisitReportScreenState();
}

class _VisitReportScreenState extends ConsumerState<VisitReportScreen> {
  final _customerIdController = TextEditingController();
  final _taskIdController = TextEditingController();
  final _notesController = TextEditingController();
  String _result = VisitResultType.interested;
  bool _completeLinkedTask = false;
  bool _submitting = false;

  @override
  void dispose() {
    _customerIdController.dispose();
    _taskIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Relatório de Visita'),
        backgroundColor: AppColors.offWhite,
        elevation: 0,
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
            return const EmptyState(
              title: 'Visitas indisponíveis no seu plano',
              subtitle:
                  'Relatórios de visita são exclusivos do plano Business.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const Text(
                'Registrar visita',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _customerIdController,
                decoration: const InputDecoration(
                  labelText: 'Customer ID',
                  hintText: 'ID do cliente visitado',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _taskIdController,
                decoration: const InputDecoration(
                  labelText: 'Task ID (opcional)',
                  hintText: 'Tarefa vinculada à visita',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _result,
                items: VisitResultType.values
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                decoration: const InputDecoration(labelText: 'Resultado'),
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _completeLinkedTask,
                onChanged: (value) {
                  setState(() => _completeLinkedTask = value ?? false);
                },
                title: const Text('Concluir tarefa vinculada automaticamente'),
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
                label: Text(_submitting ? 'A gravar...' : 'Salvar relatório'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    final customerId = _customerIdController.text.trim();
    final taskId = _taskIdController.text.trim();

    if (customerId.isEmpty) {
      AppFeedback.showMessage(context, message: 'Informe o customer ID.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(engageRepositoryProvider)
          .submitVisitReport(
            customerId: customerId,
            result: _result,
            visitedAt: DateTime.now(),
            taskId: taskId.isEmpty ? null : taskId,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (_completeLinkedTask && taskId.isNotEmpty) {
        await ref.read(engageRepositoryProvider).completeRecoveryTask(taskId);
      }

      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: 'Relatório salvo',
        subtitle: _result,
      );
      _notesController.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
