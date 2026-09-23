class AppConstants {
  static const int pointsPerMzn = 100;
  static const int salePointsBaseMzn = 100;
  static const List<int> saleQuickAmounts = [100, 200, 500, 1000];
  static const int minSalePhoneDigitsForNewCustomer = 7;
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.loyaltyos.com/v1',
  );
  static const String cloudFunctionsApiBaseUrl = String.fromEnvironment(
    'CLOUD_FUNCTIONS_API_BASE_URL',
    defaultValue: 'https://us-central1-loyaltyos-fc4dd.cloudfunctions.net/api',
  );
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const int maxSyncRetries = 3;
  static const Duration syncRetryDelay = Duration(milliseconds: 500);
  static const String dbName = 'loyaltyos.db';
  static const int dbVersion = 31;
  static const int syncPullPageSize = 200;
  static const bool enableBackendAuth = bool.fromEnvironment(
    'ENABLE_BACKEND_AUTH',
    defaultValue: false,
  );
  static const bool allowTestPhoneAuthBypass = bool.fromEnvironment(
    'ALLOW_TEST_PHONE_AUTH_BYPASS',
    defaultValue: false,
  );
  static const bool enableCrashlyticsInDebug = bool.fromEnvironment(
    'ENABLE_CRASHLYTICS_IN_DEBUG',
    defaultValue: false,
  );

  /// Points Auth, Firestore and Functions at the local emulator suite.
  ///
  /// Off unless asked for, and refused outside debug builds: a release that
  /// silently talked to 127.0.0.1 would be a broken app, and one that was
  /// meant to and did not would be writing to the real database.
  ///
  ///     flutter run --dart-define=USE_FIREBASE_EMULATORS=true
  ///
  /// The ports mirror `firebase.json`; the host is settable because an Android
  /// emulator reaches the host machine at 10.0.2.2 rather than at loopback.
  static const bool useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );
  static const String firebaseEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int firebaseAuthEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8085;
  static const int functionsEmulatorPort = 5099;
  static const String syncTransportFirestore = 'firestore';
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String appUserIdKey = 'app_user_id';
  static const String appUserRoleKey = 'app_user_role';
  static const String authActorKey = 'auth_actor';
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
  static const String onboardingPlanConfirmedKey = 'onboarding_plan_confirmed';
  static const String debugBypassPaidFeatureGateKey =
      'debug_bypass_paid_feature_gate';
  static const String appUserRoleOwner = 'OWNER';
  static const String appUserRoleStaff = 'STAFF';
  static const String appUserStatusActive = 'ACTIVE';
  static const String appUserStatusInvited = 'INVITED';
  static const String appUserStatusInactive = 'INACTIVE';
  static const int maxPinAttempts = 3;
  static const int pinLength = 4;
}
