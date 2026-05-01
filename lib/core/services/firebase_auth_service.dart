import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;
  int? _resendToken;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerify,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) {
          onAutoVerify?.call(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (kDebugMode) debugPrint('FirebaseAuth error: ${e.code}');
          onError(_mapAuthError(e.code));
        },
        codeSent: (String verificationId, int? resendToken) {
          _resendToken = resendToken;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
        forceResendingToken: _resendToken,
      );
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint('FirebaseAuth verifyPhoneNumber error: ${e.code}');
      onError(_mapAuthError(e.code));
    } catch (e) {
      onError('Erro ao enviar código. Tente novamente.');
    }
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) =>
      _auth.signInWithCredential(credential);

  Future<void> signOut() => _auth.signOut();

  String _mapAuthError(String code) => switch (code) {
        'invalid-phone-number' => 'Número de telemóvel inválido.',
        'too-many-requests' => 'Demasiadas tentativas. Tente mais tarde.',
        'quota-exceeded' => 'Quota de SMS excedida.',
         'operation-not-allowed' => 'O login por telemóvel não está ativado no Firebase.',
         'app-not-authorized' => 'Esta app Android não está autorizada no Firebase.',
         'invalid-app-credential' =>
             'A verificação da app falhou. Confirme a configuração do Android no Firebase.',
         'captcha-check-failed' =>
             'Falha na verificação reCAPTCHA. Em debug, reinstale a app; em produção, confirme a configuração do Firebase Phone Auth.',
        'invalid-verification-code' => 'Código de verificação inválido.',
        'session-expired' => 'Código expirado. Solicite um novo.',
        _ => 'Erro de autenticação. Tente novamente.',
      };
}
