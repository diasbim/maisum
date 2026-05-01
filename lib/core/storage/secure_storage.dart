import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class SecureStorageService {
  const SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

  Future<void> saveToken(String token) =>
      _storage.write(key: AppConstants.tokenKey, value: token, aOptions: _androidOptions);

  Future<String?> getToken() =>
      _storage.read(key: AppConstants.tokenKey, aOptions: _androidOptions);

  Future<void> saveUserId(String userId) =>
      _storage.write(key: AppConstants.userIdKey, value: userId, aOptions: _androidOptions);

  Future<String?> getUserId() =>
      _storage.read(key: AppConstants.userIdKey, aOptions: _androidOptions);

  Future<void> saveUserPhone(String phone) =>
      _storage.write(key: AppConstants.userPhoneKey, value: phone, aOptions: _androidOptions);

  Future<String?> getUserPhone() =>
      _storage.read(key: AppConstants.userPhoneKey, aOptions: _androidOptions);

  Future<void> saveTokenExpiry(DateTime expiry) => _storage.write(
        key: AppConstants.tokenExpiryKey,
        value: expiry.millisecondsSinceEpoch.toString(),
        aOptions: _androidOptions,
      );

  Future<DateTime?> getTokenExpiry() async {
    final raw = await _storage.read(key: AppConstants.tokenExpiryKey, aOptions: _androidOptions);
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
  Future<void> savePin(String pin) =>
      _storage.write(key: AppConstants.pinKey, value: pin, aOptions: _androidOptions);

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
    final raw = await _storage.read(key: AppConstants.pinAttemptsKey, aOptions: _androidOptions);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<void> clearPinAttempts() =>
      _storage.write(key: AppConstants.pinAttemptsKey, value: '0', aOptions: _androidOptions);

  // Firebase UID
  Future<void> saveFirebaseUid(String uid) =>
      _storage.write(key: AppConstants.firebaseUidKey, value: uid, aOptions: _androidOptions);

  Future<String?> getFirebaseUid() =>
      _storage.read(key: AppConstants.firebaseUidKey, aOptions: _androidOptions);
}
