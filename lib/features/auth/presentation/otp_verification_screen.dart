import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'auth_controller.dart';
import 'phone_auth_screen.dart';

class OtpScreenArgs {
  const OtpScreenArgs({
    required this.phone,
    required this.verificationId,
  });

  final String phone;
  final String verificationId;
}

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  ConsumerState<OTPVerificationScreen> createState() =>
      _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  String _verificationId = '';

  int _resendTimer = 60;
  Timer? _timer;
  bool _isVerifying = false;
  bool _submitInFlight = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _startResendTimer();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() => _resendTimer--);
      } else {
        timer.cancel();
      }
    });
  }

  void _resendCode() {
    if (_resendTimer > 0) return;
    _pinController.clear();
    setState(() => _resendTimer = 60);
    _startResendTimer();

    final messenger = ScaffoldMessenger.of(context);
    ref.read(authControllerProvider.notifier).requestOtp(
      phone: widget.phoneNumber,
      onCodeSent: (newVerificationId) {
        _verificationId = newVerificationId;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Código de verificação reenviado!'),
            backgroundColor: AppColors.secondary,
          ),
        );
      },
      onError: (error) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      },
    );
  }

  void _verifyOTP([String? pin]) async {
    final otp = pin ?? _pinController.text;
    if (otp.length != 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, insira o código completo')),
      );
      return;
    }

    if (_submitInFlight) return;
    _submitInFlight = true;
    setState(() => _isVerifying = true);

    try {
      await ref.read(authControllerProvider.notifier).verifyOtp(
            phone: widget.phoneNumber,
            verificationId: _verificationId,
            code: otp,
          );
      if (!mounted) return;
      final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
      if (mounted) context.go(hasPin ? '/dashboard' : '/pin-setup');
    } catch (e) {
      _submitInFlight = false;
      setState(() => _isVerifying = false);
      _pinController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final defaultTheme = PinTheme(
      width: 52,
      height: 60,
      textStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
    );

    final focusedTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    final submittedTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.secondary.withValues(alpha: 0.5)),
      ),
    );

    final errorTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error, width: 2),
      ),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.primary,
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AuthStepProgress(currentStep: 1),
                    const SizedBox(height: 36),

                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mark_email_read_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Introduza o código\nde verificação',
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: 12),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                height: 1.5,
                              ),
                              children: [
                                const TextSpan(
                                    text: 'Enviámos um código para '),
                                TextSpan(
                                  text: widget.phoneNumber,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (Navigator.of(context).canPop())
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.secondary,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Editar',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 36),

                    Center(
                      child: Pinput(
                        key: const Key('otp_input'),
                        length: 6,
                        controller: _pinController,
                        focusNode: _pinFocusNode,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        hapticFeedbackType: HapticFeedbackType.lightImpact,
                        closeKeyboardWhenCompleted: false,
                        defaultPinTheme: defaultTheme,
                        focusedPinTheme: focusedTheme,
                        submittedPinTheme: submittedTheme,
                        errorPinTheme: errorTheme,
                        onCompleted: _verifyOTP,
                        enabled: !_isVerifying,
                      ),
                    ),
                    const SizedBox(height: 32),

                    Center(child: _buildResendRow(theme)),

                    const Spacer(),
                    const SizedBox(height: 16),

                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded,
                              size: 13, color: AppColors.secondary),
                          const SizedBox(width: 6),
                          Text(
                            'Código válido por 10 minutos',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    AuthGradientButton(
                      key: const Key('verify_button'),
                      onPressed: _isVerifying ? null : _verifyOTP,
                      isLoading: _isVerifying,
                      label: 'Verificar',
                      icon: Icons.check_rounded,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResendRow(ThemeData theme) {
    if (_resendTimer > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _resendTimer / 60,
                  backgroundColor: AppColors.surfaceContainerHighest,
                  color: AppColors.secondary,
                  strokeWidth: 2.5,
                ),
                Text(
                  '$_resendTimer',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Reenviar código',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return TextButton.icon(
      onPressed: _resendCode,
      icon: const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('Reenviar código'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.secondary,
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
