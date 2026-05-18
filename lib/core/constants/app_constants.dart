class AppConstants {
  static const int pointsPerMzn = 100;
  static const int salePointsBaseMzn = 100;
  static const List<int> saleQuickAmounts = [100, 200, 500, 1000];
  static const int minSalePhoneDigitsForNewCustomer = 7;
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.loyaltyos.com/v1',
  );
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const int maxSyncRetries = 3;
  static const Duration syncRetryDelay = Duration(milliseconds: 500);
  static const String dbName = 'loyaltyos.db';
  static const int dbVersion = 14;
  static const int syncPullPageSize = 200;
  static const bool enableBackendAuth = bool.fromEnvironment(
    'ENABLE_BACKEND_AUTH',
    defaultValue: false,
  );
  static const String syncTransport = String.fromEnvironment(
    'SYNC_TRANSPORT',
    defaultValue: syncTransportFirestore,
  );
  static const String syncTransportFirestore = 'firestore';
  static const String syncTransportBackend = 'backend';
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String appUserIdKey = 'app_user_id';
  static const String userPhoneKey = 'user_phone';
  static const String merchantIdKey = 'merchant_id';
  static const String merchantNameKey = 'merchant_name';
  static const String subscriptionStatusKey = 'subscription_status';
  static const String refreshTokenKey = 'refresh_token';
  static const String deviceIdKey = 'device_id';
  static const String tokenExpiryKey = 'token_expiry';
  static const String firebaseUidKey = 'firebase_uid';
  static const String pinKey = 'user_pin';
  static const String pinAttemptsKey = 'pin_attempts';
  static const String smsPermissionPromptedKey = 'sms_permission_prompted';
  static const int maxPinAttempts = 3;
  static const int pinLength = 4;
}
