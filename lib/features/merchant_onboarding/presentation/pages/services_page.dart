import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/components/maisum_text_field.dart';
import '../../../business_profile/domain/business_profile.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key, this.returnRoute});

  final String? returnRoute;

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
    final backRoute =
        widget.returnRoute ?? MerchantOnboardingStep.services.previousRoute;
    return asyncState.when(
      loading: () => OnboardingStatusScaffold(
        step: MerchantOnboardingStep.services,
        title: 'Produtos e serviços',
        onBack: () => context.go(backRoute),
      ),
      error: (_, __) => OnboardingStatusScaffold(
        step: MerchantOnboardingStep.services,
        title: 'Produtos e serviços',
        errorMessage: 'Não foi possível carregar os serviços.',
        onBack: () => context.go(backRoute),
        onRetry: () => ref.invalidate(merchantOnboardingControllerProvider),
      ),
      data: (state) {
        final profile = BusinessProfiles.resolve(state.draft.businessType);
        final suggestions =
            state.config.suggestionsForBusinessType(state.draft.businessType);
        final itemLabel =
            profile.capabilities.products && !profile.capabilities.services
                ? 'produto'
                : profile.capabilities.products && profile.capabilities.services
                    ? 'produto ou serviço'
                    : 'serviço';

        return OnboardingScaffold(
          step: MerchantOnboardingStep.services,
          title: profile.capabilities.products && profile.capabilities.services
              ? 'Produtos e serviços'
              : profile.capabilities.products
                  ? 'Produtos vendidos'
                  : 'Serviços oferecidos',
          subtitle: 'Adicione agora ou configure o catálogo mais tarde.',
          onBack: () => context.go(backRoute),
          errorMessage: state.errorMessage,
          primaryLabel: 'Guardar e continuar',
          onPrimaryPressed: _continue,
          secondaryLabel: 'Configurar depois',
          onSecondaryPressed: _continue,
          children: [
            MaisUmTextField(
              controller: _searchController,
              label: 'Pesquisar ou adicionar $itemLabel',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Adicionar serviço',
                onPressed: () => _addCustom(state, profile),
              ),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              useFloatingLabel: true,
              onFieldSubmitted: (_) => _addCustom(state, profile),
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

  Future<void> _continue() async {
    final moved = await ref
        .read(merchantOnboardingControllerProvider.notifier)
        .continueFromStep(MerchantOnboardingStep.services);
    if (moved && mounted) {
      context.go(widget.returnRoute ?? MerchantOnboardingStep.review.route);
    }
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

  void _addCustom(
    MerchantOnboardingState state,
    BusinessProfile profile,
  ) {
    final name = _searchController.text.trim();
    if (name.isEmpty) return;
    final service = MerchantService(
      id: 'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
      name: name,
      itemKind: profile.capabilities.products && !profile.capabilities.services
          ? BusinessItemKind.product
          : BusinessItemKind.service,
      isCustom: true,
    );
    _searchController.clear();
    _toggle(state, service);
  }
}
