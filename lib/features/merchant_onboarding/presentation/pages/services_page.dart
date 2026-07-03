import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/components/maisum_text_field.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);
    return asyncState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: ErrorCard(message: 'Nao foi possivel carregar os servicos.')),
      data: (state) {
        final suggestions = state.config.serviceSuggestions;

        return OnboardingScaffold(
          step: MerchantOnboardingStep.services,
          title: 'Serviços oferecidos',
          subtitle: 'Selecione pelo menos um serviço.',
          errorMessage: state.errorMessage,
          primaryLabel: 'Continuar',
          onPrimaryPressed: () async {
            final moved = await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .continueFromStep(MerchantOnboardingStep.services);
            if (moved && context.mounted) {
              context.go(MerchantOnboardingStep.review.route);
            }
          },
          children: [
            MaisUmTextField(
              controller: _searchController,
              label: 'Pesquisar servicos',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Adicionar servico',
                onPressed: () => _addCustom(state),
              ),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              useFloatingLabel: true,
              onFieldSubmitted: (_) => _addCustom(state),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionTitle('Sugestões'),
            if (suggestions.isEmpty)
              const ErrorCard(
                message:
                    'Sugestões indisponíveis. Adicione um serviço manualmente.',
              )
            else
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final service in suggestions)
                    FilterChip(
                      label: Text(service.name),
                      selected: state.draft.services
                          .any((item) => item.id == service.id),
                      onSelected: (_) => _toggle(state, service),
                      avatar: const Icon(Icons.add_rounded, size: 18),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                    child: SectionTitle(
                        'Selecionados (${state.draft.services.length})')),
                TextButton(
                  onPressed: () => ref
                      .read(merchantOnboardingControllerProvider.notifier)
                      .updateServices(const []),
                  child: const Text('Limpar tudo'),
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final service in state.draft.services)
                  Chip(
                    backgroundColor: AppColors.secondaryLight,
                    label: Text(service.name),
                    deleteIcon: const Icon(Icons.close_rounded),
                    onDeleted: () => _toggle(state, service),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _toggle(MerchantOnboardingState state, MerchantService service) {
    final exists = state.draft.services.any((item) => item.id == service.id);
    final next = exists
        ? state.draft.services.where((item) => item.id != service.id).toList()
        : [...state.draft.services, service];
    ref
        .read(merchantOnboardingControllerProvider.notifier)
        .updateServices(next);
  }

  void _addCustom(MerchantOnboardingState state) {
    final name = _searchController.text.trim();
    if (name.isEmpty) return;
    final service = MerchantService(
      id: 'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
      name: name,
      isCustom: true,
    );
    _searchController.clear();
    _toggle(state, service);
  }
}
