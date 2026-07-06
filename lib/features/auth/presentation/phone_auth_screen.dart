import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/utils/connectivity_check.dart';
import '../../../core/utils/moz_phone_input_formatter.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../../../core/utils/moz_phone_validator.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../shared/widgets/keyboard_aware_page.dart';
import '../../../design_system/components/maisum_button.dart';
import '../../../design_system/components/loading_button.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../../../design_system/components/maisum_text_field.dart';
import '../../../design_system/components/validation_state.dart';
import 'auth_controller.dart';
import 'otp_verification_screen.dart';
import 'post_auth_navigation.dart';

const _defaultCountryDialCode = '+258';
const _brandNavy = Color(0xFF102A5E);
const _brandAccent = Color(0xFFF4C542);
const _welcomeLogoAsset = 'assets/images/logotypographi.png';
const _welcomeBarberAsset = 'assets/images/welcome.png';

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
  bool _showPhoneForm = false;
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
              final rawMessage = e.toString().trim();
              final message = rawMessage.startsWith('Exception: ')
                  ? rawMessage.substring('Exception: '.length)
                  : rawMessage;
              AppFeedback.showMessage(
                context,
                message: message.isEmpty
                    ? 'Nao foi possivel autenticar automaticamente. Digite o codigo SMS.'
                    : message,
                isError: true,
              );
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
    if (!_showPhoneForm && !canPop) {
      return _WelcomeScreen(
        onStart: () => setState(() => _showPhoneForm = true),
        onTerms: () => context.push('/terms'),
        onPrivacy: () => context.push('/privacy'),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.offWhite,
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
              final narrow = constraints.maxWidth < 360;
              final logoSize = keyboardOpen ? 64.0 : 80.0;
              final titleTopSpacing = keyboardOpen ? 6.0 : 12.0;
              final sectionSpacing = keyboardOpen ? 12.0 : 16.0;
              final horizontalPadding = narrow ? AppSpacing.sm : AppSpacing.xl;
              final surfaceHorizontalPadding =
                  narrow ? AppSpacing.md : AppSpacing.xl;

              return SafeArea(
                top: false,
                child: Center(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: AppSpacing.lg,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.formMaxWidth,
                      ),
                      child: Form(
                        key: _formKey,
                        child: MaisUmSurface(
                          padding: EdgeInsets.fromLTRB(
                            surfaceHorizontalPadding,
                            keyboardOpen ? AppSpacing.lg : AppSpacing.xxl,
                            surfaceHorizontalPadding,
                            keyboardOpen ? AppSpacing.lg : AppSpacing.xxl,
                          ),
                          radius: AppRadius.xl,
                          borderColor: AppColors.g100,
                          shadows: AppShadows.md,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: titleTopSpacing),
                              Center(
                                child: MaisUmSurface(
                                  width: logoSize,
                                  height: logoSize,
                                  radius: AppRadius.lg,
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  backgroundColor: AppColors.primaryDarker,
                                  borderColor: AppColors.secondary,
                                  borderWidth: 1.5,
                                  shadows: AppShadows.sm,
                                  child: Center(
                                    child: BrandMark(
                                      size: keyboardOpen ? 34 : 42,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'Bem-vindo',
                                textAlign: TextAlign.center,
                                style: (compact
                                        ? theme.textTheme.titleLarge
                                        : theme.textTheme.headlineSmall)
                                    ?.copyWith(
                                  color: AppColors.primaryDarker,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
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
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
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
                              const SizedBox(height: AppSpacing.md),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: MaisUmSurface(
                                  variant: MaisUmSurfaceVariant.warning,
                                  radius: AppRadius.pill,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 14,
                                        color: AppColors.secondaryDark,
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text(
                                        'Login seguro via SMS',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: AppColors.primaryDarker,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              LoadingButton(
                                key: const Key('send_code_button'),
                                onPressed: _sendCode,
                                enabled: !_isSendingCode &&
                                    !_isGoogleLoading &&
                                    _canSubmit,
                                isLoading: _isSendingCode,
                                label: 'CONTINUAR',
                                loadingLabel: 'A enviar codigo...',
                                radius: AppRadius.lg,
                                backgroundColor: AppColors.primaryDarker,
                              ),
                              if (!keyboardOpen) ...[
                                const SizedBox(height: AppSpacing.lg),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                      ),
                                      child: Text(
                                        'ou',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
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
                                const SizedBox(height: AppSpacing.lg),
                                KeyedSubtree(
                                  key: const Key('google_auth_button'),
                                  child: MaisUmButton(
                                    onPressed:
                                        (_isSendingCode || _isGoogleLoading)
                                            ? null
                                            : _continueWithGoogle,
                                    isLoading: _isGoogleLoading,
                                    label: 'Continuar com Google',
                                    loadingLabel: 'A autenticar...',
                                    variant: MaisUmButtonVariant.outlined,
                                    leadingIcon: Icons.g_mobiledata_rounded,
                                    height: compact ? 50 : 54,
                                    radius: AppRadius.lg,
                                    backgroundColor: AppColors.white,
                                    foregroundColor: AppColors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
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
                                        text:
                                            'Ao continuar, concorda com os nossos ',
                                      ),
                                      TextSpan(
                                        text: 'Termos de Servico',
                                        recognizer: _termsRecognizer,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: AppColors.primaryDarker,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor:
                                              AppColors.primaryDarker,
                                        ),
                                      ),
                                      const TextSpan(text: ' e '),
                                      TextSpan(
                                        text: 'Politica de Privacidade',
                                        recognizer: _privacyRecognizer,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: AppColors.primaryDarker,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor:
                                              AppColors.primaryDarker,
                                        ),
                                      ),
                                      const TextSpan(text: '.'),
                                    ],
                                  ),
                                ),
                              ],
                              SizedBox(
                                height: keyboardOpen
                                    ? AppSpacing.md
                                    : (compact ? AppSpacing.md : AppSpacing.lg),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({
    required this.onStart,
    required this.onTerms,
    required this.onPrivacy,
  });

  final VoidCallback onStart;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortestSide = media.size.shortestSide;
    final compact = media.size.height < 680;
    final tight = media.size.height < 600;
    final maxWidth = shortestSide >= 600 ? 520.0 : double.infinity;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF001235),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.04, -0.08),
                radius: 0.88,
                colors: [
                  Color(0xFF063D9F),
                  Color(0xFF01235F),
                  Color(0xFF000719),
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          const _WelcomeBackgroundGlow(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF000718).withValues(alpha: 0.10),
                  const Color(0xFF001D55).withValues(alpha: 0.02),
                  const Color(0xFF001136).withValues(alpha: 0.84),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.44, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tightHeight = constraints.maxHeight < 620;
                    final horizontalPadding = tightHeight ? 18.0 : 24.0;
                    final contentWidth =
                        constraints.maxWidth - (horizontalPadding * 2);

                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        tightHeight ? 10 : (compact ? 14 : 24),
                        horizontalPadding,
                        tightHeight ? 10 : 16,
                      ),
                      child: Column(
                        children: [
                          _WelcomeAssetImage(
                            assetName: _welcomeLogoAsset,
                            width: tight ? 146 : (compact ? 168 : 196),
                            fit: BoxFit.contain,
                            semanticLabel: 'MaisUm',
                            fallback: const _WelcomeLogoFallback(),
                          ),
                          SizedBox(height: tight ? 4 : 10),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: contentWidth,
                                  child: _WelcomeHero(compact: compact),
                                ),
                              ),
                            ),
                          ),
                          _WelcomeBenefits(compact: compact),
                          SizedBox(height: tightHeight ? 14 : 20),
                          _WelcomePrimaryButton(
                            compact: tightHeight,
                            onPressed: onStart,
                          ),
                          SizedBox(height: tightHeight ? 8 : 12),
                          const _WelcomeDots(),
                          SizedBox(height: tightHeight ? 6 : 10),
                          _WelcomeTerms(
                            compact: tightHeight,
                            onTerms: onTerms,
                            onPrivacy: onPrivacy,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeBackgroundGlow extends StatelessWidget {
  const _WelcomeBackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 96,
            left: -54,
            right: -54,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.045),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _WelcomeDotPatternPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeDotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var y = size.height * 0.18; y < size.height * 0.48; y += 14) {
      for (var x = 22.0; x < size.width; x += 14) {
        if ((x + y).round().isEven) {
          canvas.drawCircle(Offset(x, y), 0.7, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final heroHeight = compact ? 292.0 : 384.0;
    return SizedBox(
      height: heroHeight,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.center,
        children: [
          Positioned(
            top: compact ? 8 : 4,
            left: compact ? -20 : -34,
            right: compact ? -20 : -34,
            bottom: compact ? -10 : -20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 26 : 34),
              child: _WelcomeAssetImage(
                assetName: _welcomeBarberAsset,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                fallback: _WelcomeBarberFallback(height: heroHeight),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: heroHeight * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF001136).withValues(alpha: 0),
                    const Color(0xFF001136).withValues(alpha: 0.88),
                    const Color(0xFF001136),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: compact ? 18 : 34,
            right: compact ? 18 : 34,
            bottom: compact ? 12 : 18,
            child: const _WelcomeGrowthPill(),
          ),
        ],
      ),
    );
  }
}

class _WelcomeGrowthPill extends StatelessWidget {
  const _WelcomeGrowthPill();

  static const _shadowColor = Color(0x42000000);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up_rounded, color: Color(0xFF2FAA4A), size: 34),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+26% este mes',
                  style: TextStyle(
                    color: Color(0xFF2FAA4A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mais clientes fieis',
                  style: TextStyle(
                    color: _brandNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            SizedBox(width: 12),
            Icon(Icons.groups_rounded, color: _brandAccent, size: 34),
          ],
        ),
      ),
    );
  }
}

class _WelcomeBenefits extends StatelessWidget {
  const _WelcomeBenefits({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _BenefitItem(text: 'Registo em menos\nde 2 minutos.'),
        ),
        _BenefitDivider(),
        Expanded(
          child: _BenefitItem(text: 'Dados sempre\nprotegidos.'),
        ),
        _BenefitDivider(),
        Expanded(
          child: _BenefitItem(
              text: 'Ferramentas para atrair\ne fidelizar clientes.'),
        ),
      ],
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.68),
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.28,
        letterSpacing: 0,
      ),
    );
  }
}

class _BenefitDivider extends StatelessWidget {
  const _BenefitDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white.withValues(alpha: 0.16),
    );
  }
}

class _WelcomeDots extends StatelessWidget {
  const _WelcomeDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 4,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        ),
        const SizedBox(width: 8),
        for (var i = 0; i < 2; i++) ...[
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.34),
              shape: BoxShape.circle,
            ),
          ),
          if (i == 0) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _WelcomePrimaryButton extends StatelessWidget {
  const _WelcomePrimaryButton({
    required this.compact,
    required this.onPressed,
  });

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('welcome_start_button'),
      child: MaisUmButton(
        label: 'Começar agora',
        onPressed: onPressed,
        trailingIcon: Icons.arrow_forward_rounded,
        height: compact ? 62 : 72,
        radius: 999,
        backgroundColor: _brandAccent,
        foregroundColor: _brandNavy,
      ),
    );
  }
}

class _WelcomeTerms extends StatelessWidget {
  const _WelcomeTerms({
    required this.compact,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool compact;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child:
              Icon(Icons.lock_outline_rounded, color: _brandAccent, size: 22),
        ),
        SizedBox(width: compact ? 8 : 10),
        Flexible(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Ao continuar, concorda com os nossos ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  fontSize: compact ? 12 : null,
                ),
              ),
              GestureDetector(
                onTap: onTerms,
                child: Text(
                  'Termos de Servico',
                  style: TextStyle(
                    color: _brandAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: _brandAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : null,
                  ),
                ),
              ),
              Text(
                ' e ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : null,
                ),
              ),
              GestureDetector(
                onTap: onPrivacy,
                child: Text(
                  'Politica de Privacidade.',
                  style: TextStyle(
                    color: _brandAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: _brandAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WelcomeAssetImage extends StatelessWidget {
  const _WelcomeAssetImage({
    required this.assetName,
    required this.fallback,
    this.width,
    this.fit,
    this.alignment = Alignment.center,
    this.semanticLabel,
  });

  final String assetName;
  final Widget fallback;
  final double? width;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetName,
      width: width,
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticLabel,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _WelcomeLogoFallback extends StatelessWidget {
  const _WelcomeLogoFallback();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const BrandMark(size: 42),
        const SizedBox(width: 10),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(text: 'Mais'),
              TextSpan(
                text: 'Um',
                style: TextStyle(color: _brandAccent),
              ),
            ],
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _WelcomeBarberFallback extends StatelessWidget {
  const _WelcomeBarberFallback({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Icon(
            Icons.storefront_rounded,
            size: height * 0.52,
            color: Colors.white.withValues(alpha: 0.16),
          ),
          Icon(
            Icons.phone_iphone_rounded,
            size: height * 0.36,
            color: _brandAccent.withValues(alpha: 0.82),
          ),
        ],
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
