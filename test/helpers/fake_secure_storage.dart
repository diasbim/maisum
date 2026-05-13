import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:maisum/core/storage/secure_storage.dart';

/// In-memory SecureStorageService for widget tests — avoids the
/// FlutterSecureStorage platform channel (EncryptedSharedPreferences on Android).
class FakeSecureStorageService extends SecureStorageService {
  FakeSecureStorageService() : super(const FlutterSecureStorage());

  final _store = <String, String>{};

  // PIN
  @override
  Future<void> savePin(String pin) async => _store['pin'] = pin;
  @override
  Future<String?> getPin() async => _store['pin'];
  @override
  Future<void> clearPin() async => _store.remove('pin');
  @override
  Future<bool> hasPin() async => _store.containsKey('pin');

  // PIN attempts
  @override
  Future<void> savePinAttempts(int n) async => _store['attempts'] = '$n';
  @override
  Future<int> getPinAttempts() async =>
      int.tryParse(_store['attempts'] ?? '0') ?? 0;
  @override
  Future<void> clearPinAttempts() async => _store['attempts'] = '0';

  // Firebase UID
  @override
  Future<void> saveFirebaseUid(String uid) async => _store['firebase_uid'] = uid;
  @override
  Future<String?> getFirebaseUid() async => _store['firebase_uid'];

  // Token / session — no-ops; not needed for PIN screen tests
  @override
  Future<void> saveToken(String token) async {}
  @override
  Future<String?> getToken() async => null;
  @override
  Future<void> saveUserId(String userId) async {}
  @override
  Future<String?> getUserId() async => null;
  @override
  Future<void> saveUserPhone(String phone) async => _store['phone'] = phone;
  @override
  Future<String?> getUserPhone() async => _store['phone'];
  @override
  Future<void> saveTokenExpiry(DateTime expiry) async {}
  @override
  Future<DateTime?> getTokenExpiry() async => null;
  @override
  Future<bool> hasValidToken() async => false;
  @override
  Future<void> clearAll() async => _store.clear();
}

