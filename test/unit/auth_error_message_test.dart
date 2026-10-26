import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/services/firebase_auth_service.dart';

/// The rule these tests exist for: nothing the provider wrote ever reaches a
/// screen. A real run of the app put "The verification ID used to create the
/// phone auth credential is invalid." in front of a Portuguese-speaking user,
/// because the mapper fell through to `e.message` for any code it did not
/// know.
void main() {
  group('authErrorMessage', () {
    test('never returns the provider own English text', () {
      const english = 'The verification ID used to create the phone auth '
          'credential is invalid.';
      final message = authErrorMessage(
        FirebaseAuthException(code: 'invalid-verification-id', message: english),
      );
      expect(message, isNot(contains('verification ID')));
      expect(message, isNot(equals(english)));
    });

    test('an expired session names the way out', () {
      // The code on the person phone is real and still cannot work. Telling
      // them to try again sends them round a loop that cannot end.
      for (final code in ['invalid-verification-id', 'missing-verification-id']) {
        final message = authErrorMessage(FirebaseAuthException(code: code));
        expect(message, contains('Reenviar'));
      }
    });

    test('a wrong code and an expired code read differently', () {
      // Retyping helps for one and never for the other.
      final wrong =
          authErrorMessage(FirebaseAuthException(code: 'invalid-verification-code'));
      final expired = authErrorMessage(FirebaseAuthException(code: 'session-expired'));
      expect(wrong, isNot(equals(expired)));
    });

    test('an unmapped code still answers in Portuguese, without the code', () {
      final message = authErrorMessage(
        FirebaseAuthException(code: 'some-code-nobody-mapped', message: 'Raw SDK text'),
      );
      expect(message, isNot(contains('some-code-nobody-mapped')));
      expect(message, isNot(contains('Raw SDK')));
      expect(message, equals('Erro de autenticação. Tente novamente.'));
    });

    test('a wrapped exception shows the message written for it', () {
      final wrapped = AuthUiException(
        FirebaseAuthException(code: 'invalid-verification-code'),
        'Código de verificação inválido.',
      );
      expect(authErrorMessage(wrapped), 'Código de verificação inválido.');
    });

    test('an empty wrapped message falls back rather than showing nothing', () {
      final wrapped =
          AuthUiException(FirebaseAuthException(code: 'x'), '   ');
      expect(authErrorMessage(wrapped), kGenericAuthErrorMessage);
    });

    test('the app own thrown message is kept, without the Dart prefix', () {
      // The auth flow throws Exception('…') with Portuguese text on purpose.
      expect(
        authErrorMessage(Exception('Este número pertence a outra conta.')),
        'Este número pertence a outra conta.',
      );
    });

    test('an error nobody wrote for a reader is never shown', () {
      // These stringify into something no person should meet. Before the fix
      // all three went straight to the snackbar.
      expect(authErrorMessage(StateError('Bad state: no element')),
          kGenericAuthErrorMessage);
      expect(authErrorMessage(ArgumentError('invalid')), kGenericAuthErrorMessage);
      expect(authErrorMessage(TypeError()), kGenericAuthErrorMessage);
      expect(authErrorMessage('a bare string'), kGenericAuthErrorMessage);
    });

    test('a screen own fallback replaces the generic one', () {
      const better = 'Introduza o código por SMS.';
      expect(
        authErrorMessage(StateError('boom'), fallback: better),
        better,
      );
    });

    test('a fallback does not override a message that exists', () {
      expect(
        authErrorMessage(
          FirebaseAuthException(code: 'invalid-verification-code'),
          fallback: 'nunca mostrado',
        ),
        'Código de verificação inválido.',
      );
    });
  });

  group('describeAuthCode', () {
    test('every mapped code answers in Portuguese and ends in a full stop', () {
      const codes = [
        'invalid-phone-number',
        'too-many-requests',
        'quota-exceeded',
        'network-request-failed',
        'invalid-verification-code',
        'session-expired',
        'code-expired',
        'invalid-verification-id',
        'missing-verification-id',
        'missing-verification-code',
        'credential-already-in-use',
        'user-disabled',
      ];
      for (final code in codes) {
        final message = FirebaseAuthService.describeAuthCode(code);
        expect(message, isNotEmpty, reason: code);
        expect(message.endsWith('.') || message.endsWith('".'), isTrue,
            reason: '$code -> $message');
        // No machine strings, and nothing left in English.
        expect(message, isNot(contains(code)), reason: code);
      }
    });

    test('the table and the wrapper cannot disagree', () {
      // One table, two callers: a second copy would drift, and the drift
      // would show as two screens explaining the same failure differently.
      for (final code in ['session-expired', 'too-many-requests']) {
        expect(
          authErrorMessage(FirebaseAuthException(code: code)),
          FirebaseAuthService.describeAuthCode(code),
        );
      }
    });
  });
}
