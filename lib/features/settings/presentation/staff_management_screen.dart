import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../../../core/widgets/app_feedback.dart';
import '../domain/staff_member.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  bool _actionInProgress = false;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(staffMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestao de Staff'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: membersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Nao foi possivel carregar a equipa.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(error.toString()),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _refresh,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
          data: (members) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'Adiciona e controla os membros da tua barbearia.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _actionInProgress ? null : _inviteStaff,
                    icon: const Icon(Icons.mark_email_unread_rounded),
                    label: const Text('Convidar por telefone'),
                  ),
                  FilledButton.icon(
                    onPressed: _actionInProgress ? null : _createStaff,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Criar manualmente'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...members.map(_buildMemberCard),
              if (members.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Text(
                    'Ainda sem staff registado.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(StaffMember member) {
    final theme = Theme.of(context);
    final statusColor = switch (member.status) {
      AppConstants.appUserStatusActive => AppColors.green,
      AppConstants.appUserStatusInvited => AppColors.secondary,
      _ => AppColors.error,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.15),
              child: Icon(
                member.isOwner
                    ? Icons.workspace_premium_rounded
                    : Icons.person_outline_rounded,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.phone,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _InfoChip(label: member.role, color: AppColors.primary),
                      _InfoChip(label: member.status, color: statusColor),
                    ],
                  ),
                ],
              ),
            ),
            if (!member.isOwner)
              Switch(
                value: member.isActive,
                onChanged: _actionInProgress
                    ? null
                    : (isActive) => _toggleStaff(member, isActive),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteStaff() async {
    final phone = await _askPhone(
      title: 'Convidar staff',
      confirmLabel: 'Convidar',
    );
    if (phone == null || !mounted) return;

    setState(() => _actionInProgress = true);
    try {
      await ref
          .read(staffManagementRepositoryProvider)
          .inviteStaff(phone: phone);
      ref.invalidate(staffMembersProvider);
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: 'Convite enviado para $phone.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _createStaff() async {
    final phone = await _askPhone(
      title: 'Criar staff manualmente',
      confirmLabel: 'Criar',
    );
    if (phone == null || !mounted) return;

    setState(() => _actionInProgress = true);
    try {
      await ref
          .read(staffManagementRepositoryProvider)
          .createManualStaff(phone: phone);
      ref.invalidate(staffMembersProvider);
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: 'Staff criado com sucesso.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _toggleStaff(StaffMember member, bool isActive) async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(staffManagementRepositoryProvider).setStaffActive(
            staffId: member.id,
            isActive: isActive,
          );
      ref.invalidate(staffMembersProvider);
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: isActive ? 'Staff ativado.' : 'Staff desativado.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(staffMembersProvider);
    await ref.read(staffMembersProvider.future);
  }

  Future<String?> _askPhone({
    required String title,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefone',
              hintText: '+258 84 000 0000',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  Navigator.of(ctx).pop('');
                  return;
                }
                try {
                  final normalized = MozPhoneUtils.normalizeToE164(raw);
                  Navigator.of(ctx).pop(normalized);
                } catch (_) {
                  Navigator.of(ctx).pop(raw);
                }
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
      if (result == null) {
        return null;
      }
      final normalized = result.trim();
      if (normalized.isEmpty) {
        if (mounted) {
          AppFeedback.showMessage(
            context,
            message: 'Telefone invalido.',
            isError: true,
          );
        }
        return null;
      }
      return normalized;
    } finally {
      controller.dispose();
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
