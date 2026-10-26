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
    return '/choose-role';
  }
  if (session.isCustomer) return '/customer/home';

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
    final isComplete = isOnboardedBusiness(data, draft);

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

/// Whether this business has actually been through onboarding.
///
/// The steps themselves are the first question, and `business_profile_version`
/// is the second: the onboarding flow writes it, so its presence is a positive
/// statement that these screens ran to the end.
///
/// The name check behind it exists only to catch businesses created before
/// that flow existed — auto-named and never set up. It must not outrank the
/// marker, because "Minha Loja" is *also* the name this app suggests, and an
/// owner who accepted the suggestion finished onboarding, was judged never to
/// have started, and was returned to the first screen — every time they signed
/// in, with no way through. A shop is allowed to be called Minha Loja.
bool isOnboardedBusiness(Map<String, dynamic> data, MerchantDraft draft) {
  if (!isMerchantOnboardingCompleteDraft(draft)) return false;
  if (data['business_profile_version'] != null) return true;
  return _hasRealMerchantName(draft.businessName);
}

bool _hasRealMerchantName(String? value) {
  final merchantName = value?.trim() ?? '';
  return merchantName.isNotEmpty &&
      merchantName.toLowerCase() != _legacyMerchantPlaceholder.toLowerCase();
}
