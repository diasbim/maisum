import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/pin_pad.dart';
import 'auth_controller.dart';

const _tag = 'PinEntry';

class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen>
    with SingleTickerProviderStateMixin {
  String _input = '';
  bool _isError = false;
  bool _isLoading = false;
  int _attempts = 0;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
    _loadAttempts();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAttempts() async {
    final n = await ref.read(secureStorageServiceProvider).getPinAttempts();
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
    final storedPin = await storage.getPin();

    if (storedPin == _input) {
      Log.i(_tag, 'PIN verified successfully');
      await storage.clearPinAttempts();
      if (mounted) context.go('/dashboard');
      return;
    }

    final attempts = await storage.getPinAttempts() + 1;
    await storage.savePinAttempts(attempts);
    Log.w(_tag, 'Wrong PIN — attempt $attempts/${AppConstants.maxPinAttempts}');

    if (attempts >= AppConstants.maxPinAttempts) {
      Log.w(_tag, 'Max attempts reached — logging out');
      await storage.clearPin();
      await storage.clearPinAttempts();
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.pinBlocked)),
        );
        context.go('/login');
      }
      return;
    }

    setState(() {
      _isError = true;
      _isLoading = false;
      _attempts = attempts;
    });
    _shakeCtrl.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() { _isError = false; _input = ''; });
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
    final storage = ref.read(secureStorageServiceProvider);
    await storage.clearPin();
    await storage.clearPinAttempts();
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = AppConstants.maxPinAttempts - _attempts;
    final showAttemptsWarning = _attempts > 0;

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
                          child: const Icon(
                            Icons.loyalty_rounded,
                            color: AppColors.secondary,
                            size: 40,
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

                        // Dots with shake
                        AnimatedBuilder(
                          animation: _shakeAnim,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(_shakeAnim.value, 0),
                            child: child,
                          ),
                          child: PinDots(
                            length: AppConstants.pinLength,
                            filled: _input.length,
                            isError: _isError,
                          ),
                        ),

                        const SizedBox(height: 16),
                        AnimatedOpacity(
                          opacity: (_isError || showAttemptsWarning) ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _isError
                                ? AppStrings.pinIncorrect
                                : '$remaining tentativa${remaining == 1 ? "" : "s"} restante${remaining == 1 ? "" : "s"}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: remaining <= 1
                                  ? AppColors.error
                                  : AppColors.amber,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        if (_isLoading) ...[
                          const SizedBox(height: 12),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
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
