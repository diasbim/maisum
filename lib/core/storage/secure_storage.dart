import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class SecureStorageService {
  const SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  Future<void> saveToken(String token) => _storage.write(
        key: AppConstants.tokenKey,
        value: token,
        aOptions: _androidOptions,
      );

  Future<String?> getToken() =>
      _storage.read(key: AppConstants.tokenKey, aOptions: _androidOptions);

  Future<void> saveUserId(String userId) => _storage.write(
        key: AppConstants.userIdKey,
        value: userId,
        aOptions: _androidOptions,
      );

  Future<String?> getUserId() =>
      _storage.read(key: AppConstants.userIdKey, aOptions: _androidOptions);

  Future<void> saveAppUserId(String userId) => _storage.write(
        key: AppConstants.appUserIdKey,
        value: userId,
        aOptions: _androidOptions,
      );

  Future<String?> getAppUserId() =>
      _storage.read(key: AppConstants.appUserIdKey, aOptions: _androidOptions);

  Future<void> saveAppUserRole(String role) => _storage.write(
        key: AppConstants.appUserRoleKey,
        value: role,
        aOptions: _androidOptions,
      );

  Future<String?> getAppUserRole() => _storage.read(
        key: AppConstants.appUserRoleKey,
        aOptions: _androidOptions,
      );

  Future<bool> isOwnerUser() async {
    final role = await getAppUserRole();
    if (role == null || role.trim().isEmpty) {
      return true;
    }
    return role.trim().toUpperCase() == AppConstants.appUserRoleOwner;
  }

  Future<void> saveUserPhone(String phone) => _storage.write(
        key: AppConstants.userPhoneKey,
        value: phone,
        aOptions: _androidOptions,
      );

  Future<String?> getUserPhone() =>
      _storage.read(key: AppConstants.userPhoneKey, aOptions: _androidOptions);

  Future<void> saveMerchantId(String merchantId) => _storage.write(
        key: AppConstants.merchantIdKey,
        value: merchantId,
        aOptions: _androidOptions,
      );

  Future<String?> getMerchantId() =>
      _storage.read(key: AppConstants.merchantIdKey, aOptions: _androidOptions);

  Future<void> saveMerchantName(String merchantName) => _storage.write(
        key: AppConstants.merchantNameKey,
        value: merchantName,
        aOptions: _androidOptions,
      );

  Future<String?> getMerchantName() => _storage.read(
        key: AppConstants.merchantNameKey,
        aOptions: _androidOptions,
      );

  Future<void> saveSubscriptionStatus(String status) => _storage.write(
        key: AppConstants.subscriptionStatusKey,
        value: status,
        aOptions: _androidOptions,
      );

  Future<String?> getSubscriptionStatus() => _storage.read(
        key: AppConstants.subscriptionStatusKey,
        aOptions: _androidOptions,
      );

  Future<void> saveRefreshToken(String refreshToken) => _storage.write(
        key: AppConstants.refreshTokenKey,
        value: refreshToken,
        aOptions: _androidOptions,
      );

  Future<String?> getRefreshToken() => _storage.read(
        key: AppConstants.refreshTokenKey,
        aOptions: _androidOptions,
      );

  Future<void> saveDeviceId(String deviceId) => _storage.write(
        key: AppConstants.deviceIdKey,
        value: deviceId,
        aOptions: _androidOptions,
      );

  Future<String?> getDeviceId() =>
      _storage.read(key: AppConstants.deviceIdKey, aOptions: _androidOptions);

  Future<void> saveTokenExpiry(DateTime expiry) => _storage.write(
        key: AppConstants.tokenExpiryKey,
        value: expiry.millisecondsSinceEpoch.toString(),
        aOptions: _androidOptions,
      );

  Future<DateTime?> getTokenExpiry() async {
    final raw = await _storage.read(
      key: AppConstants.tokenExpiryKey,
      aOptions: _androidOptions,
    );
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
  }

  Future<bool> hasValidToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    final expiry = await getTokenExpiry();
    if (expiry == null) return false;
    return expiry.isAfter(DateTime.now());
  }

  Future<void> clearAll() => _storage.deleteAll(aOptions: _androidOptions);

  // PIN management
  Future<void> savePin(String pin) => _storage.write(
        key: AppConstants.pinKey,
        value: pin,
        aOptions: _androidOptions,
      );

  Future<String?> getPin() =>
      _storage.read(key: AppConstants.pinKey, aOptions: _androidOptions);

  Future<void> clearPin() =>
      _storage.delete(key: AppConstants.pinKey, aOptions: _androidOptions);

  Future<bool> hasPin() async {
    final pin = await getPin();
    return pin != null && pin.isNotEmpty;
  }

  // PIN attempt tracking
  Future<void> savePinAttempts(int count) => _storage.write(
        key: AppConstants.pinAttemptsKey,
        value: count.toString(),
        aOptions: _androidOptions,
      );

  Future<int> getPinAttempts() async {
    final raw = await _storage.read(
      key: AppConstants.pinAttemptsKey,
      aOptions: _androidOptions,
    );
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<void> clearPinAttempts() => _storage.write(
        key: AppConstants.pinAttemptsKey,
        value: '0',
        aOptions: _androidOptions,
      );

  // Firebase UID
  Future<void> saveFirebaseUid(String uid) => _storage.write(
        key: AppConstants.firebaseUidKey,
        value: uid,
        aOptions: _androidOptions,
      );

  Future<String?> getFirebaseUid() => _storage.read(
        key: AppConstants.firebaseUidKey,
        aOptions: _androidOptions,
      );

  // SMS permission onboarding
  Future<void> setSmsPermissionPrompted(bool value) => _storage.write(
        key: AppConstants.smsPermissionPromptedKey,
        value: value ? '1' : '0',
        aOptions: _androidOptions,
      );

  Future<bool> hasSmsPermissionPrompted() async {
    final raw = await _storage.read(
      key: AppConstants.smsPermissionPromptedKey,
      aOptions: _androidOptions,
    );
    return raw == '1';
  }

  // Onboarding plan selection
  Future<void> saveMerchantOnboardingDraft(
    String value, {
    String? merchantId,
    String? role,
  }) =>
      _storage.write(
        key: _merchantOnboardingDraftKey(merchantId: merchantId, role: role),
        value: value,
        aOptions: _androidOptions,
      );

  Future<String?> getMerchantOnboardingDraft({
    String? merchantId,
    String? role,
  }) =>
      _storage.read(
        key: _merchantOnboardingDraftKey(merchantId: merchantId, role: role),
        aOptions: _androidOptions,
      );

  Future<void> clearMerchantOnboardingDraft({
    String? merchantId,
    String? role,
  }) =>
      _storage.delete(
        key: _merchantOnboardingDraftKey(merchantId: merchantId, role: role),
        aOptions: _androidOptions,
      );

  Future<void> setOnboardingPlanConfirmed(
    bool value, {
    String? merchantId,
    String? role,
  }) =>
      _storage.write(
        key: _onboardingPlanConfirmedKey(merchantId: merchantId, role: role),
        value: value ? '1' : '0',
        aOptions: _androidOptions,
      );

  Future<bool> hasConfirmedOnboardingPlan({
    String? merchantId,
    String? role,
  }) async {
    final key = _onboardingPlanConfirmedKey(merchantId: merchantId, role: role);
    final raw = await _storage.read(
      key: key,
      aOptions: _androidOptions,
    );
    if (raw != null) {
      return raw == '1';
    }
    if (key != AppConstants.onboardingPlanConfirmedKey) {
      final legacyRaw = await _storage.read(
        key: AppConstants.onboardingPlanConfirmedKey,
        aOptions: _androidOptions,
      );
      if (legacyRaw != null) {
        return legacyRaw == '1';
      }
    }
    // Legacy users may not have this key, so treat missing state as already confirmed.
    return true;
  }

  String _onboardingPlanConfirmedKey({String? merchantId, String? role}) {
    final normalizedMerchantId = _normalizeKeySegment(merchantId);
    final normalizedRole = _normalizeKeySegment(role?.toUpperCase());
    if (normalizedMerchantId.isEmpty || normalizedRole.isEmpty) {
      return AppConstants.onboardingPlanConfirmedKey;
    }
    return '${AppConstants.onboardingPlanConfirmedKey}_${normalizedMerchantId}_$normalizedRole';
  }

  String _merchantOnboardingDraftKey({String? merchantId, String? role}) {
    final normalizedMerchantId = _normalizeKeySegment(merchantId);
    final normalizedRole = _normalizeKeySegment(role?.toUpperCase());
    if (normalizedMerchantId.isEmpty || normalizedRole.isEmpty) {
      return 'merchant_onboarding_draft';
    }
    return 'merchant_onboarding_draft_${normalizedMerchantId}_$normalizedRole';
  }

  String _normalizeKeySegment(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
