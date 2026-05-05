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
    final storedToken = await _storage.getToken();
    final storedUserId = await _storage.getUserId();
    final storedPhone = await _storage.getUserPhone();
    final storedExpiry = await _storage.getTokenExpiry();
    final storedFirebaseUid = await _storage.getFirebaseUid();

    if (storedToken != null &&
        storedToken.isNotEmpty &&
        storedUserId != null &&
        storedPhone != null &&
        storedExpiry != null &&
        storedExpiry.isAfter(DateTime.now())) {
      return AuthSession(
        userId: storedUserId,
        firebaseUid: storedFirebaseUid,
        phone: storedPhone,
        token: storedToken,
        expiresAt: storedExpiry,
      );
    }

    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      final phone =
          await _storage.getUserPhone() ?? firebaseUser.phoneNumber ?? '';

      String token;
      DateTime expiry;
      try {
        final result = await firebaseUser.getIdTokenResult();
        token = result.token ?? '';
        expiry = result.expirationTime ??
            DateTime.now().add(const Duration(hours: 1));
        // Persist the refreshed token immediately so offline boots use it.
        await _persistSession(AuthSession(
          userId: firebaseUser.uid,
          firebaseUid: firebaseUser.uid,
          phone: phone,
          token: token,
          expiresAt: expiry,
        ));
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-disabled' || e.code == 'user-not-found') {
          await logout();
          return null;
        }
        // Transient network failure — fall back to stored token.
        token = await _storage.getToken() ?? '';
        expiry = await _storage.getTokenExpiry() ??
            DateTime.now().add(const Duration(hours: 1));
      } catch (_) {
        token = await _storage.getToken() ?? '';
        expiry = await _storage.getTokenExpiry() ??
            DateTime.now().add(const Duration(hours: 1));
      }

      return AuthSession(
        userId: firebaseUser.uid,
        firebaseUid: firebaseUser.uid,
        phone: phone,
        token: token,
        expiresAt: expiry,
      );
    }

    return null;
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
