import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
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
  static const int _minNormalizedCodeLength = 8;

  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _isSubmitting = false;

  String get _normalizedCode => _normalizeLinkCode(_codeController.text);
  bool get _hasCodeInput => _codeController.text.trim().isNotEmpty;
  bool get _isCodeValid =>
      _hasCodeInput && _normalizedCode.length >= _minNormalizedCodeLength;
  bool get _canSubmit => !_isSubmitting && _isCodeValid;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_handleCodeChanged);
  }

  @override
  void dispose() {
    _codeController.removeListener(_handleCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _handleCodeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeValidationState = !_hasCodeInput
        ? ValidationState.neutral
        : _isCodeValid
            ? ValidationState.valid
            : ValidationState.invalid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular dispositivo'),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: FocusTraversalGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xxxl,
            ),
            children: [
              Text(
                'Entrar em um negocio existente',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Insira o codigo do negocio para conectar este dispositivo a conta existente. Este fluxo tambem funciona para contas staff.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              MaisUmTextField(
                controller: _codeController,
                focusNode: _codeFocusNode,
                enabled: !_isSubmitting,
                autofocus: true,
                label: 'Codigo do negocio',
                hintText: 'ABCD-1234',
                prefixIcon: const Icon(Icons.link_rounded),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-\s]')),
                ],
                validationState: codeValidationState,
                showValidIcon: true,
                onFieldSubmitted: (_) {
                  if (_canSubmit) {
                    _submit();
                  }
                },
                useFloatingLabel: true,
              ),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                liveRegion: _isSubmitting,
                label: _isSubmitting
                    ? 'Vinculando dispositivo'
                    : 'Vincular dispositivo',
                button: true,
                enabled: _canSubmit,
                child: MaisUmButton(
                  onPressed: _canSubmit ? _submit : null,
                  isLoading: _isSubmitting,
                  label: 'Vincular dispositivo',
                  loadingLabel: 'Vinculando...',
                  leadingIcon: Icons.sync_rounded,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              MaisUmButton(
                onPressed: _isSubmitting
                    ? null
                    : () => context.go(merchantOnboardingStartRoute),
                label: 'Criar novo negocio',
                variant: MaisUmButtonVariant.outlined,
                leadingIcon: Icons.storefront_rounded,
              ),
              const SizedBox(height: AppSpacing.lg),
              MaisUmSurface(
                variant: MaisUmSurfaceVariant.muted,
                radius: AppRadius.md,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Dica: o owner encontra este codigo em Definicoes > Codigo do negocio.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final rawCode = _codeController.text.trim();
    if (!_isCodeValid) {
      AppFeedback.showMessage(
        context,
        message: rawCode.isEmpty
            ? 'Insira o codigo do negocio.'
            : 'Codigo do negocio invalido.',
        isError: true,
      );
      return;
    }

    final firebaseUser = ref.read(firebaseAuthInstanceProvider).currentUser;
    if (firebaseUser == null) {
      AppFeedback.showMessage(
        context,
        message: 'É necessário iniciar sessão.',
        isError: true,
      );
      context.go('/login');
      return;
    }

    _codeFocusNode.unfocus();
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).linkDeviceByCode(rawCode);
      if (!mounted) return;

      AppFeedback.showSuccessToast(
        context,
        message: 'Dispositivo vinculado com sucesso',
      );

      final route = await resolvePostAuthRoute(ref.read);
      if (!mounted) return;
      context.go(route);
    } on FirebaseException catch (e, st) {
      _debugLogDeviceLinkError(e, st);
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: _mapFirebaseLinkError(e),
        isError: true,
      );
    } on ArgumentError catch (e, st) {
      _debugLogDeviceLinkError(e, st);
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: 'Codigo do negocio invalido.',
        isError: true,
      );
    } on StateError catch (e, st) {
      _debugLogDeviceLinkError(e, st);
      if (!mounted) return;
      final message = _mapStateLinkError(e);
      AppFeedback.showMessage(
        context,
        message: message,
        isError: true,
      );
      if (message == 'É necessário iniciar sessão.') {
        context.go('/login');
      }
    } catch (e, st) {
      _debugLogDeviceLinkError(e, st);
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: 'Ocorreu um erro inesperado.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _normalizeLinkCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _mapFirebaseLinkError(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' =>
        'Não tem autorização para vincular este dispositivo.',
      'not-found' => 'Código do negócio inválido.',
      'unavailable' => 'Sem ligação à internet.',
      'deadline-exceeded' => 'A operação demorou demasiado tempo.',
      'unknown' => 'Ocorreu um erro inesperado.',
      _ => 'Ocorreu um erro inesperado.',
    };
  }

  String _mapStateLinkError(StateError error) {
    final message = error.message.toLowerCase();
    if (message.contains('sess') || message.contains('iniciar')) {
      return 'É necessário iniciar sessão.';
    }
    if (message.contains('codigo') || message.contains('código')) {
      return 'Código do negócio inválido.';
    }
    return 'Ocorreu um erro inesperado.';
  }

  void _debugLogDeviceLinkError(Object error, StackTrace stackTrace) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('Device link failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
