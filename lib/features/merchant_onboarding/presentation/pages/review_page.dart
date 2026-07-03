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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: ErrorCard(message: 'Nao foi possivel carregar a revisao.')),
      data: (state) => OnboardingScaffold(
        step: MerchantOnboardingStep.review,
        title: 'Confirme os dados',
        subtitle: 'Revise antes de criar a conta.',
        errorMessage: state.errorMessage,
        primaryLabel: 'Criar conta',
        isLoading: state.isSaving,
        onPrimaryPressed: () async {
          try {
            await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .createMerchant();
            if (!context.mounted) return;
            context.go('/dashboard');
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
            title: 'Negocio',
            icon: Icons.storefront_rounded,
            onEdit: () => context.go(MerchantOnboardingStep.businessInfo.route),
            child: Text(
                '${state.draft.businessName ?? '-'}\n${state.draft.city ?? '-'}'),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Localizacao',
            icon: Icons.location_on_rounded,
            onEdit: () => context.go(MerchantOnboardingStep.location.route),
            child: Text(state.draft.address ?? '-'),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Horarios',
            icon: Icons.schedule_rounded,
            onEdit: () => context.go(MerchantOnboardingStep.workingHours.route),
            child: Text(
                '${state.draft.workingHours.values.where((hours) => hours.isOpen).length} dias abertos'),
          ),
          const SizedBox(height: AppSpacing.md),
          ReviewCard(
            title: 'Servicos',
            icon: Icons.design_services_rounded,
            onEdit: () => context.go(MerchantOnboardingStep.services.route),
            child: Text(
              state.draft.services.isEmpty
                  ? '-'
                  : state.draft.services
                      .map((service) => service.name)
                      .join(', '),
            ),
          ),
        ],
      ),
    );
  }
}
