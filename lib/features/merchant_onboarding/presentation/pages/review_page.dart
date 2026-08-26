import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_layout.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);
    return asyncState.when(
      loading: () => OnboardingStatusScaffold(
        step: MerchantOnboardingStep.review,
        title: 'Confirme os dados',
        onBack: () => context.go(MerchantOnboardingStep.services.route),
      ),
      error: (_, __) => OnboardingStatusScaffold(
        step: MerchantOnboardingStep.review,
        title: 'Confirme os dados',
        errorMessage: 'Não foi possível carregar a revisão.',
        onBack: () => context.go(MerchantOnboardingStep.services.route),
        onRetry: () => ref.invalidate(merchantOnboardingControllerProvider),
      ),
      data: (state) => OnboardingScaffold(
        step: MerchantOnboardingStep.review,
        title: 'Confirme os dados',
        subtitle: 'Revise antes de criar a conta.',
        onBack: () => context.go(MerchantOnboardingStep.services.route),
        errorMessage: state.errorMessage,
        primaryLabel: 'Criar conta',
        isLoading: state.isSaving,
        onPrimaryPressed: () async {
          try {
            await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .createMerchant();
            if (!context.mounted) return;
            context.go('/onboarding-plan');
            AppFeedback.showSuccessToast(
              context,
              message: 'Conta criada no MaisUm',
              subtitle: 'O seu negócio já está online.',
            );
          } catch (_) {
            // Controller exposes the friendly inline error.
          }
        },
        children: [
          ReviewCard(
            title: 'Tipo de negócio',
            icon: Icons.category_outlined,
            onEdit: () => context.go(
              merchantOnboardingStepLocation(
                MerchantOnboardingStep.businessType,
                returnTo: MerchantOnboardingStep.review.route,
              ),
            ),
            child: Text(_businessTypeLabel(state) ?? 'Não selecionado'),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Negócio',
            icon: Icons.storefront_rounded,
            onEdit: () => context.go(
              merchantOnboardingStepLocation(
                MerchantOnboardingStep.businessInfo,
                returnTo: MerchantOnboardingStep.review.route,
              ),
            ),
            child: Text(
              [
                state.draft.businessName,
                [state.draft.city, state.draft.district]
                    .whereType<String>()
                    .where((value) => value.trim().isNotEmpty)
                    .join(' · '),
              ].whereType<String>().join('\n'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Endereço',
            icon: Icons.location_on_rounded,
            onEdit: () => context.go(
              merchantOnboardingStepLocation(
                MerchantOnboardingStep.location,
                returnTo: MerchantOnboardingStep.review.route,
              ),
            ),
            child: Text(_locationSummary(state.draft)),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Horários',
            icon: Icons.schedule_rounded,
            onEdit: () => context.go(
              merchantOnboardingStepLocation(
                MerchantOnboardingStep.workingHours,
                returnTo: MerchantOnboardingStep.review.route,
              ),
            ),
            child: Text(
              state.draft.workingHours.isEmpty
                  ? 'Configurar depois'
                  : '${state.draft.workingHours.values.where((hours) => hours.isOpen).length} dias abertos',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Serviços',
            icon: Icons.design_services_rounded,
            onEdit: () => context.go(
              merchantOnboardingStepLocation(
                MerchantOnboardingStep.services,
                returnTo: MerchantOnboardingStep.review.route,
              ),
            ),
            child: Text(
              state.draft.services.isEmpty
                  ? 'Adicionar depois'
                  : state.draft.services
                      .map((service) => service.name)
                      .join(', '),
            ),
          ),
        ],
      ),
    );
  }

  String? _businessTypeLabel(MerchantOnboardingState state) {
    final selectedId = state.draft.businessType;
    for (final type in state.config.businessTypes) {
      if (type.id == selectedId) return type.label;
    }
    return selectedId;
  }

  String _locationSummary(MerchantDraft draft) {
    final details = [
      draft.address?.trim(),
      draft.reference?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    return details.isEmpty ? 'Adicionar depois' : details.join('\n');
  }
}
