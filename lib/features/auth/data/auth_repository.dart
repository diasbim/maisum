import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/firebase_auth_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/auth_session.dart';

class AuthRepository {
  AuthRepository(this._firebaseAuth, this._storage);

  final FirebaseAuthService _firebaseAuth;
  final SecureStorageService _storage;

  Future<void> requestOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerify,
  }) =>
      _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phone,
        onCodeSent: onCodeSent,
        onError: onError,
        onAutoVerify: onAutoVerify,
      );

  Future<AuthSession> verifyOtp({
    required String phone,
    required String verificationId,
    required String code,
  }) async {
    final userCredential = await _firebaseAuth.verifyOtp(
      verificationId: verificationId,
      smsCode: code,
    );
    return _sessionFromUser(userCredential.user!, phone);
  }

  Future<AuthSession> signInWithCredential({
    required String phone,
    required PhoneAuthCredential credential,
  }) async {
    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    return _sessionFromUser(userCredential.user!, phone);
  }

  Future<AuthSession?> getStoredSession() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      final phone =
          await _storage.getUserPhone() ?? firebaseUser.phoneNumber ?? '';
      final expiry = await _storage.getTokenExpiry() ??
          DateTime.now().add(const Duration(days: 30));
      final token = await _storage.getToken() ?? '';
      return AuthSession(
        userId: firebaseUser.uid,
        firebaseUid: firebaseUser.uid,
        phone: phone,
        token: token,
        expiresAt: expiry,
      );
    }

    // Fallback: SecureStorage (offline / cold boot before Firebase refreshes)
    final token = await _storage.getToken();
    if (token == null || token.isEmpty) return null;
    final userId = await _storage.getUserId();
    final phone = await _storage.getUserPhone();
    final expiry = await _storage.getTokenExpiry();
    if (userId == null || phone == null || expiry == null) return null;
    if (!expiry.isAfter(DateTime.now())) return null;

    final uid = await _storage.getFirebaseUid();
    return AuthSession(
      userId: userId,
      firebaseUid: uid,
      phone: phone,
      token: token,
      expiresAt: expiry,
    );
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    await _storage.clearAll();
  }

  Future<AuthSession> _sessionFromUser(User user, String phone) async {
    final idToken = await user.getIdToken() ?? '';
    final session = AuthSession(
      userId: user.uid,
      firebaseUid: user.uid,
      phone: phone,
      token: idToken,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    await _persistSession(session);
    return session;
  }

  Future<void> _persistSession(AuthSession session) async {
    await Future.wait([
      _storage.saveToken(session.token),
      _storage.saveUserId(session.userId),
      _storage.saveUserPhone(session.phone),
      _storage.saveTokenExpiry(session.expiresAt),
      if (session.firebaseUid != null)
        _storage.saveFirebaseUid(session.firebaseUid!),
    ]);
  }
}
