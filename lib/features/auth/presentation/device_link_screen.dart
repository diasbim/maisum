import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../design_system/design_system.dart';
import '../../merchant_onboarding/presentation/controllers/merchant_onboarding_controller.dart';
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            'Entrar em uma barbearia existente',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Insira o codigo da barbearia para conectar este dispositivo a conta existente. Este fluxo tambem funciona para contas staff.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          MaisUmTextField(
            controller: _codeController,
            enabled: !_isSubmitting,
            label: 'Codigo da barbearia',
            hintText: 'ABCD-1234',
            prefixIcon: const Icon(Icons.link_rounded),
            textCapitalization: TextCapitalization.characters,
            useFloatingLabel: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          MaisUmButton(
            onPressed: _isSubmitting ? null : _submit,
            isLoading: _isSubmitting,
            label: 'Vincular dispositivo',
            loadingLabel: 'A vincular...',
            leadingIcon: Icons.sync_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          MaisUmButton(
            onPressed: _isSubmitting
                ? null
                : () => context.go(merchantOnboardingStartRoute),
            label: 'Criar nova barbearia',
            variant: MaisUmButtonVariant.outlined,
            leadingIcon: Icons.storefront_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          MaisUmSurface(
            variant: MaisUmSurfaceVariant.muted,
            radius: AppRadius.md,
            padding: const EdgeInsets.all(AppSpacing.md),
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
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'device_link_submit');
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
