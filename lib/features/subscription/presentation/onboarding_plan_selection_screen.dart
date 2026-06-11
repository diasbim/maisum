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
import '../../auth/presentation/auth_controller.dart';
import '../data/firestore_plan_offers.dart';
import '../domain/plan.dart';
import '../domain/plan_catalog.dart';
import '../domain/subscription_snapshot.dart';

final onboardingPlanOffersProvider =
    FutureProvider.autoDispose<List<PlanOffer>>((ref) async {
  try {
    final firestore = ref.read(firestoreInstanceProvider);
    final offers = await fetchActivePlanOffers(firestore);
    if (offers.isNotEmpty) {
      return offers;
    }

    // Keep onboarding functional if the Firestore catalog is empty.
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
  } catch (e, st) {
    AppErrorReporter.report(e, st, hint: 'onboarding_plan_offers');
    rethrow;
  }
});

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
      canPop: false,
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
            onPressed: () => context.go('/merchant-config'),
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
              onConfirmPlan: (plan) => _confirmSelection(snapshot, plan),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSelection(
    SubscriptionSnapshot snapshot,
    Plan selectedPlan,
  ) async {
    final merchantId = ref.read(activeMerchantIdProvider);

    if (merchantId == null || merchantId.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Nao foi possivel confirmar o plano. Tente novamente.',
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

      await ref
          .read(secureStorageServiceProvider)
          .setOnboardingPlanConfirmed(true);
      await ref.read(subscriptionSnapshotProvider.notifier).refresh();

      if (!mounted) {
        return;
      }

      final destination = await _showNextStepPicker();
      if (destination != null && mounted) {
        context.go(destination);
      }
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'onboarding_plan_confirm');
      if (!mounted) {
        return;
      }
      AppFeedback.showMessage(
        context,
        message: 'Nao foi possivel confirmar o plano. Tente novamente.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
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
                  Text(
                    'Plano confirmado',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Onde pretende continuar?',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: Theme.of(ctx).colorScheme.secondaryContainer,
                    leading: const Icon(Icons.point_of_sale_rounded),
                    title: const Text('Registar primeira venda'),
                    onTap: () => Navigator.of(ctx).pop('/new-sale'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: Theme.of(ctx).colorScheme.surfaceContainerLowest,
                    leading: const Icon(Icons.dashboard_rounded),
                    title: const Text('Ir para dashboard'),
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

class _PlanSelectionBody extends ConsumerWidget {
  const _PlanSelectionBody({
    required this.snapshot,
    required this.planOffers,
    required this.selectedPlan,
    required this.isSubmitting,
    required this.onPlanSelected,
    required this.onConfirmPlan,
  });

  final SubscriptionSnapshot snapshot;
  final List<PlanOffer> planOffers;
  final Plan? selectedPlan;
  final bool isSubmitting;
  final ValueChanged<Plan> onPlanSelected;
  final ValueChanged<Plan> onConfirmPlan;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 80;
    final offerByPlan = <Plan, PlanOffer>{};
    for (final offer in planOffers) {
      offerByPlan.putIfAbsent(offer.plan, () => offer);
    }

    const plans = [Plan.free, Plan.starter, Plan.business];
    final selected = selectedPlan ?? snapshot.plan;
    final activePlan = plans.contains(selected) ? selected : Plan.starter;

    final pricingByPlan = {
      for (final entry in offerByPlan.entries)
        entry.key: _PlanPricingInfo(
          priceCents: entry.value.priceCents,
          billingInterval: entry.value.billingInterval,
          currency: entry.value.currency,
        ),
    };

    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
        children: [
          const _HeroBanner(),
          const SizedBox(height: 24),
          for (final plan in plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _PlanCard(
                plan: plan,
                whatsappMonthlyLimit: offerByPlan[plan]?.whatsappMonthlyLimit ??
                    PlanCatalog.forPlan(plan).whatsappMonthlyLimit,
                pricingInfo: pricingByPlan[plan],
                isSelected: activePlan == plan,
                onTap: isSubmitting
                    ? null
                    : () {
                        onPlanSelected(plan);
                      },
                onPrimaryAction: isSubmitting
                    ? null
                    : () {
                        onPlanSelected(plan);
                        onConfirmPlan(plan);
                      },
              ),
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
    required this.plan,
    required this.whatsappMonthlyLimit,
    required this.pricingInfo,
    required this.isSelected,
    required this.onTap,
    required this.onPrimaryAction,
  });

  final Plan plan;
  final int? whatsappMonthlyLimit;
  final _PlanPricingInfo? pricingInfo;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isStarter = plan == Plan.starter;
    final title = _planTitle(plan);
    final subtitle = whatsappMonthlyLimit == null
        ? 'Mensagens ilimitadas'
        : '${_formatInt(whatsappMonthlyLimit!)} mensagens/mes';
    final benefits = _planBenefits(plan);
    final buttonLabel = _planPrimaryCta(plan);
    final priceLabel = _formatPrice(
      pricingInfo?.priceCents,
      currency: pricingInfo?.currency,
    );
    final hasPrice = pricingInfo?.priceCents != null;
    final billingSuffix = _billingSuffix(pricingInfo?.billingInterval);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: isStarter
                    ? colorScheme.secondaryContainer.withValues(alpha: 0.25)
                    : isSelected
                        ? colorScheme.secondaryContainer.withValues(alpha: 0.14)
                        : colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isStarter
                      ? colorScheme.primary
                      : isSelected
                          ? colorScheme.secondary
                          : colorScheme.outlineVariant,
                  width: isStarter ? 2 : 1,
                ),
              ),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                ),
                            children: [
                              TextSpan(text: '$priceLabel '),
                              TextSpan(
                                text: billingSuffix,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          priceLabel,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  SizedBox(
                    width: double.infinity,
                    child: switch (plan) {
                      Plan.starter => FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            minimumSize: const Size.fromHeight(40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: onPrimaryAction,
                          child: Text(buttonLabel),
                        ),
                      Plan.business => OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                            side: BorderSide(color: colorScheme.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            foregroundColor: colorScheme.primary,
                          ),
                          onPressed: onPrimaryAction,
                          child: Text(buttonLabel),
                        ),
                      _ => TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            foregroundColor: colorScheme.onSurface,
                          ),
                          onPressed: onPrimaryAction,
                          child: Text(buttonLabel),
                        ),
                    },
                  ),
                ],
              ),
            ),
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

class _PlanPricingInfo {
  const _PlanPricingInfo({
    this.priceCents,
    this.billingInterval,
    this.currency,
  });

  final int? priceCents;
  final String? billingInterval;
  final String? currency;
}

String _planTitle(Plan plan) {
  return switch (plan) {
    Plan.free => 'FREE',
    Plan.starter => 'STARTER',
    Plan.business => 'BUSINESS',
    _ => plan.displayName.toUpperCase(),
  };
}

List<_PlanBenefitData> _planBenefits(Plan plan) {
  return switch (plan) {
    Plan.free => const [
        _PlanBenefitData(label: 'WhatsApp automatico'),
      ],
    Plan.starter => const [
        _PlanBenefitData(label: 'Clientes'),
        _PlanBenefitData(label: 'Fidelizacao'),
        _PlanBenefitData(label: 'Recompensas'),
      ],
    Plan.business => const [
        _PlanBenefitData(label: 'Tudo do Starter'),
        _PlanBenefitData(label: 'Campanhas'),
        _PlanBenefitData(label: 'Relatorios'),
      ],
    _ => const [
        _PlanBenefitData(label: 'Recursos premium'),
      ],
  };
}

String _planPrimaryCta(Plan plan) {
  return switch (plan) {
    Plan.free => 'Comecar gratis',
    Plan.starter => 'Escolher Plano',
    Plan.business => 'Falar Connosco',
    _ => 'Selecionar',
  };
}

String _formatPrice(int? priceCents, {String? currency}) {
  if (priceCents == null || priceCents < 0) {
    return 'Preco sob consulta';
  }
  final symbol = (currency?.toUpperCase() ?? 'BRL') == 'BRL'
      ? 'R\$'
      : (currency?.toUpperCase() ?? 'R\$');
  final major = priceCents ~/ 100;
  final minor = (priceCents % 100).abs();
  if (minor == 0) {
    return '$symbol ${_formatInt(major)}';
  }
  return '$symbol ${_formatInt(major)},${minor.toString().padLeft(2, '0')}';
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
