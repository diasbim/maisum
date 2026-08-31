import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../design_system/design_system.dart';
import 'auth_controller.dart';
import '../domain/auth_session.dart';
import 'post_auth_navigation.dart';
import 'phone_auth_screen.dart';

class OtpScreenArgs {
  const OtpScreenArgs({
    required this.phone,
    required this.verificationId,
    this.actor = AuthActor.merchant,
  });

  final String phone;
  final String verificationId;
  final AuthActor actor;
}

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.actor = AuthActor.merchant,
  });

  final AuthActor actor;

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
    ref.read(authControllerProvider.notifier).requestOtp(
          phone: widget.phoneNumber,
          actor: widget.actor,
          onCodeSent: (newVerificationId) {
            _verificationId = newVerificationId;
            AppFeedback.showSuccessToast(
              context,
              message: 'Código de verificação reenviado',
            );
          },
          onError: (error) {
            AppFeedback.showMessage(
              context,
              message: error,
              isError: true,
            );
          },
        );
  }

  void _verifyOTP([String? pin]) async {
    final otp = pin ?? _pinController.text;
    if (otp.length != 6) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: 'Introduza o código completo',
        isError: true,
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
            actor: widget.actor,
          );
      if (!mounted) return;
      if (widget.actor == AuthActor.customer) {
        context.go('/customer/home');
        return;
      }
      final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
      if (!mounted) return;
      if (hasPin) {
        context.go('/pin-entry');
        return;
      }
      final route = await resolvePostAuthRoute(ref.read);
      if (mounted) context.go(route);
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'auth_otp_verify_button');
      if (widget.actor == AuthActor.customer &&
          e is CustomerFeatureDisabledException) {
        if (mounted) context.go('/customer-disabled');
        return;
      }
      _submitInFlight = false;
      setState(() => _isVerifying = false);
      _pinController.clear();
      if (!mounted) return;
      final rawMessage = e.toString().trim();
      final message = rawMessage.startsWith('Exception: ')
          ? rawMessage.substring('Exception: '.length)
          : rawMessage;
      AppFeedback.showMessage(
        context,
        message: message.isEmpty
            ? 'Não foi possível validar o código. Tente novamente.'
            : message,
        isError: true,
      );
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
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5)),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthStepProgress(
                      currentStep: 1,
                      labels: widget.actor == AuthActor.customer
                          ? const ['Telemóvel', 'Verificar']
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    MaisUmSurface(
                      width: 56,
                      height: 56,
                      radius: AppRadius.lg,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      backgroundColor: AppColors.primaryDarker,
                      borderColor: AppColors.primaryDarker,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Introduza o código\nde verificação',
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                        const SizedBox(width: AppSpacing.sm),
                        if (Navigator.of(context).canPop())
                          MaisUmButton(
                            onPressed: () => Navigator.of(context).pop(),
                            label: 'Editar',
                            variant: MaisUmButtonVariant.ghost,
                            height: 36,
                            radius: AppRadius.md,
                            fullWidth: false,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
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
                    const SizedBox(height: AppSpacing.xxl),
                    Center(child: _buildResendRow(theme)),
                    const Spacer(),
                    const SizedBox(height: AppSpacing.lg),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            size: 13,
                            color: AppColors.secondary,
                          ),
                          Text(
                            'Código válido por 10 minutos',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AuthGradientButton(
                      key: const Key('verify_button'),
                      onPressed: _isVerifying ? null : _verifyOTP,
                      isLoading: _isVerifying,
                      label: 'Verificar',
                      icon: Icons.check_rounded,
                    ),
                    const SizedBox(height: AppSpacing.xl),
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
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
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
          Text(
            'Reenviar código',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return MaisUmButton(
      onPressed: _resendCode,
      label: 'Reenviar código',
      leadingIcon: Icons.refresh_rounded,
      variant: MaisUmButtonVariant.ghost,
      foregroundColor: AppColors.secondary,
      fullWidth: false,
      height: 40,
    );
  }
}
