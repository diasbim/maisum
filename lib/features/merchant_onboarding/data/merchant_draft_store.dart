import 'dart:convert';

import '../../../core/errors/app_error_reporter.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/merchant_onboarding_models.dart';

class MerchantDraftStore {
  const MerchantDraftStore(this._storage);

  final SecureStorageService _storage;

  Future<MerchantDraft?> load({String? merchantId, String? role}) async {
    final raw = await _storage.getMerchantOnboardingDraft(
      merchantId: merchantId,
      role: role,
    );
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return MerchantDraft.fromJson(decoded);
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_onboarding_draft_load',
      );
      return null;
    }
  }

  Future<void> save(
    MerchantDraft draft, {
    String? merchantId,
    String? role,
  }) {
    return _storage.saveMerchantOnboardingDraft(
      jsonEncode(draft.toJson()),
      merchantId: merchantId,
      role: role,
    );
  }

  Future<void> clear({String? merchantId, String? role}) {
    return _storage.clearMerchantOnboardingDraft(
      merchantId: merchantId,
      role: role,
    );
  }
}
