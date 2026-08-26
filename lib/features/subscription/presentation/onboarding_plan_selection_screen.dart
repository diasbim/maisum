import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/error_state.dart';
import '../../../design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../merchant_onboarding/presentation/controllers/merchant_onboarding_controller.dart';
import '../data/firestore_plan_offers.dart';
import '../domain/plan.dart';
import '../domain/plan_catalog.dart';
import '../domain/subscription_snapshot.dart';
import '../services/remote_config_reader.dart';
import 'feature_upsell_screen.dart';

final onboardingPlanOffersProvider =
    FutureProvider.autoDispose<List<PlanOffer>>((ref) async {
  try {
    final firestore = ref.read(firestoreInstanceProvider);
    final reader = ref.read(remoteConfigReaderProvider);
    return resolveOnboardingPlanOffers(
      fetchActiveOffers: () => fetchActivePlanOffers(firestore),
      getPricingOverride: reader.getPricingOverride,
    );
  } catch (e, st) {
    AppErrorReporter.report(e, st, hint: 'onboarding_plan_offers');
    rethrow;
  }
});

Future<List<PlanOffer>> resolveOnboardingPlanOffers({
  required Future<List<PlanOffer>> Function() fetchActiveOffers,
  required Future<PricingOverride?> Function(String planCode)
      getPricingOverride,
}) async {
  final offers = await fetchActiveOffers();
  if (offers.isNotEmpty) {
    return offers;
  }
  return buildOnboardingFallbackPlanOffers(
    getPricingOverride: getPricingOverride,
  );
}

Future<List<PlanOffer>> buildOnboardingFallbackPlanOffers({
  required Future<PricingOverride?> Function(String planCode)
      getPricingOverride,
}) async {
  final fallbackPlans = Plan.values.where((plan) => plan != Plan.growth);
  return Future.wait(
    fallbackPlans.map((plan) async {
      final override = await getPricingOverride(plan.code);
      final definition = PlanCatalog.forPlan(plan);
      final currency = override?.currency;
      final hasInvalidConfiguredCurrency = currency != null &&
          currency.trim().isNotEmpty &&
          !isValidPlanOfferCurrency(currency);
      return PlanOffer(
        plan: plan,
        code: plan.code,
        displayName: definition.displayName,
        priceCents: hasInvalidConfiguredCurrency
            ? null
            : override?.priceCents ?? (plan == Plan.free ? 0 : null),
        currency: isValidPlanOfferCurrency(currency)
            ? currency!.trim().toUpperCase()
            : 'MZN',
        billingInterval: override?.billingInterval ?? 'monthly',
        features: definition.features,
        whatsappMonthlyLimit: definition.whatsappMonthlyLimit,
        sortOrder: 999,
      );
    }),
  );
}

class OnboardingPlanSelectionScreen extends ConsumerStatefulWidget {
  const OnboardingPlanSelectionScreen({super.key});

  @override
  ConsumerState<OnboardingPlanSelectionScreen> createState() =>
      _OnboardingPlanSelectionScreenState();
}

class _OnboardingPlanSelectionScreenState
    extends ConsumerState<OnboardingPlanSelectionScreen> {
  Plan? _selectedPlan;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(subscriptionSnapshotProvider);
    final planOffersAsync = ref.watch(onboardingPlanOffersProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.go(merchantOnboardingStartRoute);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: AppColors.primaryDarker,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.go(merchantOnboardingStartRoute),
          ),
          title: const Text(
            'Escolha o seu plano',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: snapshotAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: colorScheme.secondary),
          ),
          error: (error, _) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(subscriptionSnapshotProvider),
          ),
          data: (snapshot) => planOffersAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: colorScheme.secondary),
            ),
            error: (error, _) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(onboardingPlanOffersProvider),
            ),
            data: (planOffers) => _PlanSelectionBody(
              snapshot: snapshot,
              planOffers: planOffers,
              selectedPlan: _selectedPlan,
              isSubmitting: _isSubmitting,
              onPlanSelected: (plan) => setState(() {
                _selectedPlan = plan;
              }),
              onConfirmPlan: (offer) => _confirmSelection(snapshot, offer),
              onOfferContact: _openPlanContact,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSelection(
    SubscriptionSnapshot snapshot,
    PlanOffer selectedOffer,
  ) async {
    if (!canConfirmOnboardingPlanOffer(selectedOffer)) {
      _openPlanContact(selectedOffer);
      return;
    }

    final selectedPlan = selectedOffer.plan;
    final merchantId = ref.read(activeMerchantIdProvider);

    if (merchantId == null || merchantId.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Não foi possível confirmar o plano. Tente novamente.',
        isError: true,
      );
      return;
    }

    if (_isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final session = ref.read(authControllerProvider).valueOrNull;
      if (selectedPlan != snapshot.plan) {
        await ref.read(subscriptionRepositoryProvider).switchPlan(
              merchantId: merchantId,
              plan: selectedPlan,
              status: snapshot.state?.status ?? session?.subscriptionStatus,
            );
      }

      await ref.read(analyticsServiceProvider).record(
        eventType: 'plan_selected',
        source: 'onboarding_plan',
        properties: {'plan': selectedPlan.code},
      );

      await ref.read(secureStorageServiceProvider).setOnboardingPlanConfirmed(
            true,
            merchantId: merchantId,
            role: await ref.read(secureStorageServiceProvider).getAppUserRole(),
          );
      await ref.read(subscriptionSnapshotProvider.notifier).refresh();

      if (!mounted) {
        return;
      }

      final destination = await _showNextStepPicker();
      if (mounted) {
        context.go(destination ?? '/dashboard');
      }
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'onboarding_plan_confirm');
      if (!mounted) {
        return;
      }
      AppFeedback.showMessage(
        context,
        message: 'Não foi possível confirmar o plano. Tente novamente.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _openPlanContact(PlanOffer offer) {
    context.push(
      featureUpsellLocation(
        featureKey: '${offer.code}_plan',
        featureName: 'Plano ${offer.displayName}',
        reason: 'plan_pricing',
      ),
    );
  }

  Future<String?> _showNextStepPicker() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final bottomInset = media.padding.bottom + media.viewInsets.bottom;

        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Plano confirmado',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Onde pretende continuar?',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  _NextStepOption(
                    icon: Icons.groups_rounded,
                    label: 'Convidar a equipa agora',
                    highlighted: true,
                    onTap: () => Navigator.of(ctx).pop('/staff-management'),
                  ),
                  const SizedBox(height: 8),
                  _NextStepOption(
                    icon: Icons.point_of_sale_rounded,
                    label: 'Registar primeira venda',
                    onTap: () => Navigator.of(ctx).pop('/new-sale'),
                  ),
                  const SizedBox(height: 8),
                  _NextStepOption(
                    icon: Icons.dashboard_rounded,
                    label: 'Ir para o painel',
                    onTap: () => Navigator.of(ctx).pop('/dashboard'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NextStepOption extends StatelessWidget {
  const _NextStepOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MaisUmSurface(
      onTap: onTap,
      semanticButton: true,
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      backgroundColor: highlighted
          ? colorScheme.secondaryContainer
          : colorScheme.surfaceContainerLowest,
      borderColor: highlighted
          ? colorScheme.secondary.withValues(alpha: 0.3)
          : colorScheme.outlineVariant,
      shadows: const [],
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSelectionBody extends ConsumerWidget {
  const _PlanSelectionBody({
    required this.snapshot,
    required this.planOffers,
    required this.selectedPlan,
    required this.isSubmitting,
    required this.onPlanSelected,
    required this.onConfirmPlan,
    required this.onOfferContact,
  });

  final SubscriptionSnapshot snapshot;
  final List<PlanOffer> planOffers;
  final Plan? selectedPlan;
  final bool isSubmitting;
  final ValueChanged<Plan> onPlanSelected;
  final ValueChanged<PlanOffer> onConfirmPlan;
  final ValueChanged<PlanOffer> onOfferContact;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 80;
    final offerByPlan = <Plan, PlanOffer>{};
    for (final offer in planOffers) {
      if (isValidPlanOfferCurrency(offer.currency)) {
        offerByPlan.putIfAbsent(offer.plan, () => offer);
      }
    }
    final offers = offerByPlan.values.toList();
    final selected = selectedPlan ?? snapshot.plan;
    final activeOffer =
        offerByPlan[selected] ?? (offers.isEmpty ? null : offers.first);

    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
        children: [
          const _HeroBanner(),
          const SizedBox(height: 24),
          for (final offer in offers)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _PlanCard(
                offer: offer,
                isSelected: activeOffer?.plan == offer.plan,
                onTap: isSubmitting
                    ? null
                    : () {
                        onPlanSelected(offer.plan);
                      },
                onPrimaryAction: isSubmitting
                    ? null
                    : () {
                        if (!canConfirmOnboardingPlanOffer(offer)) {
                          onOfferContact(offer);
                        } else {
                          onPlanSelected(offer.plan);
                        }
                      },
              ),
            ),
          if (activeOffer != null)
            _PlanSelectionFooter(
              offer: activeOffer,
              isSubmitting: isSubmitting,
              onConfirm: canConfirmOnboardingPlanOffer(activeOffer)
                  ? () => onConfirmPlan(activeOffer)
                  : () => onOfferContact(activeOffer),
            ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escolha o seu plano',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Comece gratuitamente.\nE evolua quando precisar.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onPrimary.withValues(alpha: 0.9),
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.offer,
    required this.isSelected,
    required this.onTap,
    required this.onPrimaryAction,
  });

  final PlanOffer offer;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plan = offer.plan;
    final isStarter = plan == Plan.starter;
    final title = offer.displayName.toUpperCase();
    final subtitle = offer.whatsappMonthlyLimit == null
        ? 'Mensagens ilimitadas'
        : '${_formatInt(offer.whatsappMonthlyLimit!)} mensagens/mes';
    final benefits = _planBenefits(plan);
    final requiresContact = !canConfirmOnboardingPlanOffer(offer);
    final buttonLabel =
        requiresContact ? 'Falar Connosco' : _planPrimaryCta(plan);
    final hasTrustworthyPrice = hasTrustworthyOnboardingOfferPrice(offer);
    final priceLabel = hasTrustworthyPrice
        ? _formatPrice(
            offer.priceCents,
            currency: offer.currency,
          )
        : 'Preço sob consulta';
    final hasPrice = hasTrustworthyPrice;
    final billingSuffix = _billingSuffix(offer.billingInterval);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        MaisUmSurface(
          onTap: onTap,
          semanticButton: true,
          selected: isSelected,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          radius: 14,
          backgroundColor: isStarter
              ? colorScheme.secondaryContainer.withValues(alpha: 0.25)
              : isSelected
                  ? colorScheme.secondaryContainer.withValues(alpha: 0.14)
                  : colorScheme.surfaceContainerLowest,
          borderColor: isStarter
              ? colorScheme.primary
              : isSelected
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
          borderWidth: isStarter ? 2 : 1,
          shadows: const [],
          animationDuration: const Duration(milliseconds: 200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      key: ValueKey('plan_selected_${plan.name}'),
                      size: 16,
                      color: colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              hasPrice
                  ? RichText(
                      text: TextSpan(
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                ),
                        children: [
                          TextSpan(text: '$priceLabel '),
                          TextSpan(
                            text: billingSuffix,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      priceLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
              const SizedBox(height: 10),
              for (final benefit in benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _BenefitRow(benefit: benefit),
                ),
              const SizedBox(height: 8),
              if (requiresContact)
                MaisUmButton(
                  label: buttonLabel,
                  onPressed: onPrimaryAction,
                  variant: MaisUmButtonVariant.outlined,
                  foregroundColor: colorScheme.primary,
                  height: 40,
                  radius: 8,
                )
              else
                switch (plan) {
                  Plan.starter => MaisUmButton(
                      label: buttonLabel,
                      onPressed: onPrimaryAction,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      height: 40,
                      radius: 8,
                    ),
                  Plan.business => MaisUmButton(
                      label: buttonLabel,
                      onPressed: onPrimaryAction,
                      variant: MaisUmButtonVariant.outlined,
                      foregroundColor: colorScheme.primary,
                      height: 40,
                      radius: 8,
                    ),
                  _ => MaisUmButton(
                      label: buttonLabel,
                      onPressed: onPrimaryAction,
                      variant: MaisUmButtonVariant.ghost,
                      foregroundColor: colorScheme.onSurface,
                      height: 40,
                      radius: 8,
                    ),
                },
            ],
          ),
        ),
        if (isStarter)
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                key: const ValueKey('plan_badge_starter'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Mais Popular',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit});

  final _PlanBenefitData benefit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = colorScheme.surfaceContainerHighest;
    final fgColor = colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 12, color: fgColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              benefit.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanBenefitData {
  const _PlanBenefitData({
    required this.label,
  });

  final String label;
}

class _PlanSelectionFooter extends StatelessWidget {
  const _PlanSelectionFooter({
    required this.offer,
    required this.isSubmitting,
    required this.onConfirm,
  });

  final PlanOffer offer;
  final bool isSubmitting;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final requiresContact = !canConfirmOnboardingPlanOffer(offer);
    return MaisUmSurface(
      semanticButton: false,
      padding: const EdgeInsets.all(14),
      backgroundColor: Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withValues(alpha: 0.3),
      borderColor: Theme.of(context).colorScheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            requiresContact
                ? 'Fale connosco sobre o plano ${offer.displayName}'
                : 'Plano ${offer.displayName} selecionado',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          MaisUmButton(
            label: requiresContact ? 'Falar Connosco' : 'Confirmar plano',
            loadingLabel: 'A confirmar...',
            isLoading: isSubmitting,
            onPressed: onConfirm,
            variant: requiresContact
                ? MaisUmButtonVariant.outlined
                : MaisUmButtonVariant.primary,
          ),
        ],
      ),
    );
  }
}

List<_PlanBenefitData> _planBenefits(Plan plan) {
  return switch (plan) {
    Plan.free => const [
        _PlanBenefitData(label: 'WhatsApp automático'),
      ],
    Plan.starter => const [
        _PlanBenefitData(label: 'Clientes'),
        _PlanBenefitData(label: 'Fidelização'),
        _PlanBenefitData(label: 'Recompensas'),
      ],
    Plan.business => const [
        _PlanBenefitData(label: 'Tudo do Starter'),
        _PlanBenefitData(label: 'Campanhas'),
        _PlanBenefitData(label: 'Relatórios'),
      ],
    _ => const [
        _PlanBenefitData(label: 'Recursos premium'),
      ],
  };
}

String _planPrimaryCta(Plan plan) {
  return switch (plan) {
    Plan.free => 'Começar grátis',
    Plan.starter => 'Escolher Plano',
    Plan.business => 'Falar Connosco',
    _ => 'Selecionar',
  };
}

String _formatPrice(int? priceCents, {String? currency}) {
  if (priceCents == null || priceCents < 0) {
    return 'Preço sob consulta';
  }
  final currencyCode = isValidPlanOfferCurrency(currency)
      ? currency!.trim().toUpperCase()
      : 'MZN';
  final major = priceCents ~/ 100;
  final minor = (priceCents % 100).abs();
  if (minor == 0) {
    return '$currencyCode ${_formatInt(major)}';
  }
  return '$currencyCode ${_formatInt(major)},${minor.toString().padLeft(2, '0')}';
}

bool canConfirmOnboardingPlanOffer(PlanOffer offer) {
  if (offer.plan == Plan.business) {
    return false;
  }
  return hasTrustworthyOnboardingOfferPrice(offer) &&
      _hasSupportedBillingInterval(offer.billingInterval);
}

bool hasTrustworthyOnboardingOfferPrice(PlanOffer offer) {
  if (offer.priceCents == null || offer.priceCents! < 0) {
    return false;
  }
  if (!isValidPlanOfferCurrency(offer.currency)) {
    return false;
  }
  return offer.plan == Plan.free || offer.priceCents! > 0;
}

bool _hasSupportedBillingInterval(String? billingInterval) {
  final value = billingInterval?.trim().toLowerCase();
  return value != null &&
      value.isNotEmpty &&
      (value.contains('month') ||
          value.contains('mens') ||
          value.contains('year') ||
          value.contains('anual'));
}

String _billingSuffix(String? billingInterval) {
  final value = billingInterval?.trim().toLowerCase();
  if (value == null || value.isEmpty) {
    return '/mes';
  }
  if (value.contains('month') || value.contains('mens')) {
    return '/mes';
  }
  if (value.contains('year') || value.contains('an')) {
    return '/ano';
  }
  return '/$value';
}

String _formatInt(int value) {
  final chars = value.toString().split('');
  final buffer = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    buffer.write(chars[i]);
    final remaining = chars.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) {
      buffer.write('.');
    }
  }
  return buffer.toString();
}
