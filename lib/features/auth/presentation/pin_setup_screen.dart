import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/pin_verification_feedback.dart';
import 'phone_auth_screen.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen>
    with SingleTickerProviderStateMixin, PinVerificationShakeMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _isError = false;
  bool _isLoading = false;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    initPinShakeAnimation();
  }

  @override
  void dispose() {
    disposePinShakeAnimation();
    super.dispose();
  }

  void _handleDigit(String d) {
    if (_isSuccess || _isLoading) return;
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
    if (_isSuccess || _isLoading) return;
    setState(() => _isError = false);
    if (_isConfirming) {
      if (_confirmPin.isNotEmpty) {
        setState(() =>
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1));
      } else {
        setState(() {
          _isConfirming = false;
          _pin = '';
        });
      }
    } else {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    }
  }

  Future<void> _advanceToConfirm() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _isConfirming = true;
        _confirmPin = '';
      });
    }
  }

  Future<void> _checkMatch() async {
    setState(() => _isLoading = true);
    if (_pin == _confirmPin) {
      await ref.read(secureStorageServiceProvider).savePin(_pin);
      await ref.read(secureStorageServiceProvider).clearPinAttempts();
      ref.read(appLockedProvider.notifier).state = false;
      setState(() {
        _isSuccess = true;
        _isLoading = false;
      });
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) context.go('/dashboard');
    } else {
      setState(() {
        _isError = true;
        _isLoading = false;
      });
      triggerPinShake();
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          _isError = false;
          _confirmPin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentLen = _isConfirming ? _confirmPin.length : _pin.length;
    final title = _isSuccess
        ? AppStrings.pinCreatedSuccess
        : _isConfirming
            ? AppStrings.pinConfirmTitle
            : AppStrings.pinSetupTitle;
    final subtitle = _isConfirming
        ? AppStrings.pinConfirmSubtitle
        : AppStrings.pinSetupSubtitle;

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
                            gradient: _isSuccess
                                ? AppTheme.goldGradient
                                : AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppTheme.shadowMd,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(title,
                            style: theme.textTheme.headlineLarge,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        PinVerificationFeedback(
                          shakeAnimation: pinShakeAnimation,
                          inputLength: currentLen,
                          attempts: 0,
                          isError: _isError,
                          isLoading: _isLoading,
                          isSuccess: _isSuccess,
                          showAttemptStatus: false,
                          helperText: _isError ? AppStrings.pinMismatch : null,
                          helperColor: AppColors.error,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: PinPad(
                          onDigit: _handleDigit, onDelete: _handleDelete),
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
