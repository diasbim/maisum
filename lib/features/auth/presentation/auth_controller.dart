import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/auth_session.dart';

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final session = await ref.read(authRepositoryProvider).getStoredSession();
    if (session != null && session.isValid) return session;
    return null;
  }

  Future<void> requestOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerify,
  }) =>
      ref.read(authRepositoryProvider).requestOtp(
            phone: phone,
            onCodeSent: onCodeSent,
            onError: onError,
            onAutoVerify: onAutoVerify,
          );

  Future<AuthSession> verifyOtp({
    required String phone,
    required String verificationId,
    required String code,
  }) async {
    state = const AsyncLoading();
    final session = await ref.read(authRepositoryProvider).verifyOtp(
          phone: phone,
          verificationId: verificationId,
          code: code,
        );
    state = AsyncData(session);
    return session;
  }

  Future<AuthSession> signInWithCredential({
    required String phone,
    required PhoneAuthCredential credential,
  }) async {
    state = const AsyncLoading();
    final session =
        await ref.read(authRepositoryProvider).signInWithCredential(
              phone: phone,
              credential: credential,
            );
    state = AsyncData(session);
    return session;
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    await ref.read(secureStorageServiceProvider).clearPin();
    await ref.read(secureStorageServiceProvider).clearPinAttempts();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
