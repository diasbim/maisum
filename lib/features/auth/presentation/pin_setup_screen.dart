import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pin_pad.dart';
import 'phone_auth_screen.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _isError = false;
  bool _isSuccess = false;

  void _handleDigit(String d) {
    if (_isSuccess) return;
    setState(() => _isError = false);
    if (_isConfirming) {
      if (_confirmPin.length < 4) {
        setState(() => _confirmPin += d);
        if (_confirmPin.length == 4) _checkMatch();
      }
    } else {
      if (_pin.length < 4) {
        setState(() => _pin += d);
        if (_pin.length == 4) _advanceToConfirm();
      }
    }
  }

  void _handleDelete() {
    if (_isSuccess) return;
    setState(() => _isError = false);
    if (_isConfirming) {
      if (_confirmPin.isNotEmpty) {
        setState(() => _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1));
      } else {
        setState(() { _isConfirming = false; _pin = ''; });
      }
    } else {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    }
  }

  Future<void> _advanceToConfirm() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _isConfirming = true);
  }

  Future<void> _checkMatch() async {
    if (_pin == _confirmPin) {
      await ref.read(secureStorageServiceProvider).savePin(_pin);
      await ref.read(secureStorageServiceProvider).clearPinAttempts();
      setState(() => _isSuccess = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) context.go('/dashboard');
    } else {
      setState(() => _isError = true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() { _isError = false; _confirmPin = ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentLen = _isConfirming ? _confirmPin.length : _pin.length;
    final title = _isSuccess
        ? AppStrings.pinCreatedSuccess
        : _isConfirming ? AppStrings.pinConfirmTitle : AppStrings.pinSetupTitle;
    final subtitle = _isConfirming ? AppStrings.pinConfirmSubtitle : AppStrings.pinSetupSubtitle;

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
                        const SizedBox(height: 48),
                        AuthStepProgress(currentStep: _isSuccess ? 3 : 2),
                        const SizedBox(height: 40),
                        // Icon
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: _isSuccess ? AppTheme.goldGradient : AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppTheme.shadowMd,
                          ),
                          child: Icon(
                            _isSuccess ? Icons.check_rounded : Icons.lock_outline_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(title, style: theme.textTheme.headlineLarge, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        PinDots(
                          length: 4,
                          filled: currentLen,
                          isError: _isError,
                          isSuccess: _isSuccess,
                        ),
                        if (_isError) ...[
                          const SizedBox(height: 16),
                          Text(
                            AppStrings.pinMismatch,
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: PinPad(onDigit: _handleDigit, onDelete: _handleDelete),
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
