import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_error_reporter.dart';
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
  }) async {
    try {
      await ref.read(authRepositoryProvider).requestOtp(
            phone: phone,
            onCodeSent: onCodeSent,
            onError: onError,
            onAutoVerify: onAutoVerify,
          );
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'auth_request_otp');
      rethrow;
    }
  }

  Future<AuthSession> verifyOtp({
    required String phone,
    required String verificationId,
    required String code,
  }) async {
    state = const AsyncLoading();
    try {
      final session = await ref.read(authRepositoryProvider).verifyOtp(
            phone: phone,
            verificationId: verificationId,
            code: code,
          );
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      AppErrorReporter.report(error, stackTrace, hint: 'auth_verify_otp');
      rethrow;
    }
  }

  Future<AuthSession> signInWithCredential({
    required String phone,
    required PhoneAuthCredential credential,
  }) async {
    state = const AsyncLoading();
    try {
      final session =
          await ref.read(authRepositoryProvider).signInWithCredential(
                phone: phone,
                credential: credential,
              );
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'auth_sign_in_with_credential',
      );
      rethrow;
    }
  }

  Future<AuthSession> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      final session = await ref.read(authRepositoryProvider).signInWithGoogle();
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'auth_sign_in_with_google',
      );
      rethrow;
    }
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
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'auth_update_merchant_name',
      );
      if (currentSession != null) {
        state = AsyncData(currentSession);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    }
  }

  Future<AuthSession> linkDeviceByCode(String linkCode) async {
    final currentSession = state.valueOrNull;
    state = const AsyncLoading();

    try {
      final session = await ref
          .read(authRepositoryProvider)
          .linkDeviceToMerchantByCode(linkCode: linkCode);
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'auth_link_device_by_code',
      );
      if (currentSession != null) {
        state = AsyncData(currentSession);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await ref.read(authRepositoryProvider).logout();
      await ref.read(secureStorageServiceProvider).clearPin();
      await ref.read(secureStorageServiceProvider).clearPinAttempts();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'auth_logout');
      rethrow;
    }
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

final activeAppUserRoleProvider = FutureProvider<String>((ref) async {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    return AppConstants.appUserRoleOwner;
  }
  final storedRole =
      await ref.read(secureStorageServiceProvider).getAppUserRole();
  final normalized = storedRole?.trim().toUpperCase();
  if (normalized == AppConstants.appUserRoleStaff) {
    return AppConstants.appUserRoleStaff;
  }
  return AppConstants.appUserRoleOwner;
});

final isOwnerUserProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(activeAppUserRoleProvider.future);
  return role == AppConstants.appUserRoleOwner;
});
