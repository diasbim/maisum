import 'package:firebase_auth/firebase_auth.dart';

import '../errors/app_error_reporter.dart';
import '../errors/app_exception.dart';

class FirebaseAuthService {
  FirebaseAuthService(this._auth);

  static const _tag = 'FirebaseAuthService';

  final FirebaseAuth _auth;
  int? _resendToken;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  /// [currentUser] right after process start can briefly read null even
  /// though a user is persisted: on native platforms the SDK still has to
  /// restore its saved sign-in state over a platform channel, and the
  /// getter answers before that finishes — `authStateChanges()` itself can
  /// also emit a transient null before the real restored user arrives.
  /// Session restore has to tell "really signed out" apart from "not
  /// finished restoring yet", so this waits (briefly, bounded) for the
  /// first non-null event instead of trusting an immediate `currentUser`
  /// read or the stream's first emission.
  Future<User?> waitForCurrentUser({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final immediate = _auth.currentUser;
    if (immediate != null) return immediate;
    try {
      return await _auth
          .authStateChanges()
          .firstWhere((user) => user != null, orElse: () => _auth.currentUser)
          .timeout(timeout, onTimeout: () => _auth.currentUser);
    } catch (_) {
      return _auth.currentUser;
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerify,
  }) async {
    try {
      _recordPhoneAuthStage('verification_started');
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) {
          _recordPhoneAuthStage('verification_auto_completed');
          onAutoVerify?.call(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          _recordPhoneAuthStage('verification_failed', errorCode: e.code);
          AppErrorReporter.report(
            e,
            StackTrace.current,
            hint: 'auth_phone_verification_failed:${e.code}',
          );
          onError(_mapAuthException(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _resendToken = resendToken;
          _recordPhoneAuthStage('code_sent');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _recordPhoneAuthStage('auto_retrieval_timeout');
        },
        forceResendingToken: _resendToken,
      );
    } on FirebaseAuthException catch (e) {
      _recordPhoneAuthStage('verification_exception', errorCode: e.code);
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_verify_phone_number:${e.code}',
      );
      onError(_mapAuthException(e));
    } catch (e, st) {
      _recordPhoneAuthStage('verification_exception', errorCode: 'unknown');
      AppErrorReporter.report(e, st, hint: 'auth_verify_phone_number_unknown');
      onError('Erro ao enviar código. Tente novamente.');
    }
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      _recordPhoneAuthStage('otp_verification_started');
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final result = await _auth.signInWithCredential(credential);
      _recordPhoneAuthStage('otp_verification_succeeded');
      return result;
    } on FirebaseAuthException catch (e) {
      _recordPhoneAuthStage('otp_verification_failed', errorCode: e.code);
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_verify_otp:${e.code}',
      );
      throw AuthUiException(e, _mapAuthException(e));
    }
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    try {
      _recordPhoneAuthStage('automatic_sign_in_started');
      final result = await _auth.signInWithCredential(credential);
      _recordPhoneAuthStage('automatic_sign_in_succeeded');
      return result;
    } on FirebaseAuthException catch (e) {
      _recordPhoneAuthStage('automatic_sign_in_failed', errorCode: e.code);
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_sign_in_with_credential:${e.code}',
      );
      throw AuthUiException(e, _mapAuthException(e));
    }
  }

  // Codes Firebase/Google use when the user simply closes the account
  // picker or backs out of the consent screen. Never treat these as errors.
  static const _googleSignInCancelledCodes = {
    'web-context-cancelled',
    'cancelled-popup-request',
    'popup-closed-by-user',
    'canceled',
    'user-cancelled',
  };

  Future<UserCredential> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      return await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (_googleSignInCancelledCodes.contains(e.code)) {
        _recordPhoneAuthStage('google_sign_in_cancelled', errorCode: e.code);
        throw const GoogleSignInCancelledException();
      }
      AppErrorReporter.report(
        e,
        StackTrace.current,
        hint: 'auth_sign_in_with_google:${e.code}',
      );
      throw AuthUiException(e, _mapGoogleAuthError(e.code));
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'auth_sign_in_with_google_unknown');
      throw Exception('Não foi possível autenticar com o Google.');
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _mapAuthError(String code) => describeAuthCode(code);

  /// One Firebase code, in Portuguese.
  ///
  /// Static and public so `authErrorMessage` can reach it without an
  /// instance. One table, two callers: a second copy would drift, and the
  /// drift would show up as one screen explaining a failure while another
  /// says "tente novamente" about the same thing.
  static String describeAuthCode(String code) => switch (code) {
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
          'A configuração Android do Firebase está incompleta para autenticação por telemóvel.',
        'invalid-app-credential' =>
          'A verificação da app falhou. Confirme a configuração do Android no Firebase.',
        'captcha-check-failed' =>
          'Falha na verificação reCAPTCHA. Complete o desafio no Chrome e volte para a app.',
        'invalid-verification-code' => 'Código de verificação inválido.',
        'session-expired' => 'Código expirado. Solicite um novo.',
        'code-expired' => 'Código expirado. Solicite um novo.',
        // The verification session the code belongs to is gone — the app was
        // restarted, or the screen outlived the request that opened it. The
        // code on the person's phone is real and still cannot work, so the
        // message has to name the way out rather than suggest trying again.
        'invalid-verification-id' =>
          'A sessão de verificação expirou. Toque em "Reenviar código".',
        'missing-verification-id' =>
          'A sessão de verificação expirou. Toque em "Reenviar código".',
        'missing-verification-code' => 'Introduza o código completo.',
        'credential-already-in-use' =>
          'Este número já está associado a outra conta.',
        'user-disabled' => 'Conta desativada. Contacte o suporte.',
        _ => 'Erro de autenticação. Tente novamente.',
      };

  /// A Firebase failure, in words the person reading them can act on.
  ///
  /// This used to fall through to `e.message` for any code the table did not
  /// know, which put the SDK's own English sentence on screen in an app that
  /// is entirely in Portuguese. A real run hit it: an expired verification
  /// session produced "The verification ID used to create the phone auth
  /// credential is invalid." — true, untranslated, and useless to the person
  /// holding the phone.
  ///
  /// The code itself is not shown either. It is already on every report
  /// (`errorCode` on the stage record, and the `hint` on the reported
  /// exception), so support loses nothing and the screen gains a sentence
  /// instead of a machine string.
  String _mapAuthException(FirebaseAuthException e) => _mapAuthError(e.code);

  String _mapGoogleAuthError(String code) => switch (code) {
        'account-exists-with-different-credential' =>
          'Esta conta já existe com outro método de início de sessão.',
        'invalid-credential' => 'Credenciais do Google inválidas.',
        'operation-not-allowed' =>
          'O início de sessão com o Google não está ativado no Firebase.',
        'user-disabled' => 'Conta desativada. Contacte o suporte.',
        'network-request-failed' =>
          'Sem internet. Verifique a ligação e tente novamente.',
        _ => 'Não foi possível autenticar com o Google.',
      };

  void _recordPhoneAuthStage(String stage, {String? errorCode}) {
    AppErrorReporter.setCustomKey('phone_auth_stage', stage);
    AppErrorReporter.setCustomKey('phone_auth_error_code', errorCode ?? 'none');
    AppErrorReporter.breadcrumb(
      _tag,
      errorCode == null
          ? 'phone_auth:$stage'
          : 'phone_auth:$stage code=$errorCode',
    );
  }
}

/// An authentication failure already translated for display.
///
/// Public so a screen can ask whether a message is safe to show instead of
/// inferring it from the shape of `toString()`. Three screens used to print
/// `e.toString()` for whatever reached them: fine for this class, and a leak
/// for anything else — a `TimeoutException`, a `TypeError`, a plain `Error`
/// all stringify into something a person should never be shown.
class AuthUiException implements Exception {
  const AuthUiException(this.cause, this.message);

  final FirebaseAuthException cause;

  /// Portuguese, user-facing, and never the provider's own text.
  final String message;

  @override
  String toString() => message;
}

/// The fallback for a failure nobody mapped. Says what to do, not what broke.
const String kGenericAuthErrorMessage =
    'Não foi possível concluir. Tente novamente.';

/// Any error, reduced to something that can go on screen.
///
/// `AuthUiException` carries a message that was written for this purpose.
/// So does a bare `Exception('…')` thrown by the app's own code, which the
/// auth flow uses deliberately for its own Portuguese messages — that one is
/// recognised by its `Exception: ` prefix and unwrapped.
///
/// Everything else gets the generic sentence. That is the point: an error
/// this layer does not recognise is, by definition, one whose text nobody
/// wrote for a reader.
/// [fallback] replaces the generic sentence where the screen has a better one
/// — "introduza o código por SMS" tells a person what to do next, and only
/// the screen knows that.
String authErrorMessage(Object error, {String? fallback}) {
  final generic = fallback ?? kGenericAuthErrorMessage;

  if (error is AuthUiException) {
    final message = error.message.trim();
    return message.isEmpty ? generic : message;
  }
  if (error is FirebaseAuthException) {
    // Reached when a call site lets the raw exception through rather than
    // wrapping it. Mapped the same way, so the two paths cannot disagree.
    return FirebaseAuthService.describeAuthCode(error.code);
  }
  if (error is Exception) {
    final raw = error.toString().trim();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) {
      final message = raw.substring(prefix.length).trim();
      if (message.isNotEmpty) return message;
    }
  }
  return generic;
}
