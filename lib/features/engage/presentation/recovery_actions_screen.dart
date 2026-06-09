import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class RecoveryActionsScreen extends ConsumerStatefulWidget {
  const RecoveryActionsScreen({super.key});

  @override
  ConsumerState<RecoveryActionsScreen> createState() =>
      _RecoveryActionsScreenState();
}

class _RecoveryActionsScreenState extends ConsumerState<RecoveryActionsScreen> {
  final _customerIdController = TextEditingController();
  final _taskIdController = TextEditingController();
  final _notesController = TextEditingController();
  String _actionType = RecoveryActionType.whatsapp;
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
        title: const Text('Ações de Recuperação'),
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
          if (!access.canManageRecovery) {
            return const EmptyState(
              title: 'Ações indisponíveis no seu plano',
              subtitle:
                  'A criação de ações de recuperação é exclusiva do plano Business.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const Text(
                'Registrar ação',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _customerIdController,
                decoration: const InputDecoration(
                  labelText: 'Customer ID',
                  hintText: 'ID do cliente',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _taskIdController,
                decoration: const InputDecoration(
                  labelText: 'Task ID (opcional)',
                  hintText: 'Vincular à tarefa de recuperação',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _actionType,
                items: RecoveryActionType.values
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                decoration: const InputDecoration(labelText: 'Tipo de ação'),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _actionType = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  hintText: 'Detalhes da ligação, WhatsApp, oferta ou visita',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_submitting ? 'A gravar...' : 'Salvar ação'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    final customerId = _customerIdController.text.trim();
    if (customerId.isEmpty) {
      AppFeedback.showMessage(context, message: 'Informe o customer ID.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(engageRepositoryProvider)
          .logRecoveryAction(
            customerId: customerId,
            actionType: _actionType,
            taskId: _taskIdController.text.trim().isEmpty
                ? null
                : _taskIdController.text.trim(),
            payload: {
              if (_notesController.text.trim().isNotEmpty)
                'notes': _notesController.text.trim(),
            },
          );
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: 'Ação registrada',
        subtitle: _actionType,
      );
      _notesController.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
