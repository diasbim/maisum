class AppConstants {
  static const int pointsPerMzn = 100;
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.loyaltyos.com/v1',
  );
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const int maxSyncRetries = 3;
  static const Duration syncRetryDelay = Duration(milliseconds: 500);
  static const String dbName = 'loyaltyos.db';
  static const int dbVersion = 5;
  static const int syncPullPageSize = 200;
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String userPhoneKey = 'user_phone';
  static const String tokenExpiryKey = 'token_expiry';
  static const String firebaseUidKey = 'firebase_uid';
  static const String pinKey = 'user_pin';
  static const String pinAttemptsKey = 'pin_attempts';
  static const int maxPinAttempts = 3;
  static const int pinLength = 4;
}
