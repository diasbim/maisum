import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/utils/connectivity_check.dart';
import '../../../core/utils/moz_phone_input_formatter.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../../../core/utils/moz_phone_validator.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../shared/widgets/keyboard_aware_page.dart';
import '../../../design_system/components/loading_button.dart';
import '../../../design_system/components/maisum_text_field.dart';
import '../../../design_system/components/validation_state.dart';
import 'auth_controller.dart';
import 'otp_verification_screen.dart';
import 'post_auth_navigation.dart';

const _defaultCountryDialCode = '+258';
const _loginBackground = Color(0xFFF8F9FC);
const _brandNavy = Color(0xFF102A5E);
const _brandAccent = Color(0xFFF4C542);

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final GlobalKey _phoneFieldKey = GlobalKey();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSendingCode = false;
  bool _isGoogleLoading = false;
  bool _canSubmit = false;
  bool _hasSubmitted = false;
  ValidationState _phoneValidationState = ValidationState.neutral;

  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => context.push('/terms');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => context.push('/privacy');
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim =
        CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));
    _entryController.forward();
    _phoneFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        if (_phoneFocusNode.hasFocus) {
          _phoneValidationState = ValidationState.focused;
          return;
        }

        final hasValue = _phoneController.text.trim().isNotEmpty;
        if (!_hasSubmitted && !hasValue) {
          _phoneValidationState = ValidationState.neutral;
          return;
        }

        _phoneValidationState =
            MozPhoneValidator.isValidLocalPhone(_phoneController.text)
                ? ValidationState.valid
                : ValidationState.invalid;
      });

      if (_phoneFocusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final fieldContext = _phoneFieldKey.currentContext;
          if (fieldContext == null) return;
          Scrollable.ensureVisible(
            fieldContext,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: 0.2,
          );
        });
      }
    });
    _phoneController.addListener(() {
      final digitsOnly = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      final canSubmit = MozPhoneValidator.isValidLocalPhone(digitsOnly);
      if (canSubmit != _canSubmit) {
        setState(() => _canSubmit = canSubmit);
      }
      if (_hasSubmitted && !_phoneFocusNode.hasFocus) {
        setState(() {
          _phoneValidationState =
              canSubmit ? ValidationState.valid : ValidationState.invalid;
        });
        _formKey.currentState?.validate();
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _entryController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  String? _phoneValidator(String? value) {
    if (!_hasSubmitted && _phoneFocusNode.hasFocus) {
      return null;
    }

    return MozPhoneValidator.validationMessage(value);
  }

  void _sendCode() async {
    FocusScope.of(context).unfocus();
    if (!_hasSubmitted) {
      setState(() => _hasSubmitted = true);
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final rawNumber = _phoneController.text.trim();
    String cleanNumber;
    try {
      cleanNumber = MozPhoneUtils.normalizeToE164(rawNumber);
    } on FormatException catch (e) {
      AppFeedback.showMessage(context, message: e.message, isError: true);
      return;
    }
    if (!await ConnectivityCheck.isConnected()) {
      if (!mounted) return;
      ConnectivityCheck.showNoConnectionSnackBar(context);
      return;
    }
    setState(() => _isSendingCode = true);
    await ref.read(authControllerProvider.notifier).requestOtp(
          phone: cleanNumber,
          onCodeSent: (verificationId) {
            if (!mounted) return;
            setState(() => _isSendingCode = false);
            AppFeedback.showSuccessToast(
              context,
              message: 'Codigo de verificacao enviado com sucesso',
            );
            context.push('/otp',
                extra: OtpScreenArgs(
                    phone: cleanNumber, verificationId: verificationId));
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _isSendingCode = false);
            AppFeedback.showMessage(
              context,
              message: error.isEmpty ? AppStrings.erroAuth : error,
              isError: true,
            );
          },
          onAutoVerify: (credential) async {
            if (!mounted) return;
            setState(() => _isSendingCode = false);
            try {
              await ref
                  .read(authControllerProvider.notifier)
                  .signInWithCredential(
                      phone: cleanNumber, credential: credential);
              if (!mounted) return;
              final hasPin =
                  await ref.read(secureStorageServiceProvider).hasPin();
              if (!mounted) return;
              if (hasPin) {
                context.go('/pin-entry');
                return;
              }
              final route = await resolvePostAuthRoute(ref.read);
              if (!mounted) return;
              context.go(route);
            } catch (e, st) {
              AppErrorReporter.report(e, st, hint: 'auth_auto_verify');
              if (!mounted) return;
              final route = await resolvePostAuthRoute(ref.read);
              if (mounted) context.go(route);
            }
          },
        );
  }

  Future<void> _continueWithGoogle() async {
    if (_isSendingCode || _isGoogleLoading) return;

    if (!await ConnectivityCheck.isConnected()) {
      if (!mounted) return;
      ConnectivityCheck.showNoConnectionSnackBar(context);
      return;
    }

    setState(() => _isGoogleLoading = true);
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
      if (!mounted) return;
      if (hasPin) {
        context.go('/pin-entry');
        return;
      }
      final route = await resolvePostAuthRoute(ref.read);
      if (!mounted) return;
      context.go(route);
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'auth_google_button');
      if (!mounted) return;
      final rawMessage = e.toString().trim();
      final message = rawMessage.startsWith('Exception: ')
          ? rawMessage.substring('Exception: '.length)
          : rawMessage;
      AppFeedback.showMessage(
        context,
        message: message.isEmpty
            ? 'Nao foi possivel autenticar com Google. Tente novamente.'
            : message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _loginBackground,
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: _brandNavy,
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: KeyboardAwarePage(
            builder: (context, keyboardOpen, constraints) {
              final compact = constraints.maxHeight < 640;
              final logoSize = keyboardOpen ? 64.0 : 80.0;
              final titleTopSpacing = keyboardOpen ? 6.0 : 12.0;
              final sectionSpacing = keyboardOpen ? 12.0 : 16.0;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: titleTopSpacing),
                      Center(
                        child: Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _brandAccent.withValues(alpha: 0.7),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _brandNavy.withValues(alpha: 0.08),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: BrandMark(size: keyboardOpen ? 34 : 42),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Bem-vindo 👋',
                        textAlign: TextAlign.center,
                        style: (compact
                                ? theme.textTheme.titleLarge
                                : theme.textTheme.headlineSmall)
                            ?.copyWith(
                          color: _brandNavy,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Entre com o seu numero\npara continuar.',
                        textAlign: TextAlign.center,
                        style: (compact
                                ? theme.textTheme.bodySmall
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: sectionSpacing),
                      Text(
                        'Numero de telefone',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _brandNavy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        key: _phoneFieldKey,
                        child: MaisUmTextField(
                          fieldKey: const Key('phone_input'),
                          autovalidateMode: AutovalidateMode.disabled,
                          validator: _phoneValidator,
                          controller: _phoneController,
                          focusNode: _phoneFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_isSendingCode && !_isGoogleLoading) {
                              _sendCode();
                            }
                          },
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                            MozPhoneFormatter(),
                          ],
                          hintText: '84 326 2347',
                          prefix: const _CountryCodePrefix(),
                          validationState: _phoneValidationState,
                          showValidIcon: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _brandAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _brandAccent.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Text(
                            '🔒 Login seguro via SMS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _brandNavy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      LoadingButton(
                        key: const Key('send_code_button'),
                        onPressed: _sendCode,
                        enabled:
                            !_isSendingCode && !_isGoogleLoading && _canSubmit,
                        isLoading: _isSendingCode,
                        label: 'CONTINUAR',
                        loadingLabel: 'A enviar codigo...',
                        radius: 18,
                        backgroundColor: _brandNavy,
                      ),
                      if (!keyboardOpen) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.onSurfaceVariant
                                    .withValues(alpha: 0.20),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'ou',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.onSurfaceVariant
                                    .withValues(alpha: 0.20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const Key('google_auth_button'),
                            onPressed: (_isSendingCode || _isGoogleLoading)
                                ? null
                                : _continueWithGoogle,
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size.fromHeight(compact ? 50 : 54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              side: BorderSide(
                                color: AppColors.onSurfaceVariant
                                    .withValues(alpha: 0.35),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            child: _isGoogleLoading
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text('A autenticar...'),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: AppColors.outlineVariant,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          'G',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          'Continuar com Google',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            color: AppColors.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        RichText(
                          key: const Key('terms_section'),
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: (compact
                                    ? theme.textTheme.labelSmall
                                    : theme.textTheme.bodySmall)
                                ?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              height: compact ? 1.4 : 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Ao continuar, concorda com os nossos ',
                              ),
                              TextSpan(
                                text: 'Termos de Servico',
                                recognizer: _termsRecognizer,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _brandNavy,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: _brandNavy,
                                ),
                              ),
                              const TextSpan(text: ' e '),
                              TextSpan(
                                text: 'Politica de Privacidade',
                                recognizer: _privacyRecognizer,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _brandNavy,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: _brandNavy,
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(height: keyboardOpen ? 12 : (compact ? 10 : 16)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Shared auth widgets (exported so OTP screen can reuse them) ───────────────

class AuthStepProgress extends StatelessWidget {
  final int currentStep;
  const AuthStepProgress({super.key, required this.currentStep});
  static const _labels = ['Telefone', 'Verificar', 'PIN', 'Pronto'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final active = i <= currentStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primaryLight
                      : AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(4, (i) {
            final isCurrent = i == currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                child: Text(
                  _labels[i],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isCurrent
                        ? AppColors.primaryLight
                        : AppColors.onSurfaceVariant.withValues(alpha: 0.75),
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class AuthGradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
  final IconData? icon;
  final double borderRadius;
  final Color? solidColor;

  const AuthGradientButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.label,
    this.icon,
    this.borderRadius = 22,
    this.solidColor,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient:
              enabled && solidColor == null ? AppTheme.primaryGradient : null,
          color: enabled ? solidColor : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: (solidColor ?? AppColors.primary)
                        .withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final showIcon =
                        icon != null && constraints.maxWidth >= 280;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        if (showIcon) ...[
                          const SizedBox(width: 10),
                          Icon(icon, color: Colors.white, size: 24),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _CountryCodePrefix extends StatelessWidget {
  const _CountryCodePrefix();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('\u{1F1F2}\u{1F1FF}', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                _defaultCountryDialCode,
                key: const Key('default_country_code'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _brandNavy,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(width: 1, height: 18, color: AppColors.outlineVariant),
        const SizedBox(width: 10),
      ],
    );
  }
}
