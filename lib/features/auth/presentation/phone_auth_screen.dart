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

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
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
              message: 'Código de verificação enviado com sucesso',
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
                    ? 'Não foi possível autenticar automaticamente. Introduza o código por SMS.'
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
            ? 'Não foi possível autenticar com o Google. Tente novamente.'
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
      backgroundColor: AppColors.primaryDarker,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (canPop) {
              Navigator.of(context).pop();
              return;
            }
            setState(() => _showPhoneForm = false);
          },
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.xl),
            child: _SecureAccessBadge(),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryDarker,
              AppColors.primary,
              Color(0xFF243D68),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _AuthBackground()),
            FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: KeyboardAwarePage(
                  builder: (context, keyboardOpen, constraints) {
                    final compact = constraints.maxHeight < 680;
                    final narrow = constraints.maxWidth < 360;
                    final pagePadding = narrow ? AppSpacing.md : AppSpacing.xl;
                    final cardPadding = narrow ? AppSpacing.lg : AppSpacing.xxl;

                    return SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            pagePadding,
                            keyboardOpen ? 8 : (compact ? 16 : 28),
                            pagePadding,
                            keyboardOpen ? 12 : 24,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppLayout.formMaxWidth,
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!keyboardOpen)
                                    _PhoneAuthHero(compact: compact),
                                  if (!keyboardOpen)
                                    SizedBox(
                                      height: compact
                                          ? AppSpacing.lg
                                          : AppSpacing.xxl,
                                    ),
                                  MaisUmSurface(
                                    padding: EdgeInsets.all(cardPadding),
                                    radius: AppRadius.xxl,
                                    backgroundColor: AppColors.white,
                                    borderColor:
                                        Colors.white.withValues(alpha: 0.72),
                                    shadows: AppShadows.lg,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const AuthStepProgress(currentStep: 0),
                                        SizedBox(
                                          height: compact
                                              ? AppSpacing.lg
                                              : AppSpacing.xxl,
                                        ),
                                        Text(
                                          'O seu número',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            color: AppColors.primaryDarker,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          'Enviaremos um código único por SMS. Sem palavras-passe.',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                            height: 1.45,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        Semantics(
                                          label:
                                              'Número de telemóvel de Moçambique',
                                          textField: true,
                                          child: Container(
                                            key: _phoneFieldKey,
                                            child: MaisUmTextField(
                                              fieldKey:
                                                  const Key('phone_input'),
                                              autovalidateMode:
                                                  AutovalidateMode.disabled,
                                              validator: _phoneValidator,
                                              controller: _phoneController,
                                              focusNode: _phoneFocusNode,
                                              keyboardType:
                                                  TextInputType.number,
                                              textInputAction:
                                                  TextInputAction.done,
                                              onFieldSubmitted: (_) {
                                                if (!_isSendingCode &&
                                                    !_isGoogleLoading) {
                                                  _sendCode();
                                                }
                                              },
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                    9),
                                                MozPhoneFormatter(),
                                              ],
                                              label: 'Número de telemóvel',
                                              hintText: '84 326 2347',
                                              prefix:
                                                  const _CountryCodePrefix(),
                                              validationState:
                                                  _phoneValidationState,
                                              showValidIcon: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        const _SmsTrustMessage(),
                                        const SizedBox(height: AppSpacing.lg),
                                        LoadingButton(
                                          key: const Key('send_code_button'),
                                          onPressed: _sendCode,
                                          enabled: !_isSendingCode &&
                                              !_isGoogleLoading &&
                                              _canSubmit,
                                          isLoading: _isSendingCode,
                                          label: 'CONTINUAR',
                                          loadingLabel: 'A enviar código...',
                                          radius: AppRadius.lg,
                                          backgroundColor:
                                              AppColors.primaryDarker,
                                        ),
                                        if (!keyboardOpen) ...[
                                          const SizedBox(height: AppSpacing.lg),
                                          const _AuthDivider(),
                                          const SizedBox(height: AppSpacing.lg),
                                          KeyedSubtree(
                                            key:
                                                const Key('google_auth_button'),
                                            child: MaisUmButton(
                                              onPressed: (_isSendingCode ||
                                                      _isGoogleLoading)
                                                  ? null
                                                  : _continueWithGoogle,
                                              isLoading: _isGoogleLoading,
                                              label: 'Continuar com Google',
                                              loadingLabel: 'A autenticar...',
                                              variant:
                                                  MaisUmButtonVariant.outlined,
                                              leadingIcon:
                                                  Icons.g_mobiledata_rounded,
                                              radius: AppRadius.lg,
                                              foregroundColor:
                                                  AppColors.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.md),
                                          _AuthLegalLinks(
                                            key: const Key('terms_section'),
                                            compact: compact,
                                            onTerms: () =>
                                                context.push('/terms'),
                                            onPrivacy: () =>
                                                context.push('/privacy'),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
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
          ],
        ),
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 60,
            right: -90,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecureAccessBadge extends StatelessWidget {
  const _SecureAccessBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Acesso seguro',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 15),
            SizedBox(width: AppSpacing.xs),
            Text(
              'Seguro',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneAuthHero extends StatelessWidget {
  const _PhoneAuthHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 56 : 64,
          height: compact ? 56 : 64,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: BrandMark(size: compact ? 30 : 36),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Bem-vindo',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Entre na sua conta ou comece agora.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.70),
              ),
        ),
      ],
    );
  }
}

class _SmsTrustMessage extends StatelessWidget {
  const _SmsTrustMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sms_outlined,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Código gratuito por SMS. O número é usado apenas para confirmar a sua identidade.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.primaryDarker,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.g100)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'ou continue com',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.g100)),
      ],
    );
  }
}

class _AuthLegalLinks extends StatelessWidget {
  const _AuthLegalLinks({
    super.key,
    required this.compact,
    required this.onTerms,
    required this.onPrivacy,
    this.foregroundColor = AppColors.onSurfaceVariant,
    this.linkColor = AppColors.primary,
  });

  final bool compact;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final Color foregroundColor;
  final Color linkColor;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foregroundColor,
          fontSize: compact ? 10 : 11,
          height: 1.35,
        );
    final linkStyle = TextButton.styleFrom(
      foregroundColor: linkColor,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      tapTargetSize: MaterialTapTargetSize.padded,
      textStyle: textStyle?.copyWith(
        color: linkColor,
        fontWeight: FontWeight.w800,
        decoration: TextDecoration.underline,
      ),
    );

    return Semantics(
      container: true,
      label: 'Informação legal',
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Ao continuar, aceita os', style: textStyle),
          TextButton(
            onPressed: onTerms,
            style: linkStyle,
            child: const Text('Termos'),
          ),
          Text('e a', style: textStyle),
          TextButton(
            onPressed: onPrivacy,
            style: linkStyle,
            child: const Text('Privacidade'),
          ),
        ],
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
    final compact = media.size.height < 700;
    final tight = media.size.height < 610;
    final maxWidth = shortestSide >= 600 ? 520.0 : double.infinity;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.primaryDarker,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0D2652),
                  AppColors.primary,
                  AppColors.primaryDarker,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const _WelcomeBackgroundGlow(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tightHeight = constraints.maxHeight < 620;
                    final horizontalPadding = tightHeight ? 16.0 : 24.0;
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
                          const _WelcomeBrand(),
                          SizedBox(height: tight ? 8 : 16),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: contentWidth,
                                  child: Column(
                                    children: [
                                      const _WelcomeEyebrow(),
                                      SizedBox(height: tight ? 10 : 16),
                                      Text(
                                        'Clientes que voltam.\nNegócios que crescem.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              height: 1.05,
                                              letterSpacing: -0.7,
                                            ),
                                      ),
                                      SizedBox(height: tight ? 8 : 12),
                                      Text(
                                        'Fidelização, vendas e clientes num só lugar — simples desde o primeiro dia.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.72),
                                              height: 1.45,
                                            ),
                                      ),
                                      SizedBox(height: tight ? 12 : 22),
                                      _WelcomeHero(compact: compact),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: tightHeight ? 8 : 14),
                          _WelcomeBenefits(compact: compact),
                          SizedBox(height: tightHeight ? 12 : 18),
                          _WelcomePrimaryButton(
                            compact: tightHeight,
                            onPressed: onStart,
                          ),
                          SizedBox(height: tightHeight ? 8 : 12),
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

class _WelcomeBrand extends StatelessWidget {
  const _WelcomeBrand();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'MaisUm',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const BrandMark(size: 26),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Mais'),
                TextSpan(
                  text: 'Um',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeEyebrow extends StatelessWidget {
  const _WelcomeEyebrow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.secondary,
            size: 16,
          ),
          SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Feito para pequenos negócios',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeAvatar extends StatelessWidget {
  const _WelcomeAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Icon(
        Icons.storefront_rounded,
        color: AppColors.primary,
        size: 22,
      ),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: AppColors.green, size: 7),
          SizedBox(width: AppSpacing.xs),
          Text(
            'Hoje',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeMetric extends StatelessWidget {
  const _WelcomeMetric({
    required this.icon,
    required this.value,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.primaryDarker : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.secondary
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.84), size: 18),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.72),
                  fontSize: 10,
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
            top: 80,
            right: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -140,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
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
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const _WelcomeAvatar(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bom dia, Ana',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      'O seu negócio está a crescer',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                    ),
                  ],
                ),
              ),
              const _LiveIndicator(),
            ],
          ),
          SizedBox(height: compact ? 12 : 18),
          const Row(
            children: [
              Expanded(
                child: _WelcomeMetric(
                  icon: Icons.groups_rounded,
                  value: '128',
                  label: 'clientes',
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _WelcomeMetric(
                  icon: Icons.trending_up_rounded,
                  value: '+26%',
                  label: 'este mês',
                  highlighted: true,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _WelcomeMetric(
                  icon: Icons.stars_rounded,
                  value: '4,9',
                  label: 'avaliação',
                ),
              ),
            ],
          ),
        ],
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
      children: [
        Expanded(
          child: _BenefitItem(
            icon: Icons.bolt_rounded,
            text: 'Rápido',
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _BenefitItem(
            icon: Icons.shield_outlined,
            text: 'Seguro',
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _BenefitItem(
            icon: Icons.cloud_off_rounded,
            text: 'Funciona offline',
          ),
        ),
      ],
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: AppColors.secondary),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
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
        label: 'Entrar ou criar conta',
        onPressed: onPressed,
        trailingIcon: Icons.arrow_forward_rounded,
        height: compact ? 56 : 60,
        radius: AppRadius.lg,
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
    return _AuthLegalLinks(
      compact: compact,
      onTerms: onTerms,
      onPrivacy: onPrivacy,
      foregroundColor: Colors.white.withValues(alpha: 0.62),
      linkColor: AppColors.secondary,
    );
  }
}

// ── Shared auth widgets (exported so OTP screen can reuse them) ───────────────

class AuthStepProgress extends StatelessWidget {
  final int currentStep;
  const AuthStepProgress({super.key, required this.currentStep});
  static const _labels = ['Telemóvel', 'Verificar', 'PIN', 'Pronto'];

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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
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
