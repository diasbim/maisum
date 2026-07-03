import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../merchant_onboarding/domain/merchant_onboarding_models.dart';
import '../../merchant_onboarding/presentation/controllers/merchant_onboarding_controller.dart';
import 'auth_controller.dart';

const _legacyMerchantPlaceholder = 'Minha Loja';

Future<String> resolvePostAuthRoute(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  final session = read(authControllerProvider).valueOrNull;
  if (session == null) {
    return '/login';
  }

  final merchantId = read(activeMerchantIdProvider);
  if (merchantId == null || merchantId.isEmpty) {
    return '/onboarding-entry';
  }

  try {
    final doc = await read(firestoreInstanceProvider)
        .collection('businesses')
        .doc(merchantId)
        .get();
    if (!doc.exists) {
      final looksDetached = merchantId == session.userId ||
          (session.firebaseUid != null && merchantId == session.firebaseUid);
      if (looksDetached) {
        return '/onboarding-entry';
      }
      return merchantOnboardingStartRoute;
    }

    final data = doc.data() ?? <String, dynamic>{};
    final draft =
        merchantDraftFromBusinessData(data, fallbackPhone: session.phone);
    final isComplete = isMerchantOnboardingCompleteDraft(draft) &&
        _hasRealMerchantName(draft.businessName);

    if (!isComplete) {
      final hasExplicitMerchant = session.merchantId != null &&
          session.merchantId!.isNotEmpty &&
          session.merchantId != session.userId &&
          session.merchantId != session.firebaseUid;
      if (!hasExplicitMerchant) {
        return '/onboarding-entry';
      }
      return merchantOnboardingStartRoute;
    }

    final storage = read(secureStorageServiceProvider);
    final appUserRole = await storage.getAppUserRole();
    if (appUserRole?.trim().toUpperCase() == AppConstants.appUserRoleStaff) {
      return '/dashboard';
    }

    final hasConfirmedPlan = await storage.hasConfirmedOnboardingPlan(
      merchantId: merchantId,
      role: appUserRole,
    );

    return hasConfirmedPlan ? '/dashboard' : '/onboarding-plan';
  } catch (e, st) {
    AppErrorReporter.report(e, st, hint: 'post_auth_route_resolution');
    // Prefer onboarding setup as safe fallback when profile state is unknown.
    return merchantOnboardingStartRoute;
  }
}

bool _hasRealMerchantName(String? value) {
  final merchantName = value?.trim() ?? '';
  return merchantName.isNotEmpty &&
      merchantName.toLowerCase() != _legacyMerchantPlaceholder.toLowerCase();
}
