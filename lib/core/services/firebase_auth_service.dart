import 'package:firebase_auth/firebase_auth.dart';

import '../errors/app_error_reporter.dart';

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
          AppErrorReporter.report(
            e,
            StackTrace.current,
            hint: 'auth_phone_verification_failed:${e.code}',
          );
          onError(_mapAuthException(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _resendToken = resendToken;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
        forceResendingToken: _resendToken,
      );
    } on FirebaseAuthException catch (e) {
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_verify_phone_number:${e.code}',
      );
      onError(_mapAuthException(e));
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'auth_verify_phone_number_unknown');
      onError('Erro ao enviar código. Tente novamente.');
    }
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_verify_otp:${e.code}',
      );
      throw Exception(_mapAuthException(e));
    }
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    try {
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_sign_in_with_credential:${e.code}',
      );
      throw Exception(_mapAuthException(e));
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      return _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_sign_in_with_google:${e.code}',
      );
      throw Exception(_mapGoogleAuthError(e.code));
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'auth_sign_in_with_google_unknown');
      throw Exception('Nao foi possivel autenticar com Google.');
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _mapAuthError(String code) => switch (code) {
        'invalid-phone-number' => 'Número de telemóvel inválido.',
        'too-many-requests' => 'Demasiadas tentativas. Tente mais tarde.',
        'quota-exceeded' => 'Quota de SMS excedida.',
        'network-request-failed' =>
          'Sem internet. Verifique a ligação e tente novamente.',
        'operation-not-allowed' =>
          'O login por telemóvel não está ativado no Firebase.',
        'app-not-authorized' =>
          'Esta app Android não está autorizada no Firebase.',
        'missing-client-identifier' =>
          'A configuração Android do Firebase está incompleta para autenticação por telefone.',
        'invalid-app-credential' =>
          'A verificação da app falhou. Confirme a configuração do Android no Firebase.',
        'captcha-check-failed' =>
          'Falha na verificação reCAPTCHA. Complete o desafio no Chrome e volte para a app.',
        'invalid-verification-code' => 'Código de verificação inválido.',
        'session-expired' => 'Código expirado. Solicite um novo.',
        _ => 'Erro de autenticação. Tente novamente.',
      };

  String _mapAuthException(FirebaseAuthException e) {
    final mapped = _mapAuthError(e.code);
    if (mapped != 'Erro de autenticação. Tente novamente.') {
      return mapped;
    }

    final detail = (e.message ?? '').trim();
    if (detail.isNotEmpty) {
      return detail;
    }

    return 'Erro de autenticação (${e.code}). Tente novamente.';
  }

  String _mapGoogleAuthError(String code) => switch (code) {
        'account-exists-with-different-credential' =>
          'Esta conta ja existe com outro metodo de login.',
        'invalid-credential' => 'Credenciais Google invalidas.',
        'operation-not-allowed' => 'Login Google nao esta ativado no Firebase.',
        'user-disabled' => 'Conta desativada. Contacte o suporte.',
        'network-request-failed' =>
          'Sem internet. Verifique a ligacao e tente novamente.',
        'web-context-cancelled' => 'Login cancelado.',
        _ => 'Nao foi possivel autenticar com Google.',
      };
}
