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
import '../../../design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../merchant_onboarding/presentation/controllers/merchant_onboarding_controller.dart';
import '../../subscription/data/firestore_plan_offers.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/domain/plan.dart';
import '../../subscription/domain/plan_catalog.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';

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

const _settingsCardBorder = Color(0xFFECECEC);
const _settingsCardShadows = [
  BoxShadow(
    color: Color(0x0A1C2E50),
    blurRadius: 8,
    offset: Offset(0, 1),
  ),
];
const _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.9',
);
const _buildNumber = String.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: '10',
);

const _paidSettingsFeatures = [
  _PaidSettingsFeature(
    icon: Icons.analytics_outlined,
    iconColor: AppColors.green,
    title: 'Relatorios de vendas',
    subtitle: 'Historico e analise do negocio',
    route: '/sales',
    featureKey: FeatureKeys.analytics,
    requiredPlanLabel: 'Starter ou superior',
  ),
  _PaidSettingsFeature(
    icon: Icons.favorite_border_rounded,
    iconColor: AppColors.primaryDark,
    title: 'Retencao inteligente',
    subtitle: 'Clientes recorrentes e em risco',
    route: '/retention',
    featureKey: FeatureKeys.engageViewRisk,
    requiredPlanLabel: 'Pro ou Business',
  ),
  _PaidSettingsFeature(
    icon: Icons.auto_graph_rounded,
    iconColor: AppColors.primaryDark,
    title: 'MaisUm Engage',
    subtitle: 'Risco, recuperacao e surveys',
    route: '/engage',
    featureKey: FeatureKeys.engageViewRisk,
    requiredPlanLabel: 'Pro ou Business',
  ),
  _PaidSettingsFeature(
    icon: Icons.playlist_add_check_circle_outlined,
    iconColor: AppColors.primaryDark,
    title: 'Recuperacao de clientes',
    subtitle: 'Fila de acoes premium',
    route: '/engage/actions',
    featureKey: FeatureKeys.engageManageRecovery,
    requiredPlanLabel: 'Business',
  ),
  _PaidSettingsFeature(
    icon: Icons.assignment_turned_in_outlined,
    iconColor: AppColors.primaryDark,
    title: 'Relatorios de visitas',
    subtitle: 'Visitas e resultados de recuperacao',
    route: '/engage/visit-report',
    featureKey: FeatureKeys.engageManageVisits,
    requiredPlanLabel: 'Business',
  ),
  _PaidSettingsFeature(
    icon: Icons.insights_outlined,
    iconColor: AppColors.green,
    title: 'Analytics de surveys',
    subtitle: 'Insights de respostas e satisfacao',
    route: '/engage/surveys/analytics',
    featureKey: FeatureKeys.engageManageSurveys,
    requiredPlanLabel: 'Business',
  ),
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull == true;
    final appUserRole = ref.watch(activeAppUserRoleProvider).valueOrNull ??
        AppConstants.appUserRoleOwner;
    final businessLinkCode = ref.watch(businessLinkCodeProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.definicoes)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (session != null) ...[
            _AccountHeader(
              merchantName: session.merchantName,
              role: appUserRole,
              subscriptionStatus: _formatSubscriptionStatus(
                session.subscriptionStatus,
              ),
            ),
            const SizedBox(height: 24),
            const _Section('Conta', topSpacing: 0),
            _SettingsTile(
              icon: Icons.storefront_rounded,
              iconColor: AppColors.amber,
              title: AppStrings.nomeNegocio,
              subtitle: session.merchantName,
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.g300,
                size: 20,
              ),
              onTap: () => context.push(merchantOnboardingStartRoute),
            ),
            _SettingsTile(
              icon: Icons.phone_rounded,
              iconColor: AppColors.amber,
              title: AppStrings.phoneNumber,
              subtitle: session.phone,
            ),
            if (isOwner)
              _SettingsTile(
                icon: Icons.qr_code_rounded,
                iconColor: AppColors.amber,
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
                iconColor: AppColors.amber,
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
              onTap: isOwner ? () => _showPlanPicker(context, ref) : null,
            ),
            if (isOwner)
              _SettingsTile(
                icon: Icons.admin_panel_settings_rounded,
                iconColor: AppColors.green,
                title: AppStrings.subscricaoAdmin,
                subtitle: AppStrings.subscricaoAdminDesc,
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.g300,
                  size: 20,
                ),
                onTap: () => context.push('/subscription-admin'),
              ),
            const _Section('Negocio'),
            if (isOwner)
              _SettingsTile(
                icon: Icons.groups_rounded,
                iconColor: AppColors.amber,
                title: 'Gestao de Staff',
                subtitle: 'Convidar, criar e ativar/desativar membros',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.g300,
                  size: 20,
                ),
                onTap: () => context.push('/staff-management'),
              ),
            _SettingsTile(
              icon: Icons.inventory_2_rounded,
              iconColor: AppColors.amber,
              title: 'Produtos e Servicos',
              subtitle: 'Ordenar, desativar e gerir itens do catalogo',
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.g300,
                size: 20,
              ),
              onTap: () => context.push('/catalog'),
            ),
            _SettingsTile(
              icon: Icons.calendar_month_rounded,
              iconColor: AppColors.amber,
              title: 'Agenda de clientes',
              subtitle: 'Ver agendamentos em lista e abrir cliente',
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.g300,
                size: 20,
              ),
              onTap: () => context.push('/appointments'),
            ),
            const _Section('Premium'),
            ..._paidSettingsFeatures.map(
              (feature) => _SettingsTile(
                icon: feature.icon,
                iconColor: feature.iconColor,
                title: feature.title,
                subtitle:
                    '${feature.subtitle}. Pago: ${feature.requiredPlanLabel}',
                trailing: const _PaidFeatureTrailing(),
                onTap: () => _openPaidFeature(
                  context,
                  ref,
                  feature,
                  isOwner: isOwner,
                ),
              ),
            ),
          ],
          const _Section('Segurança'),
          _SettingsTile(
            icon: Icons.pin_outlined,
            iconColor: AppColors.primary,
            title: 'PIN de acesso',
            subtitle: 'Alterar o PIN de segurança',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () => _showPinVerifySheet(context, ref),
          ),
          _SettingsTile(
            icon: Icons.lock_clock_rounded,
            iconColor: AppColors.primary,
            title: 'Bloquear aplicação',
            subtitle: 'Exigir PIN para continuar',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () {
              ref.read(appLockedProvider.notifier).state = true;
              context.go('/dashboard');
            },
          ),
          const _Section('Support & Diagnostics'),
          _SettingsTile(
            icon: Icons.support_agent_rounded,
            iconColor: AppColors.g500,
            title: 'Support & Diagnostics',
            subtitle: 'IDs, sessao e versao da app',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () => context.push('/settings/support-diagnostics'),
          ),
          const _Section('Sessao'),
          _SettingsTile(
            icon: Icons.logout_rounded,
            iconColor: AppColors.error,
            title: AppStrings.logout,
            titleColor: AppColors.error,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () => _confirmLogout(context, ref),
          ),
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
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          final plans = offerByPlan.keys.toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            builder: (context, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.g300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Escolher novo plano',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Plano atual: ${currentOffer?.displayName ?? PlanCatalog.forPlan(snapshot.plan).displayName}',
                  textAlign: TextAlign.center,
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
                    final selected = snapshot.plan == plan;
                    return MaisUmSurface(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      radius: 14,
                      selected: selected,
                      semanticButton: true,
                      backgroundColor:
                          selected ? AppColors.secondaryLight : AppColors.white,
                      borderColor:
                          selected ? AppColors.secondary : AppColors.g100,
                      shadows: const [],
                      onTap: () => Navigator.of(sheetContext).pop(plan),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(planName),
                                const SizedBox(height: 2),
                                Text(
                                  _formatPlanPrice(
                                    offer?.priceCents,
                                    currency: offer?.currency,
                                  ),
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.green,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
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
          MaisUmButton(
            onPressed: () => Navigator.pop(ctx),
            label: AppStrings.cancelar,
            variant: MaisUmButtonVariant.ghost,
            fullWidth: false,
            height: 40,
          ),
          MaisUmButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            label: AppStrings.logout,
            variant: MaisUmButtonVariant.danger,
            fullWidth: false,
            height: 40,
          ),
        ],
      ),
    );
  }
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

String _diagnosticValue(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 'Indisponivel';
  }
  return normalized;
}

String _buildDiagnosticsText({
  required String? merchantId,
  required String? appUserId,
  required String? deviceId,
  required String appUserRole,
  required DateTime? expiresAt,
}) {
  final expiry = expiresAt == null ? 'Indisponivel' : _formatExpiry(expiresAt);
  return [
    'Merchant ID: ${_diagnosticValue(merchantId)}',
    'App User ID: ${_diagnosticValue(appUserId)}',
    'Device ID: ${_diagnosticValue(deviceId)}',
    'Current Profile: $appUserRole',
    'Session Expiration: $expiry',
    'App Version: $_appVersion',
    'Build Number: $_buildNumber',
  ].join('\n');
}

Future<void> _openPaidFeature(
  BuildContext context,
  WidgetRef ref,
  _PaidSettingsFeature feature, {
  required bool isOwner,
}) async {
  try {
    final decision = await ref.read(featureGateProvider).check(
          featureKey: feature.featureKey,
        );
    if (!context.mounted) return;

    if (decision.allowed) {
      context.push(feature.route);
      return;
    }

    context.push(
      featureUpsellLocation(
        featureKey: feature.featureKey,
        featureName: feature.title,
        reason: decision.reason,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    AppFeedback.showMessage(
      context,
      message: 'Nao foi possivel validar o plano. Tente novamente.',
      isError: true,
    );
  }
}

class _PaidSettingsFeature {
  const _PaidSettingsFeature({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.featureKey,
    required this.requiredPlanLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String route;
  final String featureKey;
  final String requiredPlanLabel;
}

class SupportDiagnosticsScreen extends ConsumerWidget {
  const SupportDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final appUserRole = ref.watch(activeAppUserRoleProvider).valueOrNull ??
        AppConstants.appUserRoleOwner;
    final diagnosticsText = _buildDiagnosticsText(
      merchantId: session?.resolvedMerchantId,
      appUserId: session?.resolvedAppUserId,
      deviceId: session?.deviceId,
      appUserRole: appUserRole,
      expiresAt: session?.expiresAt,
    );

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('Support & Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const _Section('Identificadores', topSpacing: 0),
          _SettingsTile(
            icon: Icons.badge_outlined,
            iconColor: AppColors.g500,
            title: AppStrings.merchantId,
            subtitle: _diagnosticValue(session?.resolvedMerchantId),
          ),
          _SettingsTile(
            icon: Icons.person_outline_rounded,
            iconColor: AppColors.g500,
            title: AppStrings.appUserId,
            subtitle: _diagnosticValue(session?.resolvedAppUserId),
          ),
          _SettingsTile(
            icon: Icons.phone_android_rounded,
            iconColor: AppColors.g500,
            title: AppStrings.deviceId,
            subtitle: _diagnosticValue(session?.deviceId),
          ),
          _SettingsTile(
            icon: Icons.security_rounded,
            iconColor: AppColors.g500,
            title: 'Perfil atual',
            subtitle: appUserRole,
          ),
          _SettingsTile(
            icon: Icons.schedule_rounded,
            iconColor: AppColors.g500,
            title: AppStrings.sessaoValidaAte,
            subtitle: session == null
                ? _diagnosticValue(null)
                : _formatExpiry(session.expiresAt),
          ),
          const _Section('Aplicacao'),
          const _SettingsTile(
            icon: Icons.verified_rounded,
            iconColor: AppColors.g500,
            title: 'App Version',
            subtitle: _appVersion,
          ),
          const _SettingsTile(
            icon: Icons.numbers_rounded,
            iconColor: AppColors.g500,
            title: 'Build Number',
            subtitle: _buildNumber,
          ),
          _SettingsTile(
            icon: Icons.content_copy_rounded,
            iconColor: AppColors.g500,
            title: 'Copy Diagnostics',
            subtitle: 'Copiar informacao tecnica',
            trailing: const Icon(
              Icons.content_copy_rounded,
              color: AppColors.g300,
              size: 18,
            ),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: diagnosticsText));
              if (!context.mounted) return;
              AppFeedback.showMessage(
                context,
                message: 'Diagnostico copiado.',
              );
            },
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
  const _Section(this.title, {this.topSpacing = 28});

  final String title;
  final double topSpacing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(4, topSpacing, 4, 10),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
              ),
        ),
      );
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.merchantName,
    required this.role,
    required this.subscriptionStatus,
  });

  final String merchantName;
  final String role;
  final String subscriptionStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MaisUmSurface(
      padding: const EdgeInsets.all(16),
      radius: 20,
      backgroundColor: AppColors.white,
      borderColor: _settingsCardBorder,
      borderWidth: 1,
      shadows: _settingsCardShadows,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const BrandMark(size: 28, padding: EdgeInsets.all(10)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _HeaderPill(label: role),
                    _HeaderPill(
                      label: subscriptionStatus,
                      color: AppColors.green,
                      backgroundColor: AppColors.greenLight,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.label,
    this.color = AppColors.primary,
    this.backgroundColor = AppColors.surfaceContainerLow,
  });

  final String label;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
        ),
      );
}

class _PaidFeatureTrailing extends StatelessWidget {
  const _PaidFeatureTrailing();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'PAGO',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.secondaryDark,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.g300,
            size: 20,
          ),
        ],
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
    this.titleColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

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
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 16,
                  height: 1.1,
                  color: titleColor ?? AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.2,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );

    return MaisUmSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      radius: 20,
      height: 74,
      onTap: onTap,
      semanticButton: onTap != null,
      backgroundColor: AppColors.white,
      borderColor: _settingsCardBorder,
      borderWidth: 1,
      shadows: _settingsCardShadows,
      child: content,
    );
  }
}
