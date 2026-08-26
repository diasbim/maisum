import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/components/maisum_text_field.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class BusinessLocationPage extends ConsumerStatefulWidget {
  const BusinessLocationPage({super.key, this.returnRoute});

  final String? returnRoute;

  @override
  ConsumerState<BusinessLocationPage> createState() =>
      _BusinessLocationPageState();
}

class _BusinessLocationPageState extends ConsumerState<BusinessLocationPage> {
  late final TextEditingController _addressController;
  late final TextEditingController _referenceController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _referenceController = TextEditingController();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);
    final backRoute =
        widget.returnRoute ?? MerchantOnboardingStep.location.previousRoute;
    return asyncState.when(
      loading: () => OnboardingStatusScaffold(
        step: MerchantOnboardingStep.location,
        title: 'Onde está o seu negócio?',
        onBack: () => context.go(backRoute),
      ),
      error: (_, __) => OnboardingStatusScaffold(
        step: MerchantOnboardingStep.location,
        title: 'Onde está o seu negócio?',
        errorMessage: 'Não foi possível carregar a localização.',
        onBack: () => context.go(backRoute),
        onRetry: () => ref.invalidate(merchantOnboardingControllerProvider),
      ),
      data: (state) {
        _syncController(_addressController, state.draft.address ?? '');
        _syncController(_referenceController, state.draft.reference ?? '');
        return OnboardingScaffold(
          step: MerchantOnboardingStep.location,
          title: 'Detalhes da localização',
          subtitle:
              'Opcional. Pode adicionar um endereço agora ou completar esta informação mais tarde.',
          onBack: () => context.go(backRoute),
          errorMessage: state.errorMessage,
          primaryLabel: 'Guardar e continuar',
          onPrimaryPressed: () => _continue(saveDetails: true),
          secondaryLabel: 'Adicionar depois',
          onSecondaryPressed: () => _continue(saveDetails: false),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Área principal já guardada',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppColors.primaryDarker,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          [
                            state.draft.city?.trim(),
                            state.draft.district?.trim(),
                          ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              label: 'Endereço (opcional)',
              prefixIcon: const Icon(Icons.map_rounded),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.streetAddressLine1],
              useFloatingLabel: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _referenceController,
              textCapitalization: TextCapitalization.sentences,
              label: 'Ponto de referência (opcional)',
              prefixIcon: const Icon(Icons.flag_rounded),
              textInputAction: TextInputAction.done,
              useFloatingLabel: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Não precisa de conhecer latitude ou longitude. Poderá definir a posição exata mais tarde nas configurações.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _continue({required bool saveDetails}) async {
    final controller = ref.read(merchantOnboardingControllerProvider.notifier);
    if (saveDetails) {
      await controller.updateLocationDetails(
        address: _addressController.text,
        reference: _referenceController.text,
      );
    }
    final moved =
        await controller.continueFromStep(MerchantOnboardingStep.location);
    if (moved && mounted) {
      context.go(
        widget.returnRoute ?? MerchantOnboardingStep.workingHours.route,
      );
    }
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }
}
