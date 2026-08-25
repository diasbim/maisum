import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/components/maisum_text_field.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class BusinessInfoPage extends ConsumerStatefulWidget {
  const BusinessInfoPage({super.key});

  @override
  ConsumerState<BusinessInfoPage> createState() => _BusinessInfoPageState();
}

class _BusinessInfoPageState extends ConsumerState<BusinessInfoPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _cityController;
  late final TextEditingController _districtController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _cityController = TextEditingController();
    _districtController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);
    return asyncState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: ErrorCard(message: 'Não foi possível carregar os dados.')),
      data: (state) {
        _syncController(_nameController, state.draft.businessName ?? '');
        _syncController(_phoneController, state.draft.phone ?? '');
        _syncController(_cityController, state.draft.city ?? '');
        _syncController(_districtController, state.draft.district ?? '');

        return OnboardingScaffold(
          step: MerchantOnboardingStep.businessInfo,
          title: 'Dados do negócio',
          subtitle: 'Conte-nos mais sobre o seu negócio.',
          errorMessage: state.errorMessage,
          primaryLabel: 'Continuar',
          onPrimaryPressed: () async {
            await _save();
            final moved = await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .continueFromStep(MerchantOnboardingStep.businessInfo);
            if (moved && context.mounted) {
              context.go(MerchantOnboardingStep.location.route);
            }
          },
          children: [
            MaisUmTextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              label: 'Nome do negócio *',
              prefixIcon: const Icon(Icons.storefront_rounded),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.organizationName],
              useFloatingLabel: true,
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _phoneController,
              readOnly: true,
              label: 'Telemóvel verificado',
              prefixIcon: const Icon(Icons.phone_rounded),
              autofillHints: const [AutofillHints.telephoneNumber],
              useFloatingLabel: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              label: 'Cidade *',
              prefixIcon: const Icon(Icons.location_city_rounded),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.addressCity],
              useFloatingLabel: true,
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _districtController,
              textCapitalization: TextCapitalization.words,
              label: 'Bairro (opcional)',
              prefixIcon: const Icon(Icons.apartment_rounded),
              textInputAction: TextInputAction.done,
              useFloatingLabel: true,
              onChanged: (_) => _save(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() {
    return ref
        .read(merchantOnboardingControllerProvider.notifier)
        .updateBusinessInfo(
          businessName: _nameController.text,
          city: _cityController.text,
          district: _districtController.text,
        );
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }
}
