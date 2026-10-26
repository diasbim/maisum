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
import '../../../core/services/firebase_auth_service.dart';

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
    if (_resendTimer > 0 && _hasSession) return;
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

  /// Whether this screen still has a session a code could be checked against.
  ///
  /// False after the verification id is lost — the screen survives, the
  /// session behind it does not. Checked before anything is typed, because
  /// the alternative is letting someone enter a correct code and telling them
  /// it is wrong.
  bool get _hasSession => _verificationId.trim().isNotEmpty;

  void _verifyOTP([String? pin]) async {
    if (!_hasSession) {
      AppFeedback.showMessage(
        context,
        message: 'A sessão expirou. Toque em "Reenviar código".',
        isError: true,
      );
      return;
    }
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
      AppFeedback.showMessage(
        context,
        message: authErrorMessage(e),
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
                    if (!_hasSession) ...[
                      const _SessionLostNotice(key: Key('otp_session_lost')),
                      const SizedBox(height: AppSpacing.lg),
                    ],
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
                        enabled: !_isVerifying && _hasSession,
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
                      // Disabled with a reason shown above, rather than a
                      // button that submits into a session that is gone.
                      onPressed:
                          _isVerifying || !_hasSession ? null : _verifyOTP,
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
    // The countdown exists to stop someone spamming SMS they are waiting for.
    // With no session there is nothing to wait for, and the countdown would
    // be holding shut the only door out of the screen.
    if (_resendTimer > 0 && _hasSession) {
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

/// What `/otp` shows when it is reached without a verification session.
///
/// `extra` carries the verification id and is not serialisable, so it is gone
/// after a process restart, after a deep link, and any other way of arriving
/// here without having just asked for a code. The route used to cast it
/// unchecked and throw — a crash, where the honest answer is short and the
/// way out is one tap.
///
/// Deliberately not a snackbar over an empty code field: a screen that asks
/// for six digits it can never accept is worse than no screen, because the
/// person spends the attempt and reads a failure that sounds like their
/// fault.
class OtpSessionLostScreen extends StatelessWidget {
  const OtpSessionLostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.sms_failed_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'A sessão de verificação expirou',
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Por segurança, o código deixa de ser válido passado algum '
                  'tempo. Introduza o seu número para receber um novo.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: AuthGradientButton(
                    key: const Key('otp_session_lost_restart'),
                    onPressed: () => context.go('/login'),
                    isLoading: false,
                    label: 'Receber novo código',
                    icon: Icons.arrow_forward_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Said before anything is typed, not after it fails.
///
/// The screen can outlive the session it depends on. When that happens the
/// six boxes still render and the button still looks ready, so the only
/// signal used to be an error after the person had found their code and
/// typed it — which reads as "you got it wrong".
class _SessionLostNotice extends StatelessWidget {
  const _SessionLostNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colour is not the only carrier: the icon says it too.
          const Icon(Icons.schedule_rounded, size: 20, color: AppColors.secondaryDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'A sessão de verificação expirou. Toque em "Reenviar código" '
              'para receber um novo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
