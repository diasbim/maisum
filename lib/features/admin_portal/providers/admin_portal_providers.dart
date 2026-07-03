import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart' as app_providers;
import '../../auth/presentation/auth_controller.dart' as auth_providers;
import '../data/admin_portal_api.dart';
import '../domain/admin_audit_event.dart';
import '../domain/admin_merchant_summary.dart';
import '../domain/admin_operations_summary.dart';
import '../domain/admin_plan_catalog.dart';

final adminPortalApiProvider = Provider<AdminPortalApi>((ref) {
  return AdminPortalApi(
    ref.read(app_providers.cloudFunctionsApiClientProvider),
    () async {
      final currentUser =
          ref.read(app_providers.firebaseAuthInstanceProvider).currentUser;
      return currentUser?.getIdToken();
    },
  );
});

final adminMerchantSummariesProvider = FutureProvider.autoDispose
    .family<List<AdminMerchantSummary>, String?>((ref, search) async {
  await ref.watch(auth_providers.isInternalAdminProvider.future);
  return ref.read(adminPortalApiProvider).getMerchants(search: search);
});

final adminMerchantDetailProvider = FutureProvider.autoDispose
    .family<AdminMerchantDetail, String>((ref, merchantId) async {
  await ref.watch(auth_providers.isInternalAdminProvider.future);
  return ref.read(adminPortalApiProvider).getMerchant(merchantId);
});

final adminAuditEventsProvider = FutureProvider.autoDispose
    .family<List<AdminAuditEvent>, String?>((ref, merchantId) async {
  await ref.watch(auth_providers.isInternalAdminProvider.future);
  return ref
      .read(adminPortalApiProvider)
      .getAuditEvents(merchantId: merchantId);
});

final adminPlanCatalogProvider =
    FutureProvider.autoDispose<List<AdminPlanCatalogItem>>((ref) async {
  await ref.watch(auth_providers.isInternalAdminProvider.future);
  return ref.read(adminPortalApiProvider).getPlans();
});

final adminOperationsSummaryProvider =
    FutureProvider.autoDispose<AdminOperationsSummary>((ref) async {
  await ref.watch(auth_providers.isInternalAdminProvider.future);
  return ref.read(adminPortalApiProvider).getOperationsSummary();
});
