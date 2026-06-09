import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/widgets/app_feedback.dart';
import 'auth_controller.dart';
import 'post_auth_navigation.dart';

class DeviceLinkScreen extends ConsumerStatefulWidget {
  const DeviceLinkScreen({super.key});

  @override
  ConsumerState<DeviceLinkScreen> createState() => _DeviceLinkScreenState();
}

class _DeviceLinkScreenState extends ConsumerState<DeviceLinkScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Vincular dispositivo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text(
            'Entrar em uma barbearia existente',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Insira o codigo da barbearia para conectar este dispositivo a conta existente. Este fluxo tambem funciona para contas staff.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            enabled: !_isSubmitting,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Codigo da barbearia',
              hintText: 'ABCD-1234',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                  _isSubmitting ? 'A vincular...' : 'Vincular dispositivo'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                _isSubmitting ? null : () => context.go('/merchant-config'),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Criar nova barbearia'),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              'Dica: o owner encontra este codigo em Definicoes > Codigo da barbearia.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final rawCode = _codeController.text.trim();
    if (rawCode.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Insira o codigo da barbearia.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).linkDeviceByCode(rawCode);
      if (!mounted) return;

      AppFeedback.showMessage(
        context,
        message: 'Dispositivo vinculado com sucesso.',
      );

      final route = await resolvePostAuthRoute(ref.read);
      if (!mounted) return;
      context.go(route);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().trim();
      final message = raw.startsWith('Exception: ')
          ? raw.substring('Exception: '.length)
          : raw;
      AppFeedback.showMessage(
        context,
        message: message.isEmpty
            ? 'Nao foi possivel vincular o dispositivo.'
            : message,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
