import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';

enum PinVerificationStatus { success, invalid, blocked, unavailable }

class PinVerificationResult {
  const PinVerificationResult({
    required this.status,
    required this.attempts,
  });

  final PinVerificationStatus status;
  final int attempts;

  int get remainingAttempts => AppConstants.maxPinAttempts - attempts;
  bool get isSuccess => status == PinVerificationStatus.success;
  bool get isBlocked => status == PinVerificationStatus.blocked;
  bool get isInvalid => status == PinVerificationStatus.invalid;
}

class PinVerificationService {
  const PinVerificationService._();

  static Future<int> loadPersistedAttempts(
    SecureStorageService storage,
  ) {
    return storage.getPinAttempts();
  }

  static Future<PinVerificationResult> verifyPersistedPin({
    required SecureStorageService storage,
    required String input,
  }) async {
    final storedPin = await storage.getPin();
    if (storedPin == null || storedPin.isEmpty) {
      return const PinVerificationResult(
        status: PinVerificationStatus.unavailable,
        attempts: 0,
      );
    }

    if (storedPin == input) {
      await storage.clearPinAttempts();
      return const PinVerificationResult(
        status: PinVerificationStatus.success,
        attempts: 0,
      );
    }

    final attempts = await storage.getPinAttempts() + 1;
    await storage.savePinAttempts(attempts);

    return PinVerificationResult(
      status: attempts >= AppConstants.maxPinAttempts
          ? PinVerificationStatus.blocked
          : PinVerificationStatus.invalid,
      attempts: attempts,
    );
  }

  static Future<PinVerificationResult> verifyEphemeralPin({
    required SecureStorageService storage,
    required String input,
    required int currentAttempts,
  }) async {
    final storedPin = await storage.getPin();
    if (storedPin == null || storedPin.isEmpty) {
      return const PinVerificationResult(
        status: PinVerificationStatus.unavailable,
        attempts: 0,
      );
    }

    if (storedPin == input) {
      return const PinVerificationResult(
        status: PinVerificationStatus.success,
        attempts: 0,
      );
    }

    final attempts = currentAttempts + 1;
    return PinVerificationResult(
      status: attempts >= AppConstants.maxPinAttempts
          ? PinVerificationStatus.blocked
          : PinVerificationStatus.invalid,
      attempts: attempts,
    );
  }
}
