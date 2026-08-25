import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_error_reporter.dart';
import '../../auth/domain/auth_session.dart';
import '../../business_profile/domain/business_profile.dart';
import '../domain/merchant_onboarding_models.dart';

class MerchantOnboardingRepository {
  const MerchantOnboardingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<MerchantOnboardingConfig> loadConfig() async {
    try {
      final doc = await _firestore
          .collection('merchant_onboarding_config')
          .doc('default')
          .get();
      final data = doc.data();
      if (data == null) {
        return MerchantOnboardingConfig.fallback;
      }
      final config = MerchantOnboardingConfig.fromJson(data);
      if (config.businessTypes.isEmpty) {
        return MerchantOnboardingConfig.fallback;
      }
      return config.withBuiltInProfiles();
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_onboarding_config_load',
      );
      return MerchantOnboardingConfig.fallback;
    }
  }

  Future<MerchantDraft> loadRemoteDraft(AuthSession session) async {
    final merchantId = session.resolvedMerchantId;
    if (merchantId.isEmpty) {
      return MerchantDraft.empty(phone: session.phone);
    }

    try {
      final doc =
          await _firestore.collection('businesses').doc(merchantId).get();
      final data = doc.data();
      if (data == null) {
        return MerchantDraft.empty(phone: session.phone);
      }

      return merchantDraftFromBusinessData(data, fallbackPhone: session.phone);
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_onboarding_remote_draft_load',
      );
      return MerchantDraft.empty(phone: session.phone);
    }
  }

  Future<void> saveMerchant({
    required AuthSession session,
    required MerchantDraft draft,
    required String firebaseUid,
    required bool wasProfileCompleteAtLoad,
  }) async {
    final merchantId = session.resolvedMerchantId;
    if (merchantId.isEmpty) {
      throw StateError('Sessão inválida para criar comerciante.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final businessRef = _firestore.collection('businesses').doc(merchantId);
    final batch = _firestore.batch();
    batch.set(
        businessRef,
        {
          'id': merchantId,
          'merchant_name': draft.businessName?.trim(),
          'phone': draft.phone?.trim() ?? session.phone,
          'city': draft.city?.trim(),
          'business_type': draft.businessType,
          'business_profile_version': BusinessProfiles.schemaVersion,
          'owner_user_id': session.resolvedAppUserId,
          'firebase_uid': firebaseUid,
          if ((draft.district ?? '').trim().isNotEmpty)
            'district': draft.district!.trim(),
          if ((draft.address ?? '').trim().isNotEmpty)
            'address': draft.address!.trim(),
          if ((draft.reference ?? '').trim().isNotEmpty)
            'reference': draft.reference!.trim(),
          if (draft.location != null) 'location': draft.location!.toJson(),
          'working_hours': draft.workingHours.map(
            (key, value) => MapEntry(key.toString(), value.toJson()),
          ),
          'services':
              draft.services.map((service) => service.toJson()).toList(),
          if (!wasProfileCompleteAtLoad) 'created_at': now,
          'updated_at': now,
        },
        SetOptions(merge: true));

    for (var index = 0; index < draft.services.length; index++) {
      final item = draft.services[index];
      final itemRef = businessRef.collection('merchant_items').doc(item.id);
      batch.set(
          itemRef,
          {
            'id': item.id,
            'merchant_id': merchantId,
            'name': item.name,
            'type': item.itemKind.name.toUpperCase(),
            'default_price': null,
            'is_active': true,
            'display_order': index,
            'created_at': now,
            'updated_at': now,
            'created_by_app_user_id': session.resolvedAppUserId,
            'updated_by_app_user_id': session.resolvedAppUserId,
          },
          SetOptions(merge: true));
    }

    await batch.commit();
  }
}
