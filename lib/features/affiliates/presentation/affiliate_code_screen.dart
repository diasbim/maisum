import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/affiliate_repository.dart';
import '../domain/affiliate_code.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../providers/affiliate_providers.dart';
import 'widgets/affiliate_widgets.dart';

/// The terms of one affiliate's code.
///
/// Everything here can be changed without minting a new code, which matters:
/// the code is already printed on someone's phone and shared with their
/// contacts, so changing what it is worth must not change what it is called.
class AffiliateCodeScreen extends ConsumerStatefulWidget {
  const AffiliateCodeScreen({super.key, required this.affiliateId});

  final String affiliateId;

  @override
  ConsumerState<AffiliateCodeScreen> createState() =>
      _AffiliateCodeScreenState();
}

class _AffiliateCodeScreenState extends ConsumerState<AffiliateCodeScreen> {
  final _valueCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();

  ReferralBenefitType? _benefitType;
  bool? _firstVisitOnly;
  DateTime? _expiresAt;
  String? _loadedCodeId;
  bool _busy = false;

  @override
  void dispose() {
    _valueCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  /// Seeds the form from the server's copy, once per code.
  ///
  /// Re-seeding on every rebuild would wipe what the owner is typing the moment
  /// a background refresh lands, so the guard is the code id rather than a
  /// one-shot flag: a different code really does need new values.
  void _seed(MerchantAffiliateCode code) {
    if (_loadedCodeId == code.id) return;
    _loadedCodeId = code.id;
    _benefitType = code.benefitType;
    _firstVisitOnly = code.firstVisitOnly;
    _expiresAt = code.expiresAt;
    _valueCtrl.text = code.benefitValue == code.benefitValue.roundToDouble()
        ? code.benefitValue.round().toString()
        : code.benefitValue.toString();
    _limitCtrl.text = code.usageLimit?.toString() ?? '';
  }

  Future<void> _save(MerchantAffiliateCode code) async {
    if (_busy) return;
    final value = double.tryParse(_valueCtrl.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      AppFeedback.showMessage(
        context,
        message: 'Escreva um valor maior que zero.',
        isError: true,
      );
      return;
    }
    final rawLimit = _limitCtrl.text.trim();
    final limit = rawLimit.isEmpty ? null : int.tryParse(rawLimit);
    if (rawLimit.isNotEmpty && limit == null) {
      AppFeedback.showMessage(
        context,
        message: 'O limite de usos tem de ser um número.',
        isError: true,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(affiliateAdminControllerProvider.notifier).updateCode(
            affiliateId: widget.affiliateId,
            edit: AffiliateCodeEdit(
              codeId: code.id,
              benefitType: (_benefitType ?? code.benefitType).storageValue,
              benefitValue: value,
              // The pair travels together or not at all: the server refuses a
              // lone date with `invalid_dates`.
              startsAt:
                  _expiresAt == null ? null : (code.startsAt ?? DateTime.now()),
              expiresAt: _expiresAt,
              usageLimit: limit,
              clearUsageLimit: limit == null,
              firstVisitOnly: _firstVisitOnly ?? code.firstVisitOnly,
            ),
          );
      if (!mounted) return;
      AppFeedback.showSuccessToast(context, message: 'Código atualizado');
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: AppErrorMapper.describe(error).message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleEnabled(MerchantAffiliateCode code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(affiliateAdminControllerProvider.notifier).setCodeEnabled(
            codeId: code.id,
            enabled: !code.isActive,
            affiliateId: widget.affiliateId,
          );
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: code.isActive ? 'Código desativado' : 'Código ativado',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: AppErrorMapper.describe(error).message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(affiliateDetailProvider(widget.affiliateId));
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull ?? false;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: MaisUmAppBar(
        title: 'Definições do código',
        fallbackLocation: '/affiliates/${widget.affiliateId}',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.formMaxWidth),
            child: AffiliateAsyncView<AffiliateDetailSnapshot>(
              value: detailAsync,
              loadingLabel: 'A carregar código',
              onRetry: () =>
                  ref.invalidate(affiliateDetailProvider(widget.affiliateId)),
              builder: (context, snapshot) {
                final code = snapshot.affiliate.code;
                if (code == null) {
                  return const AffiliateOfflineNotice(
                    message: 'Este afiliado ainda não tem código atribuído.',
                  );
                }
                _seed(code);
                return _buildForm(
                  code: code,
                  isOwner: isOwner,
                  online: online,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm({
    required MerchantAffiliateCode code,
    required bool isOwner,
    required bool online,
  }) {
    final canEdit = isOwner && online && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online) ...[
          const AffiliateOfflineNotice(
            message: 'Sem ligação. As alterações ao código só podem ser '
                'guardadas online.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!isOwner) ...[
          const AffiliateOfflineNotice(
            message: 'Só o responsável do negócio pode alterar o código.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        MaisUmSurface(
          variant: MaisUmSurfaceVariant.muted,
          radius: AppRadius.md,
          padding: const EdgeInsets.all(AppSpacing.md),
          animationDuration: Duration.zero,
          child: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  code.code.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              AffiliateStatusChip(
                label: _availabilityLabel(code),
                icon: _availabilityIcon(code),
                color: _availabilityColor(code),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'Benefício do cliente',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final type in ReferralBenefitType.values)
              ChoiceChip(
                label: Text(_benefitLabel(type)),
                selected: (_benefitType ?? code.benefitType) == type,
                onSelected:
                    canEdit ? (_) => setState(() => _benefitType = type) : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        MaisUmTextField(
          fieldKey: const Key('affiliate-code-value-field'),
          controller: _valueCtrl,
          label: 'Valor do benefício',
          enabled: canEdit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        MaisUmTextField(
          fieldKey: const Key('affiliate-code-limit-field'),
          controller: _limitCtrl,
          label: 'Limite de usos',
          hintText: 'Deixe vazio para não ter limite',
          enabled: canEdit,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: AppSpacing.md),
        _ExpiryField(
          value: _expiresAt,
          enabled: canEdit,
          onChanged: (value) => setState(() => _expiresAt = value),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile.adaptive(
          key: const Key('affiliate-code-first-visit-switch'),
          value: _firstVisitOnly ?? code.firstVisitOnly,
          onChanged: canEdit
              ? (value) => setState(() => _firstVisitOnly = value)
              : null,
          contentPadding: EdgeInsets.zero,
          title: const Text('Só na primeira visita'),
          subtitle: const Text(
            'Desligado, o desconto também se aplica a clientes atuais, mas não '
            'conta como cliente novo nem gera recompensa.',
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        MaisUmButton(
          key: const Key('affiliate-code-save-button'),
          label: 'Guardar alterações',
          isLoading: _busy,
          onPressed: canEdit ? () => _save(code) : null,
          animationDuration: Duration.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        MaisUmButton(
          key: const Key('affiliate-code-toggle-button'),
          label: code.isActive ? 'Desativar código' : 'Ativar código',
          variant: code.isActive
              ? MaisUmButtonVariant.danger
              : MaisUmButtonVariant.outlined,
          foregroundColor: code.isActive ? null : AppColors.primary,
          onPressed: canEdit ? () => _toggleEnabled(code) : null,
          animationDuration: Duration.zero,
        ),
      ],
    );
  }

  static String _benefitLabel(ReferralBenefitType type) => switch (type) {
        ReferralBenefitType.percentage => 'Percentagem',
        ReferralBenefitType.fixedAmount => 'Valor em MT',
        ReferralBenefitType.points => 'Pontos',
      };

  static MerchantAffiliateCodeAvailability _availability(
    MerchantAffiliateCode code,
  ) =>
      code.availabilityAt(DateTime.now());

  static String _availabilityLabel(MerchantAffiliateCode code) =>
      switch (_availability(code)) {
        MerchantAffiliateCodeAvailability.active => 'Ativo',
        MerchantAffiliateCodeAvailability.disabled => 'Desativado',
        MerchantAffiliateCodeAvailability.notStarted => 'Ainda não começou',
        MerchantAffiliateCodeAvailability.expired => 'Expirado',
        MerchantAffiliateCodeAvailability.exhausted => 'Limite atingido',
      };

  static IconData _availabilityIcon(MerchantAffiliateCode code) =>
      switch (_availability(code)) {
        MerchantAffiliateCodeAvailability.active =>
          Icons.check_circle_outline_rounded,
        MerchantAffiliateCodeAvailability.notStarted => Icons.schedule_rounded,
        MerchantAffiliateCodeAvailability.disabled =>
          Icons.pause_circle_outline_rounded,
        MerchantAffiliateCodeAvailability.expired ||
        MerchantAffiliateCodeAvailability.exhausted =>
          Icons.error_outline_rounded,
      };

  static Color _availabilityColor(MerchantAffiliateCode code) =>
      switch (_availability(code)) {
        MerchantAffiliateCodeAvailability.active => AppColors.success,
        MerchantAffiliateCodeAvailability.notStarted => AppColors.warning,
        MerchantAffiliateCodeAvailability.disabled =>
          AppColors.onSurfaceVariant,
        MerchantAffiliateCodeAvailability.expired ||
        MerchantAffiliateCodeAvailability.exhausted =>
          AppColors.error,
      };
}

class _ExpiryField extends StatelessWidget {
  const _ExpiryField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? 'Sem data de fim'
        : PtDateFormat.dayMonthYearTime(value!);
    return Semantics(
      button: true,
      label: 'Validade do código: $label. Tocar para alterar.',
      child: InkWell(
        key: const Key('affiliate-code-expiry-field'),
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppControlSize.button),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.g100),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Validade do código',
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(color: AppColors.onSurface),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) onChanged(picked);
  }
}
