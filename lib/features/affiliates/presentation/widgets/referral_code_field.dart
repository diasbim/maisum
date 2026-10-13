import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../app/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../domain/offline_referral.dart';
import '../../domain/referral_validation.dart';
import '../../providers/affiliate_providers.dart';
import '../../services/referral_copy.dart';

/// What the cashier has typed, and what the server said about it.
///
/// [validation] is advisory. The code is carried to the commit whether or not a
/// preview succeeded, because the commit is the only call that decides, and a
/// till that refused to send an unpreviewed code would fail the sale for a
/// network blip.
class ReferralCodeEntry {
  const ReferralCodeEntry({
    required this.code,
    this.validation,
    this.offline = false,
    this.offlineDecision,
  });

  final String code;
  final ReferralValidationResult? validation;

  /// Connectivity snapshot used only for immediate presentation. The sale
  /// screen resolves current connectivity again when the cashier confirms.
  final bool offline;

  /// What the local cache said about this code, when the preview ran offline.
  ///
  /// Advisory, exactly like [validation]: the commit path re-reads the cache
  /// inside the transaction that writes the sale, so a decision taken here can
  /// never be the one that prices the bill.
  final OfflineReferralDecision? offlineDecision;

  bool get hasCode => code.isNotEmpty;

  bool get isConfirmedValid => validation?.isValid == true;
}

/// The optional referral invitation in the sale flow.
///
/// Collapsed by default and, when left alone, worth exactly zero taps: a sale
/// without a code is confirmed with the same single tap it always was, and
/// never touches the affiliate API.
///
/// It is only built for a customer who could plausibly be new. Offering it for
/// a regular would waste the cashier's attention on an offer the server would
/// refuse with `CUSTOMER_ALREADY_REFERRED` anyway.
class ReferralCodeSection extends ConsumerStatefulWidget {
  const ReferralCodeSection({
    super.key,
    required this.customerPhone,
    required this.grossAmount,
    required this.onChanged,
    this.enabled = true,
    this.customerIsNew = true,
  });

  final String customerPhone;
  final double grossAmount;
  final ValueChanged<ReferralCodeEntry?> onChanged;
  final bool enabled;

  /// What this device knows about the customer, passed down so the offline
  /// preview can run the `firstVisitOnly` check the server would run. It is a
  /// local opinion and is treated as one: the server decides the acquisition.
  final bool customerIsNew;

  @override
  ConsumerState<ReferralCodeSection> createState() =>
      _ReferralCodeSectionState();
}

enum _ReferralPhase {
  idle,
  validating,
  valid,
  invalid,
  unavailable,

  /// Priced from this device's cache, with nothing confirmed.
  offlineCached,

  /// Typed with no cache entry: kept, worth nothing until the server sees it.
  offlineUnknown,
}

class _ReferralCodeSectionState extends ConsumerState<ReferralCodeSection> {
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _expanded = false;
  _ReferralPhase _phase = _ReferralPhase.idle;
  ReferralValidationResult? _result;
  OfflineReferralDecision? _offlineDecision;
  String? _validatedCode;
  double? _validatedAmount;
  String? _failureMessage;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String get _normalizedCode => normalizeReferralCodeInput(_codeCtrl.text);

  bool get _isOnline => ref.read(isOnlineProvider).valueOrNull ?? true;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) {
        _codeCtrl.clear();
        _phase = _ReferralPhase.idle;
        _result = null;
        _offlineDecision = null;
        _validatedCode = null;
        _validatedAmount = null;
        _failureMessage = null;
      }
    });
    widget.onChanged(_expanded ? _currentEntry() : null);
    if (_expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    }
  }

  ReferralCodeEntry? _currentEntry() {
    final code = _normalizedCode;
    if (code.isEmpty) return null;
    return ReferralCodeEntry(
      code: code,
      validation: _validatedCode == code ? _result : null,
      offline: !_isOnline,
      offlineDecision: _validatedCode == code ? _offlineDecision : null,
    );
  }

  void _notify() => widget.onChanged(_currentEntry());

  /// Runs the preview, once per code.
  ///
  /// Guarded rather than debounced: validation is an explicit action here. The
  /// first guard stops a double tap from making two calls at once; the second
  /// stops a cashier from re-spending the rate-limited budget on an answer that
  /// is already on screen — while still allowing a re-check when the amount
  /// changed, because a percentage benefit is worth a different number then.
  Future<void> _validate() async {
    if (_phase == _ReferralPhase.validating) return;
    final code = _normalizedCode;
    if (!isReferralCodeLongEnough(code)) return;
    final alreadyAnswered =
        _phase == _ReferralPhase.valid || _phase == _ReferralPhase.invalid;
    if (alreadyAnswered &&
        _validatedCode == code &&
        _validatedAmount == widget.grossAmount) {
      return;
    }
    if (!_isOnline) {
      await _previewFromCache(code);
      return;
    }

    setState(() {
      _phase = _ReferralPhase.validating;
      _failureMessage = null;
    });

    try {
      final result = await ref.read(affiliateSaleApiProvider).validateCode(
            code: code,
            customerPhone: widget.customerPhone,
            saleAmount: widget.grossAmount > 0 ? widget.grossAmount : null,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _offlineDecision = null;
        _validatedCode = code;
        _validatedAmount = widget.grossAmount;
        _phase = result.isValid ? _ReferralPhase.valid : _ReferralPhase.invalid;
        _failureMessage =
            result.isValid ? null : referralRejectionMessage(result);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ReferralPhase.unavailable;
        _result = null;
        _validatedCode = null;
        _failureMessage = 'Não foi possível confirmar o código agora. '
            'Pode continuar a venda.';
      });
    }
    _notify();
  }

  /// The offline preview, read from the codes this device was told about.
  ///
  /// A cached code shows the benefit it will apply and says plainly that the
  /// indication is not confirmed. An uncached one shows no benefit at all —
  /// inventing a discount for a code nobody has seen is how a business gives
  /// away money to a code that does not exist — and the typed code is still
  /// carried to the sale so the server can judge it later.
  Future<void> _previewFromCache(String code) async {
    final repository = ref.read(affiliateOfflineGatewayProvider);
    if (repository == null) {
      setState(() {
        _phase = _ReferralPhase.offlineUnknown;
        _offlineDecision = null;
        _validatedCode = code;
        _validatedAmount = widget.grossAmount;
        _failureMessage = null;
      });
      _notify();
      return;
    }

    setState(() {
      _phase = _ReferralPhase.validating;
      _failureMessage = null;
    });

    final decision = await repository.previewOfflineReferral(
      code: code,
      grossAmount: widget.grossAmount,
      customerIsNew: widget.customerIsNew,
      customerPhoneE164: widget.customerPhone,
    );
    if (!mounted) return;
    setState(() {
      _result = null;
      _offlineDecision = decision;
      _validatedCode = code;
      _validatedAmount = widget.grossAmount;
      _phase = decision.appliesBenefit
          ? _ReferralPhase.offlineCached
          : _ReferralPhase.offlineUnknown;
      _failureMessage = decision.errorCode == null
          ? null
          : referralErrorMessage(decision.errorCode);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return MaisUmSurface(
      width: double.infinity,
      variant: MaisUmSurfaceVariant.muted,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      animationDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReferralToggle(
            expanded: _expanded,
            onTap: widget.enabled ? _toggle : null,
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            MaisUmTextField(
              fieldKey: const Key('referral-code-field'),
              controller: _codeCtrl,
              focusNode: _codeFocus,
              hintText: 'Ex.: AFI-ANA-7K2P',
              label: 'Código de indicação',
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              enabled: widget.enabled && _phase != _ReferralPhase.validating,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                LengthLimitingTextInputFormatter(40),
              ],
              onChanged: (_) {
                setState(() {
                  if (_validatedCode != _normalizedCode) {
                    _phase = _ReferralPhase.idle;
                    _failureMessage = null;
                  }
                });
                _notify();
              },
              onFieldSubmitted: (_) => _validate(),
            ),
            const SizedBox(height: AppSpacing.md),
            MaisUmButton(
              key: const Key('referral-validate-button'),
              label: 'Validar',
              loadingLabel: 'A validar…',
              isLoading: _phase == _ReferralPhase.validating,
              variant: MaisUmButtonVariant.outlined,
              foregroundColor: AppColors.primary,
              onPressed: widget.enabled &&
                      isReferralCodeLongEnough(_normalizedCode) &&
                      _phase != _ReferralPhase.validating
                  ? _validate
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _ReferralStatusPanel(
              phase: _phase,
              result: _result,
              offlineDecision: _offlineDecision,
              failureMessage: _failureMessage,
              online: online,
              amountChanged: _validatedAmount != null &&
                  _validatedAmount != widget.grossAmount,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferralToggle extends StatelessWidget {
  const _ReferralToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: 'Tem código de indicação? Opcional.',
      child: InkWell(
        key: const Key('referral-code-toggle'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppControlSize.iconButton,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.local_offer_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Tem código de indicação?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const Text(
                'Opcional',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one line the cashier reads back to the customer.
///
/// Never shows an identifier: the affiliate is a first name and the benefit is
/// the server's own wording, because those are the two things a person at a
/// counter can act on.
class _ReferralStatusPanel extends StatelessWidget {
  const _ReferralStatusPanel({
    required this.phase,
    required this.result,
    required this.offlineDecision,
    required this.failureMessage,
    required this.online,
    required this.amountChanged,
  });

  final _ReferralPhase phase;
  final ReferralValidationResult? result;
  final OfflineReferralDecision? offlineDecision;
  final String? failureMessage;
  final bool online;
  final bool amountChanged;

  @override
  Widget build(BuildContext context) {
    if (!online &&
        phase != _ReferralPhase.valid &&
        phase != _ReferralPhase.offlineCached &&
        phase != _ReferralPhase.offlineUnknown &&
        phase != _ReferralPhase.validating) {
      return const _ReferralNotice(
        key: Key('referral-offline-notice'),
        icon: Icons.wifi_off_rounded,
        variant: MaisUmSurfaceVariant.warning,
        color: AppColors.warning,
        title: 'Sem ligação',
        message: 'Escreva o código e toque em Validar para ver se este '
            'aparelho já o conhece.',
      );
    }

    switch (phase) {
      case _ReferralPhase.idle:
        return const _ReferralNotice(
          key: Key('referral-idle-notice'),
          icon: Icons.info_outline_rounded,
          variant: MaisUmSurfaceVariant.muted,
          color: AppColors.onSurfaceVariant,
          title: 'Sem código a venda continua igual',
          message: 'Escreva o código e toque em Validar.',
        );
      case _ReferralPhase.validating:
        return const _ReferralNotice(
          key: Key('referral-validating-notice'),
          icon: Icons.hourglass_top_rounded,
          variant: MaisUmSurfaceVariant.muted,
          color: AppColors.onSurfaceVariant,
          title: 'A validar código',
          message: 'Um momento.',
        );
      case _ReferralPhase.invalid:
      case _ReferralPhase.unavailable:
        return _ReferralNotice(
          key: const Key('referral-invalid-notice'),
          icon: Icons.error_outline_rounded,
          variant: MaisUmSurfaceVariant.error,
          color: AppColors.error,
          title: 'Código não aplicado',
          message: '${failureMessage ?? 'Não foi possível usar este código.'} '
              'Pode concluir a venda normalmente.',
        );
      case _ReferralPhase.offlineCached:
        // The one screen where a benefit is promised without the server having
        // agreed to it. It has to say so in the same breath, because a cashier
        // who reads "código válido" tells the customer the affiliate has been
        // credited, and nobody has been credited yet.
        final benefit = offlineDecision?.benefit;
        final affiliate = offlineDecision?.cache?.affiliateFirstName ??
            offlineDecision?.cache?.affiliateDisplayName;
        return _ReferralNotice(
          key: const Key('referral-offline-cached-notice'),
          icon: Icons.schedule_rounded,
          variant: MaisUmSurfaceVariant.warning,
          color: AppColors.warning,
          title: 'Pendente de confirmação',
          message: [
            if (benefit != null) 'Cliente recebe: ${benefit.displayText}',
            if (affiliate != null) 'Afiliado: $affiliate',
            'A indicação só é confirmada quando houver ligação.',
          ].join(' · '),
        );
      case _ReferralPhase.offlineUnknown:
        return _ReferralNotice(
          key: const Key('referral-offline-unknown-notice'),
          icon: Icons.wifi_off_rounded,
          variant: MaisUmSurfaceVariant.warning,
          color: AppColors.warning,
          title: 'Código guardado, sem benefício agora',
          message: [
            failureMessage ??
                'Este aparelho ainda não conhece este código, por isso a venda '
                    'fica pelo valor total.',
            'O código segue com a venda e é verificado quando houver ligação.',
          ].join(' '),
        );
      case _ReferralPhase.valid:
        final validation = result;
        final affiliate = validation?.affiliateFirstName;
        final benefit =
            validation == null ? null : referralBenefitText(validation);
        return _ReferralNotice(
          key: const Key('referral-valid-notice'),
          icon: Icons.check_circle_outline_rounded,
          variant: MaisUmSurfaceVariant.success,
          color: AppColors.success,
          title: 'Código válido',
          message: [
            if (benefit != null) 'Cliente recebe: $benefit',
            if (affiliate != null) 'Afiliado: $affiliate',
            if (amountChanged)
              'O valor mudou depois da validação. Valide outra vez para '
                  'confirmar o benefício.',
          ].join(' · '),
        );
    }
  }
}

class _ReferralNotice extends StatelessWidget {
  const _ReferralNotice({
    super.key,
    required this.icon,
    required this.variant,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final MaisUmSurfaceVariant variant;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '$title. $message',
      excludeSemantics: true,
      child: MaisUmSurface(
        width: double.infinity,
        variant: variant,
        radius: AppRadius.md,
        padding: const EdgeInsets.all(AppSpacing.md),
        animationDuration: Duration.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
