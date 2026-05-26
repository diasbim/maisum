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
import 'auth_controller.dart';
import 'otp_verification_screen.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  bool _isLoading = false;
  bool _hasInput = false;

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
    _phoneController.addListener(() {
      final hasInput = _phoneController.text.trim().isNotEmpty;
      if (hasInput != _hasInput) setState(() => _hasInput = hasInput);
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

  void _sendCode() async {
    final rawNumber = _phoneController.text.trim();
    String cleanNumber;
    try {
      cleanNumber = MozPhoneUtils.normalizeToE164(rawNumber);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!await ConnectivityCheck.isConnected()) {
      if (!mounted) return;
      ConnectivityCheck.showNoConnectionSnackBar(context);
      return;
    }
    setState(() => _isLoading = true);
    await ref.read(authControllerProvider.notifier).requestOtp(
          phone: cleanNumber,
          onCodeSent: (verificationId) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Codigo de verificacao enviado com sucesso'),
                backgroundColor: AppColors.secondary,
              ),
            );
            context.push('/otp',
                extra: OtpScreenArgs(
                    phone: cleanNumber, verificationId: verificationId));
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(error.isEmpty ? AppStrings.erroAuth : error)),
            );
          },
          onAutoVerify: (credential) async {
            if (!mounted) return;
            setState(() => _isLoading = false);
            try {
              await ref
                  .read(authControllerProvider.notifier)
                  .signInWithCredential(
                      phone: cleanNumber, credential: credential);
              if (!mounted) return;
              final hasPin =
                  await ref.read(secureStorageServiceProvider).hasPin();
              if (mounted) context.go(hasPin ? '/pin-entry' : '/pin-setup');
            } catch (e, st) {
              AppErrorReporter.report(e, st, hint: 'auth_auto_verify');
              if (mounted) context.go('/pin-setup');
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthStepProgress(currentStep: 0),
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
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Qual e o seu\nnumero de telefone?',
                          style: theme.textTheme.displaySmall),
                      const SizedBox(height: 12),
                      Text(
                        'Enviaremos um codigo SMS para confirmar a sua identidade.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurfaceVariant, height: 1.6),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'NUMERO DE TELEFONE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('phone_input'),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: MozPhoneUtils.validatorMessage,
                        controller: _phoneController,
                        focusNode: _phoneFocusNode,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_isLoading && _hasInput) _sendCode();
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
                          MozPhoneInputFormatter(),
                        ],
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: '84 326 2347',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                              color: AppColors.mediumGray,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0),
                          prefix: const _CountryCodePrefix(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.secondary, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.error, width: 2),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.error, width: 2),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.lock_rounded,
                              size: 13, color: AppColors.secondary),
                          const SizedBox(width: 6),
                          Text(
                            'Ligacao segura - Encriptado de ponta a ponta',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.secondary, letterSpacing: 0.1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant, height: 1.65),
                          children: [
                            const TextSpan(
                                text: 'Ao continuar, concorda com os nossos '),
                            TextSpan(
                              text: 'Termos de Servico',
                              recognizer: _termsRecognizer,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.primary),
                            ),
                            const TextSpan(text: ' e '),
                            TextSpan(
                              text: 'Politica de Privacidade',
                              recognizer: _privacyRecognizer,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.primary),
                            ),
                            const TextSpan(
                                text: ', e a receber mensagens SMS.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      AuthGradientButton(
                        key: const Key('send_code_button'),
                        onPressed:
                            (!_isLoading && _hasInput) ? _sendCode : null,
                        isLoading: _isLoading,
                        label: 'Enviar codigo de verificacao',
                        icon: Icons.arrow_forward_rounded,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
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
                      ? AppColors.secondary
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
                        ? AppColors.secondary
                        : AppColors.onSurfaceVariant.withValues(alpha: 0.45),
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

  const AuthGradientButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled ? AppTheme.primaryGradient : null,
          color: enabled ? null : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 16,
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: Colors.white, size: 18),
                    ],
                  ],
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
        const Text('\u{1F1F2}\u{1F1FF}', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(
          '+258',
          style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.5),
        ),
        const SizedBox(width: 12),
        Container(width: 1, height: 20, color: AppColors.outlineVariant),
        const SizedBox(width: 12),
      ],
    );
  }
}
