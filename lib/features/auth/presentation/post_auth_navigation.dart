import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import 'auth_controller.dart';

Future<String> resolvePostAuthRoute(WidgetRef ref) async {
  final session = ref.read(authControllerProvider).valueOrNull;
  if (session == null) {
    return '/login';
  }

  final merchantId = ref.read(activeMerchantIdProvider);
  if (merchantId == null || merchantId.isEmpty) {
    return '/merchant-config';
  }

  try {
    final doc = await ref
        .read(firestoreInstanceProvider)
        .collection('businesses')
        .doc(merchantId)
        .get();
    final data = doc.data() ?? <String, dynamic>{};

    final merchantName =
        ((data['merchant_name'] as String?) ?? session.merchantName).trim();
    final phone = ((data['phone'] as String?) ?? session.phone).trim();
    final city = (data['city'] as String? ?? '').trim();
    final businessType = (data['business_type'] as String? ?? '').trim();

    final isComplete = merchantName.isNotEmpty &&
        phone.isNotEmpty &&
        city.isNotEmpty &&
        businessType.isNotEmpty;

    return isComplete ? '/dashboard' : '/merchant-config';
  } catch (_) {
    // Prefer onboarding setup as safe fallback when profile state is unknown.
    return '/merchant-config';
  }
}
