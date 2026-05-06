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
  }) => ref
      .read(authRepositoryProvider)
      .requestOtp(
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
    final session = await ref
        .read(authRepositoryProvider)
        .verifyOtp(phone: phone, verificationId: verificationId, code: code);
    state = AsyncData(session);
    return session;
  }

  Future<AuthSession> signInWithCredential({
    required String phone,
    required PhoneAuthCredential credential,
  }) async {
    state = const AsyncLoading();
    final session = await ref
        .read(authRepositoryProvider)
        .signInWithCredential(phone: phone, credential: credential);
    state = AsyncData(session);
    return session;
  }

  Future<AuthSession> updateMerchantName(String merchantName) async {
    final currentSession = state.valueOrNull;
    if (currentSession != null) {
      state = AsyncData(currentSession.copyWith(merchantName: merchantName));
    } else {
      state = const AsyncLoading();
    }

    try {
      final session = await ref
          .read(authRepositoryProvider)
          .updateMerchantName(merchantName);
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      if (currentSession != null) {
        state = AsyncData(currentSession);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    }
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

final activeMerchantIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    return null;
  }
  return session.resolvedMerchantId;
});

final activeAppUserIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    return null;
  }
  return session.resolvedAppUserId;
});

final activeDeviceIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    return null;
  }
  return session.deviceId;
});
