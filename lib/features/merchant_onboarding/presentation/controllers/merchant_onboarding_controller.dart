import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_error_reporter.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/merchant_draft_store.dart';
import '../../data/merchant_onboarding_repository.dart';
import '../../domain/merchant_onboarding_models.dart';

const merchantOnboardingStartRoute = '/merchant-onboarding/type';

final merchantDraftStoreProvider = Provider<MerchantDraftStore>((ref) {
  return MerchantDraftStore(ref.read(secureStorageServiceProvider));
});

final merchantOnboardingRepositoryProvider =
    Provider<MerchantOnboardingRepository>((ref) {
  return MerchantOnboardingRepository(ref.read(firestoreInstanceProvider));
});

final merchantOnboardingControllerProvider = AsyncNotifierProvider<
    MerchantOnboardingController, MerchantOnboardingState>(
  MerchantOnboardingController.new,
);

class MerchantOnboardingState {
  const MerchantOnboardingState({
    required this.draft,
    required this.config,
    required this.currentStep,
    required this.wasProfileCompleteAtLoad,
    this.isSaving = false,
    this.errorMessage,
  });

  final MerchantDraft draft;
  final MerchantOnboardingConfig config;
  final MerchantOnboardingStep currentStep;
  final bool wasProfileCompleteAtLoad;
  final bool isSaving;
  final String? errorMessage;

  MerchantOnboardingState copyWith({
    MerchantDraft? draft,
    MerchantOnboardingConfig? config,
    MerchantOnboardingStep? currentStep,
    bool? wasProfileCompleteAtLoad,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MerchantOnboardingState(
      draft: draft ?? this.draft,
      config: config ?? this.config,
      currentStep: currentStep ?? this.currentStep,
      wasProfileCompleteAtLoad:
          wasProfileCompleteAtLoad ?? this.wasProfileCompleteAtLoad,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  bool get canContinue => validate(currentStep) == null;

  String? validate(MerchantOnboardingStep step) {
    switch (step) {
      case MerchantOnboardingStep.verifyPhone:
        return (draft.phone ?? '').trim().isEmpty
            ? 'Telefone verificado obrigatorio.'
            : null;
      case MerchantOnboardingStep.businessType:
        return (draft.businessType ?? '').trim().isEmpty
            ? 'Selecione o tipo do seu negocio.'
            : null;
      case MerchantOnboardingStep.businessInfo:
        final name = (draft.businessName ?? '').trim();
        if (name.length < 3) {
          return 'O nome deve ter pelo menos 3 caracteres.';
        }
        if ((draft.city ?? '').trim().isEmpty) {
          return 'Informe a cidade.';
        }
        if ((draft.phone ?? '').trim().isEmpty) {
          return 'Telefone verificado obrigatorio.';
        }
        return null;
      case MerchantOnboardingStep.location:
        if (draft.location == null) {
          return 'Selecione a localizacao do negocio.';
        }
        if ((draft.address ?? '').trim().isEmpty) {
          return 'Informe o endereco do negocio.';
        }
        return null;
      case MerchantOnboardingStep.workingHours:
        final openDays =
            draft.workingHours.values.where((hours) => hours.isOpen);
        return openDays.isEmpty ? 'Defina pelo menos um dia aberto.' : null;
      case MerchantOnboardingStep.services:
        return null;
      case MerchantOnboardingStep.review:
        for (final step in MerchantOnboardingStep.values.skip(1).take(5)) {
          final message = validate(step);
          if (message != null) return message;
        }
        return null;
    }
  }
}

class MerchantOnboardingController
    extends AsyncNotifier<MerchantOnboardingState> {
  @override
  Future<MerchantOnboardingState> build() async {
    final session = await ref.watch(authControllerProvider.future);
    if (session == null) {
      throw StateError('Sem sessao ativa.');
    }

    final role = await ref.read(secureStorageServiceProvider).getAppUserRole();
    final repository = ref.read(merchantOnboardingRepositoryProvider);
    final remoteDraft = await _loadRemoteDraft(repository, session);
    final config = await _loadConfig(repository);
    final localDraft = await ref.read(merchantDraftStoreProvider).load(
          merchantId: session.resolvedMerchantId,
          role: role,
        );
    final initialDraft = (localDraft ?? const MerchantDraft()).mergeMissing(
      remoteDraft.mergeMissing(MerchantDraft.empty(phone: session.phone)),
    );
    final configuredDraft = initialDraft.workingHours.isEmpty
        ? initialDraft.copyWith(workingHours: config.defaultWorkingHours)
        : initialDraft;

    return MerchantOnboardingState(
      draft: configuredDraft,
      config: config,
      currentStep: firstIncompleteStep(configuredDraft),
      wasProfileCompleteAtLoad: _isProfileComplete(remoteDraft),
    );
  }

  Future<MerchantDraft> _loadRemoteDraft(
    MerchantOnboardingRepository repository,
    AuthSession session,
  ) async {
    try {
      return await repository.loadRemoteDraft(session);
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_onboarding_controller_remote_draft_load',
      );
      return MerchantDraft.empty(phone: session.phone);
    }
  }

  Future<MerchantOnboardingConfig> _loadConfig(
    MerchantOnboardingRepository repository,
  ) async {
    try {
      final config = await repository.loadConfig();
      if (config.businessTypes.isEmpty) {
        return MerchantOnboardingConfig.fallback;
      }
      return config;
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_onboarding_controller_config_load',
      );
      return MerchantOnboardingConfig.fallback;
    }
  }

  void setCurrentStep(MerchantOnboardingStep step) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(currentStep: step, clearError: true));
  }

  Future<void> updateDraft(MerchantDraft draft) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(draft: draft, clearError: true));
    await _saveLocalDraft(draft);
  }

  Future<void> selectBusinessType(String value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await updateDraft(current.draft.copyWith(businessType: value));
  }

  Future<void> updateBusinessInfo({
    required String businessName,
    required String city,
    String? district,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await updateDraft(current.draft.copyWith(
      businessName: businessName,
      city: city,
      district: district,
    ));
  }

  Future<void> updateLocation({
    MerchantLocation? location,
    required String address,
    String? reference,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await updateDraft(current.draft.copyWith(
      location: location,
      address: address,
      reference: reference,
      clearLocation: location == null,
    ));
  }

  Future<void> updateWorkingHours(Map<int, WorkingHours> workingHours) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await updateDraft(current.draft.copyWith(workingHours: workingHours));
  }

  Future<void> updateServices(List<MerchantService> services) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await updateDraft(current.draft.copyWith(services: services));
  }

  Future<bool> continueFromCurrentStep() async {
    final current = state.valueOrNull;
    if (current == null) return false;
    return continueFromStep(current.currentStep);
  }

  Future<bool> continueFromStep(MerchantOnboardingStep step) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final validationMessage = current.validate(step);
    if (validationMessage != null) {
      state = AsyncData(current.copyWith(
        currentStep: step,
        errorMessage: validationMessage,
      ));
      return false;
    }
    final nextStep = _nextStep(step);
    if (nextStep == null) return true;
    state =
        AsyncData(current.copyWith(currentStep: nextStep, clearError: true));
    return true;
  }

  Future<void> createMerchant() async {
    final current = state.valueOrNull;
    if (current == null || current.isSaving) return;

    final validationMessage = current.validate(MerchantOnboardingStep.review);
    if (validationMessage != null) {
      state = AsyncData(current.copyWith(errorMessage: validationMessage));
      return;
    }

    state = AsyncData(current.copyWith(isSaving: true, clearError: true));
    try {
      var session = await ref.read(authControllerProvider.future);
      if (session == null) throw StateError('Sem sessao ativa.');

      final authController = ref.read(authControllerProvider.notifier);
      final onboardingRepository =
          ref.read(merchantOnboardingRepositoryProvider);
      final storage = ref.read(secureStorageServiceProvider);
      final draftStore = ref.read(merchantDraftStoreProvider);

      final draft = current.draft;
      final businessName = draft.businessName?.trim();
      if (businessName != null &&
          businessName.isNotEmpty &&
          businessName != session.merchantName) {
        session = await authController.updateMerchantName(businessName);
      }

      final firebaseUid = session.firebaseUid ??
          ref.read(firebaseAuthInstanceProvider).currentUser?.uid;
      if (firebaseUid == null || firebaseUid.isEmpty) {
        throw StateError('Sessao Firebase invalida para criar comerciante.');
      }

      await onboardingRepository.saveMerchant(
        session: session,
        draft: draft,
        firebaseUid: firebaseUid,
        wasProfileCompleteAtLoad: current.wasProfileCompleteAtLoad,
      );
      ref.invalidate(activeBusinessProfileProvider);

      if (!current.wasProfileCompleteAtLoad) {
        final trialDays =
            await ref.read(remoteConfigReaderProvider).getTrialDays();
        await ref.read(subscriptionRepositoryProvider).ensureTrialStarted(
              merchantId: session.resolvedMerchantId,
              startedAt: DateTime.now(),
              trialDays: trialDays,
            );
        ref.invalidate(subscriptionStateProvider);
        ref.invalidate(subscriptionSnapshotProvider);
      }

      final role = await storage.getAppUserRole();
      await storage.setOnboardingPlanConfirmed(
        true,
        merchantId: session.resolvedMerchantId,
        role: role,
      );
      await draftStore.clear(
        merchantId: session.resolvedMerchantId,
        role: role,
      );
      state = AsyncData(current.copyWith(isSaving: false, clearError: true));
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_onboarding_create',
      );
      state = AsyncData(current.copyWith(
        isSaving: false,
        errorMessage: 'Nao foi possivel criar o negocio. Tente novamente.',
      ));
      rethrow;
    }
  }

  Future<void> _saveLocalDraft(MerchantDraft draft) async {
    final session = await ref.read(authControllerProvider.future);
    final role = await ref.read(secureStorageServiceProvider).getAppUserRole();
    await ref.read(merchantDraftStoreProvider).save(
          draft,
          merchantId: session?.resolvedMerchantId,
          role: role,
        );
  }

  static MerchantOnboardingStep firstIncompleteStep(MerchantDraft draft) {
    final probe = MerchantOnboardingState(
      draft: draft,
      config: const MerchantOnboardingConfig(),
      currentStep: MerchantOnboardingStep.businessType,
      wasProfileCompleteAtLoad: false,
    );
    for (final step in MerchantOnboardingStep.values.skip(1).take(5)) {
      if (probe.validate(step) != null) return step;
    }
    return MerchantOnboardingStep.review;
  }

  MerchantOnboardingStep? _nextStep(MerchantOnboardingStep step) {
    final index = MerchantOnboardingStep.values.indexOf(step);
    if (index < 0 || index >= MerchantOnboardingStep.values.length - 1) {
      return null;
    }
    return MerchantOnboardingStep.values[index + 1];
  }

  bool _isProfileComplete(MerchantDraft draft) {
    final name = (draft.businessName ?? '').trim();
    final phone = (draft.phone ?? '').trim();
    return name.isNotEmpty &&
        name.toLowerCase() != 'minha loja' &&
        phone.isNotEmpty;
  }
}

String routeForFirstIncompleteMerchantOnboardingStep(MerchantDraft draft) {
  return MerchantOnboardingController.firstIncompleteStep(draft).route;
}

bool isMerchantOnboardingRoute(String location) {
  return location.startsWith('/merchant-onboarding');
}

bool isMerchantOnboardingCompleteDraft(MerchantDraft draft) {
  return MerchantOnboardingController.firstIncompleteStep(draft) ==
      MerchantOnboardingStep.review;
}

String normalizeAppUserRole(String? role) {
  final normalized = role?.trim().toUpperCase();
  return normalized == null || normalized.isEmpty
      ? AppConstants.appUserRoleOwner
      : normalized;
}
