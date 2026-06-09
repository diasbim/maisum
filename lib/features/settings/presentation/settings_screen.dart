import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/pin_verification_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/pin_verification_feedback.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../subscription/data/firestore_plan_offers.dart';
import '../../subscription/domain/plan.dart';
import '../../subscription/domain/plan_catalog.dart';

final businessLinkCodeProvider = FutureProvider<String?>((ref) async {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    return null;
  }

  try {
    final doc = await ref
        .read(firestoreInstanceProvider)
        .collection('businesses')
        .doc(session.resolvedMerchantId)
        .get();
    final data = doc.data() ?? <String, dynamic>{};

    final rawCode = (data['link_code'] as String?)?.trim();
    if (rawCode != null && rawCode.isNotEmpty) {
      return rawCode;
    }

    final normalizedCode = (data['link_code_normalized'] as String?)?.trim();
    if (normalizedCode != null && normalizedCode.isNotEmpty) {
      final compact =
          normalizedCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (compact.length == 8) {
        return '${compact.substring(0, 4)}-${compact.substring(4)}';
      }
      return compact;
    }
  } catch (_) {
    return null;
  }

  return null;
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull ?? true;
    final appUserRole = ref.watch(activeAppUserRoleProvider).valueOrNull ??
        AppConstants.appUserRoleOwner;
    final businessLinkCode = ref.watch(businessLinkCodeProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.definicoes)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (session != null) ...[
            const _Section('Conta'),
            _SettingsTile(
              icon: Icons.storefront_rounded,
              iconColor: AppColors.secondary,
              title: AppStrings.nomeNegocio,
              subtitle: session.merchantName,
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.g300,
                size: 20,
              ),
              onTap: () => context.push('/merchant-config'),
            ),
            _SettingsTile(
              icon: Icons.phone_rounded,
              iconColor: AppColors.primary,
              title: AppStrings.phoneNumber,
              subtitle: session.phone,
            ),
            if (isOwner)
              _SettingsTile(
                icon: Icons.groups_rounded,
                iconColor: AppColors.secondary,
                title: 'Gestao de Staff',
                subtitle: 'Convidar, criar e ativar/desativar membros',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.g300,
                  size: 20,
                ),
                onTap: () => context.push('/staff-management'),
              ),
            if (isOwner)
              _SettingsTile(
                icon: Icons.qr_code_rounded,
                iconColor: AppColors.primaryDark,
                title: 'Codigo da barbearia',
                subtitle: businessLinkCode ?? 'A gerar codigo...',
                trailing: const Icon(
                  Icons.content_copy_rounded,
                  color: AppColors.g300,
                  size: 18,
                ),
                onTap: () async {
                  final code = businessLinkCode;
                  if (code == null || code.trim().isEmpty) {
                    AppFeedback.showMessage(
                      context,
                      message: 'Codigo indisponivel neste momento.',
                      isError: true,
                    );
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  AppFeedback.showMessage(
                    context,
                    message: 'Codigo copiado: $code',
                  );
                },
              ),
            if (!isOwner)
              _SettingsTile(
                icon: Icons.link_rounded,
                iconColor: AppColors.primaryDark,
                title: 'Vincular dispositivo',
                subtitle: 'Entrar por codigo da barbearia',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.g300,
                  size: 20,
                ),
                onTap: () => context.push('/link-device'),
              ),
            _SettingsTile(
              icon: Icons.verified_user_rounded,
              iconColor: AppColors.green,
              title: AppStrings.subscricao,
              subtitle: _formatSubscriptionStatus(session.subscriptionStatus),
              trailing: isOwner
                  ? const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.g300,
                      size: 20,
                    )
                  : null,
              onTap: isOwner ? () => context.push('/onboarding-plan') : null,
            ),
            if (isOwner)
              _SettingsTile(
                icon: Icons.admin_panel_settings_rounded,
                iconColor: AppColors.primaryDark,
                title: AppStrings.subscricaoAdmin,
                subtitle: AppStrings.subscricaoAdminDesc,
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.g300,
                  size: 20,
                ),
                onTap: () => context.push('/subscription-admin'),
              ),
            const _Section(AppStrings.identificadores),
            _SettingsTile(
              icon: Icons.badge_outlined,
              iconColor: AppColors.primary,
              title: AppStrings.merchantId,
              subtitle: session.resolvedMerchantId,
            ),
            _SettingsTile(
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.secondary,
              title: AppStrings.appUserId,
              subtitle: session.resolvedAppUserId,
            ),
            _SettingsTile(
              icon: Icons.security_rounded,
              iconColor: AppColors.primaryDark,
              title: 'Perfil',
              subtitle: appUserRole,
            ),
            if (session.deviceId != null && session.deviceId!.isNotEmpty)
              _SettingsTile(
                icon: Icons.phone_android_rounded,
                iconColor: AppColors.primaryDark,
                title: AppStrings.deviceId,
                subtitle: session.deviceId,
              ),
            _SettingsTile(
              icon: Icons.schedule_rounded,
              iconColor: AppColors.g800,
              title: AppStrings.sessaoValidaAte,
              subtitle: _formatExpiry(session.expiresAt),
            ),
          ],

          // ── Security ────────────────────────────────────────────────────────
          const _Section('Segurança'),
          _SettingsTile(
            icon: Icons.pin_outlined,
            iconColor: AppColors.primary,
            title: 'PIN de acesso',
            subtitle: 'Alterar o PIN de segurança',
            brandAccent: true,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () => _showPinVerifySheet(context, ref),
          ),
          _SettingsTile(
            icon: Icons.lock_clock_rounded,
            iconColor: AppColors.secondary,
            title: 'Bloquear agora',
            subtitle: 'Exige PIN para continuar',
            brandAccent: true,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () {
              ref.read(appLockedProvider.notifier).state = true;
              context.pop();
            },
          ),

          const SizedBox(height: 8),
          const _Section('Sessao'),
          Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => _confirmLogout(context, ref),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      AppStrings.logout,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _formatSubscriptionStatus(String status) {
    if (status.trim().isEmpty) {
      return 'Sem estado';
    }
    return status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatExpiry(DateTime expiry) {
    final localExpiry = expiry.toLocal();
    final day = localExpiry.day.toString().padLeft(2, '0');
    final month = localExpiry.month.toString().padLeft(2, '0');
    final year = localExpiry.year.toString();
    final hour = localExpiry.hour.toString().padLeft(2, '0');
    final minute = localExpiry.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<void> _showPlanPicker(BuildContext context, WidgetRef ref) async {
    final merchantId = ref.read(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Sessao invalida.',
        isError: true,
      );
      return;
    }

    try {
      final snapshot = await ref.read(subscriptionSnapshotProvider.future);
      final planOffers = await _loadPlanOffers(ref);
      if (!context.mounted) return;
      if (planOffers.isEmpty) {
        AppFeedback.showMessage(
          context,
          message: 'Nenhum plano disponivel no momento.',
          isError: true,
        );
        return;
      }

      final offerByPlan = <Plan, PlanOffer>{};
      for (final offer in planOffers) {
        offerByPlan.putIfAbsent(offer.plan, () => offer);
      }

      final currentOffer = offerByPlan[snapshot.plan];

      final selectedPlan = await showModalBottomSheet<Plan>(
        context: context,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          final plans = offerByPlan.keys.toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.g300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Escolher novo plano',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Plano atual: ${currentOffer?.displayName ?? PlanCatalog.forPlan(snapshot.plan).displayName}',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              ...plans.map(
                (plan) {
                  final offer = offerByPlan[plan];
                  final planName = offer?.displayName ??
                      PlanCatalog.forPlan(plan).displayName;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(planName),
                    subtitle: Text(_formatPlanPrice(
                      offer?.priceCents,
                      currency: offer?.currency,
                    )),
                    trailing: snapshot.plan == plan
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.green,
                          )
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(plan),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      );

      if (!context.mounted || selectedPlan == null) return;
      if (selectedPlan == snapshot.plan) {
        AppFeedback.showMessage(
          context,
          message: 'Este plano ja esta ativo.',
          isError: false,
        );
        return;
      }

      final session = ref.read(authControllerProvider).valueOrNull;
      final selectedOffer = offerByPlan[selectedPlan];
      await ref.read(subscriptionRepositoryProvider).switchPlan(
            merchantId: merchantId,
            plan: selectedPlan,
            status: snapshot.state?.status ?? session?.subscriptionStatus,
          );
      await ref.read(subscriptionSnapshotProvider.notifier).refresh();

      if (!context.mounted) return;
      AppFeedback.showMessage(
        context,
        message:
            'Plano alterado para ${selectedOffer?.displayName ?? PlanCatalog.forPlan(selectedPlan).displayName}.',
        isError: false,
      );
    } catch (_) {
      if (!context.mounted) return;
      AppFeedback.showMessage(
        context,
        message: 'Nao foi possivel atualizar o plano.',
        isError: true,
      );
    }
  }

  Future<List<PlanOffer>> _loadPlanOffers(WidgetRef ref) async {
    final firestore = ref.read(firestoreInstanceProvider);
    final offers = await fetchActivePlanOffers(firestore);
    if (offers.isNotEmpty) {
      return offers;
    }

    final reader = ref.read(remoteConfigReaderProvider);
    final fallbackPlans = Plan.values.where((plan) => plan != Plan.growth);
    final fallbackEntries = await Future.wait(
      fallbackPlans.map((plan) async {
        final override = await reader.getPricingOverride(plan.code);
        final definition = PlanCatalog.forPlan(plan);
        return PlanOffer(
          plan: plan,
          code: plan.code,
          displayName: definition.displayName,
          priceCents: override?.priceCents,
          currency: (override?.currency ?? 'BRL').toUpperCase(),
          billingInterval: override?.billingInterval ?? 'monthly',
          features: definition.features,
          whatsappMonthlyLimit: definition.whatsappMonthlyLimit,
          sortOrder: 999,
        );
      }),
    );

    return fallbackEntries;
  }

  Future<void> _showPinVerifySheet(BuildContext context, WidgetRef ref) async {
    final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
    if (!context.mounted) return;
    if (!hasPin) {
      context.push('/pin-setup');
      return;
    }
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _PinVerifySheet(storage: ref.read(secureStorageServiceProvider)),
    );
    if (verified == true && context.mounted) {
      context.push('/pin-setup');
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.confirmarLogout),
        content: const Text(AppStrings.confirmarLogoutMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancelar),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text(AppStrings.logout),
          ),
        ],
      ),
    );
  }
}

String _formatPlanPrice(int? priceCents, {String? currency}) {
  if (priceCents == null || priceCents < 0) {
    return 'Preco sob consulta';
  }
  final symbol = (currency?.toUpperCase() ?? 'BRL') == 'BRL'
      ? 'R\$'
      : (currency?.toUpperCase() ?? 'R\$');
  final major = priceCents ~/ 100;
  final minor = (priceCents % 100).abs();
  final majorLabel = major.toString();
  if (minor == 0) {
    return '$symbol $majorLabel';
  }
  return '$symbol $majorLabel,${minor.toString().padLeft(2, '0')}';
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

// ── PIN Verify Sheet ──────────────────────────────────────────────────────────

class _PinVerifySheet extends StatefulWidget {
  const _PinVerifySheet({required this.storage});
  final SecureStorageService storage;

  @override
  State<_PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends State<_PinVerifySheet>
    with SingleTickerProviderStateMixin, PinVerificationShakeMixin {
  String _input = '';
  bool _isError = false;
  bool _isLoading = false;
  int _attempts = 0;

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
    if (_isLoading || _isError || _input.length >= AppConstants.pinLength) {
      return;
    }
    setState(() => _input += d);
    if (_input.length == AppConstants.pinLength) _verify();
  }

  void _handleDelete() {
    if (_isLoading) return;
    setState(() {
      _isError = false;
      if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
    });
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    final result = await PinVerificationService.verifyEphemeralPin(
      storage: widget.storage,
      input: _input,
      currentAttempts: _attempts,
    );
    if (result.isSuccess) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    if (result.status == PinVerificationStatus.unavailable) {
      setState(() => _isLoading = false);
      return;
    }

    if (result.isBlocked) {
      if (mounted) {
        AppFeedback.showMessage(
          context,
          message: AppStrings.pinBlocked,
          isError: true,
        );
        Navigator.of(context).pop(false);
      }
      return;
    }

    setState(() {
      _attempts = result.attempts;
      _isError = true;
      _isLoading = false;
    });
    triggerPinShake();
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _isError = false;
        _input = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.g300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text('Verificar PIN atual', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Introduza o PIN atual para continuar',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          PinVerificationFeedback(
            shakeAnimation: pinShakeAnimation,
            inputLength: _input.length,
            attempts: _attempts,
            isError: _isError,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 24),
          PinPad(onDigit: _handleDigit, onDelete: _handleDelete),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.brandAccent = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool brandAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            if (brandAccent)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.g100),
                  ),
                  child: const BrandMark(size: 10, padding: EdgeInsets.all(3)),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100, width: 1.5),
      ),
      child: onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: content,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: content,
            ),
    );
  }
}
