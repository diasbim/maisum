import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
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
      return '/merchant-config';
    }

    final data = doc.data() ?? <String, dynamic>{};

    final merchantName =
        ((data['merchant_name'] as String?) ?? session.merchantName).trim();
    final phone = ((data['phone'] as String?) ?? session.phone).trim();

    final hasMerchantName = merchantName.isNotEmpty &&
        merchantName.toLowerCase() != _legacyMerchantPlaceholder.toLowerCase();
    final isComplete = hasMerchantName && phone.isNotEmpty;

    if (!isComplete) {
      return '/merchant-config';
    }

    final hasConfirmedPlan =
        await read(secureStorageServiceProvider).hasConfirmedOnboardingPlan();

    return hasConfirmedPlan ? '/dashboard' : '/onboarding-plan';
  } catch (_) {
    // Prefer onboarding setup as safe fallback when profile state is unknown.
    return '/merchant-config';
  }
}
