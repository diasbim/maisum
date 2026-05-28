import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/pin_verification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/pin_verification_feedback.dart';
import '../../../core/widgets/pin_pad.dart';
import 'auth_controller.dart';
import 'post_auth_navigation.dart';

const _tag = 'PinEntry';

class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen>
    with SingleTickerProviderStateMixin, PinVerificationShakeMixin {
  String _input = '';
  bool _isError = false;
  bool _isLoading = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    initPinShakeAnimation();
    _loadAttempts();
  }

  @override
  void dispose() {
    disposePinShakeAnimation();
    super.dispose();
  }

  Future<void> _loadAttempts() async {
    final n = await PinVerificationService.loadPersistedAttempts(
      ref.read(secureStorageServiceProvider),
    );
    if (mounted) setState(() => _attempts = n);
  }

  void _handleDigit(String d) {
    if (_isLoading || _isError || _input.length >= AppConstants.pinLength) {
      return;
    }
    setState(() => _input += d);
    if (_input.length == AppConstants.pinLength) _verify();
  }

  void _handleDelete() {
    if (_isLoading) return;
    setState(() {
      _isError = false;
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
      }
    });
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    final storage = ref.read(secureStorageServiceProvider);
    final result = await PinVerificationService.verifyPersistedPin(
      storage: storage,
      input: _input,
    );

    if (result.isSuccess) {
      Log.i(_tag, 'PIN verified successfully');
      ref.read(appLockedProvider.notifier).state = false;
      if (!mounted) return;
      final route = await resolvePostAuthRoute(ref);
      if (mounted) context.go(route);
      return;
    }

    if (result.status == PinVerificationStatus.unavailable) {
      setState(() => _isLoading = false);
      return;
    }

    Log.w(
      _tag,
      'Wrong PIN — attempt ${result.attempts}/${AppConstants.maxPinAttempts}',
    );

    if (result.isBlocked) {
      Log.w(_tag, 'Max attempts reached — logging out');
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) {
        AppFeedback.showMessage(
          context,
          message: AppStrings.pinBlocked,
          isError: true,
        );
        context.go('/login');
      }
      return;
    }

    setState(() {
      _isError = true;
      _isLoading = false;
      _attempts = result.attempts;
    });
    triggerPinShake();
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _isError = false;
        _input = '';
      });
    }
  }

  Future<void> _forgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repor acesso'),
        content: const Text(
            'Isto irá apagar o PIN e terminar a sessão. Terá de fazer login novamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancelar),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Repor'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    Log.i(_tag, 'User chose to reset PIN — logging out');
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 60),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: AppTheme.shadowMd,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          AppStrings.pinEntryTitle,
                          style: theme.textTheme.headlineLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.pinEntrySubtitle,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 52),
                        PinVerificationFeedback(
                          shakeAnimation: pinShakeAnimation,
                          inputLength: _input.length,
                          attempts: _attempts,
                          isError: _isError,
                          isLoading: _isLoading,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        children: [
                          PinPad(
                            onDigit: _handleDigit,
                            onDelete: _handleDelete,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _isLoading ? null : _forgotPin,
                            child: Text(
                              AppStrings.pinForgot,
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
