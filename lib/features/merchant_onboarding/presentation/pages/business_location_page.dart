import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../design_system/components/maisum_text_field.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class BusinessLocationPage extends ConsumerStatefulWidget {
  const BusinessLocationPage({super.key});

  @override
  ConsumerState<BusinessLocationPage> createState() =>
      _BusinessLocationPageState();
}

class _BusinessLocationPageState extends ConsumerState<BusinessLocationPage> {
  late final TextEditingController _addressController;
  late final TextEditingController _referenceController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _referenceController = TextEditingController();
    _latitudeController = TextEditingController();
    _longitudeController = TextEditingController();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _referenceController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);
    return asyncState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: ErrorCard(message: 'Nao foi possivel carregar a localizacao.')),
      data: (state) {
        _syncController(_addressController, state.draft.address ?? '');
        _syncController(_referenceController, state.draft.reference ?? '');
        final location = state.draft.location;
        if (location != null) {
          _syncController(_latitudeController, location.latitude.toString());
          _syncController(_longitudeController, location.longitude.toString());
        }
        return OnboardingScaffold(
          step: MerchantOnboardingStep.location,
          title: 'Onde esta o seu negocio?',
          subtitle:
              'Esta localizacao sera usada para que os clientes o encontrem mais facilmente.',
          errorMessage: state.errorMessage,
          primaryLabel: 'Continuar',
          onPrimaryPressed: () async {
            await _save();
            final moved = await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .continueFromStep(MerchantOnboardingStep.location);
            if (moved && context.mounted) {
              context.go(MerchantOnboardingStep.workingHours.route);
            }
          },
          children: [
            Container(
              height: AppSpacing.xxxxxxl * 3,
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.g100),
                boxShadow: AppShadows.sm,
              ),
              child: Center(
                child: Semantics(
                  label:
                      'Mapa indisponivel. Insira as coordenadas manualmente.',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: AppSpacing.xxxxxxl,
                        height: AppSpacing.xxxxxxl,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryDarker,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_pin,
                          size: AppSpacing.xxxl,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Localização manual',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.primaryDarker,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Use endereço e coordenadas.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              label: 'Endereco selecionado *',
              prefixIcon: const Icon(Icons.map_rounded),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.streetAddressLine1],
              useFloatingLabel: true,
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: MaisUmTextField(
                    controller: _latitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    label: 'Latitude *',
                    prefixIcon: const Icon(Icons.explore_rounded),
                    textInputAction: TextInputAction.next,
                    useFloatingLabel: true,
                    onChanged: (_) => _save(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MaisUmTextField(
                    controller: _longitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    label: 'Longitude *',
                    prefixIcon: const Icon(Icons.explore_rounded),
                    textInputAction: TextInputAction.next,
                    useFloatingLabel: true,
                    onChanged: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            MaisUmTextField(
              controller: _referenceController,
              textCapitalization: TextCapitalization.sentences,
              label: 'Ponto de referencia (opcional)',
              prefixIcon: const Icon(Icons.flag_rounded),
              textInputAction: TextInputAction.done,
              useFloatingLabel: true,
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            const ErrorCard(
              message: 'Mapa interativo indisponivel nesta versao.',
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() {
    return ref
        .read(merchantOnboardingControllerProvider.notifier)
        .updateLocation(
          location: _locationFromAddress(),
          address: _addressController.text,
          reference: _referenceController.text,
        );
  }

  MerchantLocation? _locationFromAddress() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) return null;
    return MerchantLocation(latitude: latitude, longitude: longitude);
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }
}
