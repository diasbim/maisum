import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/constants/app_runtime_config.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/core/services/firebase_auth_service.dart';
import 'package:maisum/core/storage/secure_storage.dart';
import 'package:maisum/features/auth/data/auth_repository.dart';
import 'package:maisum/features/auth/data/backend_auth_api.dart';
import 'package:maisum/features/auth/domain/backend_bootstrap_session.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late _InMemorySecureStorageService storage;
  late AuthRepository repository;

  setUp(() async {
    db = await setUpTestDatabase();
    storage = _InMemorySecureStorageService();
    repository = AuthRepository(
      FirebaseAuthService(MockFirebaseAuth()),
      storage,
      AppDatabase.instance,
      config: const AppRuntimeConfig(enableBackendAuth: false),
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  group('AuthRepository.updateMerchantName', () {
    test('persists merchant name and updates merchants row', () async {
      await storage.seedSession(
        userId: 'user-1',
        appUserId: 'app-user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        subscriptionStatus: 'TRIAL',
        phone: '+258840000000',
        token: 'stored-token',
        refreshToken: 'refresh-token',
        deviceId: 'device-1',
        firebaseUid: 'firebase-1',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );

      final session = await repository.updateMerchantName('Loja Nova');

      expect(session.merchantName, 'Loja Nova');
      expect(await storage.getMerchantName(), 'Loja Nova');

      final rows = await db.query(
        'merchants',
        where: 'id = ?',
        whereArgs: ['merchant-1'],
      );

      expect(rows, hasLength(1));
      expect(rows.first['merchant_name'], 'Loja Nova');
      expect(rows.first['phone'], '+258840000000');
      expect(rows.first['subscription_status'], 'TRIAL');
    });
  });

  group('AuthRepository.getStoredSession', () {
    test(
      'restores backend session when runtime config enables backend auth',
      () async {
        await storage.seedSession(
          userId: 'user-1',
          appUserId: 'app-user-1',
          merchantId: 'merchant-1',
          merchantName: 'Minha Loja',
          subscriptionStatus: 'TRIAL',
          phone: '+258840000000',
          token: 'stored-token',
          refreshToken: 'refresh-token',
          deviceId: 'device-1',
          firebaseUid: 'firebase-1',
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        );

        final backendAuthApi = _FakeBackendAuthApi(
          restoreResult: BackendBootstrapSession(
            userId: 'user-1',
            appUserId: 'app-user-1',
            merchantId: 'merchant-1',
            merchantName: 'Loja Restaurada',
            phone: '+258840000000',
            accessToken: 'restored-token',
            refreshToken: 'restored-refresh',
            deviceId: 'device-1',
            firebaseUid: 'firebase-1',
            subscriptionStatus: 'ACTIVE_PAID',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
          ),
        );
        final repository = AuthRepository(
          FirebaseAuthService(MockFirebaseAuth()),
          storage,
          AppDatabase.instance,
          config: const AppRuntimeConfig(enableBackendAuth: true),
          backendAuthApi: backendAuthApi,
        );

        final session = await repository.getStoredSession();

        expect(session, isNotNull);
        expect(backendAuthApi.restoreCalls, 1);
        expect(backendAuthApi.refreshCalls, 0);
        expect(session!.merchantName, 'Loja Restaurada');
        expect(session.subscriptionStatus, 'ACTIVE_PAID');
        expect(session.token, 'restored-token');
        expect(await storage.getToken(), 'restored-token');
        expect(await storage.getMerchantName(), 'Loja Restaurada');
      },
    );

    test(
      'refreshes backend session when stored access token is expired',
      () async {
        await storage.seedSession(
          userId: 'user-1',
          appUserId: 'app-user-1',
          merchantId: 'merchant-1',
          merchantName: 'Minha Loja',
          subscriptionStatus: 'TRIAL',
          phone: '+258840000000',
          token: 'expired-token',
          refreshToken: 'refresh-token',
          deviceId: 'device-1',
          firebaseUid: 'firebase-1',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        final backendAuthApi = _FakeBackendAuthApi(
          refreshResult: BackendBootstrapSession(
            userId: 'user-1',
            appUserId: 'app-user-1',
            merchantId: 'merchant-1',
            merchantName: 'Loja Atualizada',
            phone: '+258840000000',
            accessToken: 'fresh-token',
            refreshToken: 'fresh-refresh-token',
            deviceId: 'device-1',
            firebaseUid: 'firebase-1',
            subscriptionStatus: 'ACTIVE_PAID',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
          ),
        );
        final repository = AuthRepository(
          FirebaseAuthService(MockFirebaseAuth()),
          storage,
          AppDatabase.instance,
          config: const AppRuntimeConfig(enableBackendAuth: true),
          backendAuthApi: backendAuthApi,
        );

        final session = await repository.getStoredSession();

        expect(session, isNotNull);
        expect(backendAuthApi.restoreCalls, 0);
        expect(backendAuthApi.refreshCalls, 1);
        expect(session!.token, 'fresh-token');
        expect(session.refreshToken, 'fresh-refresh-token');
        expect(await storage.getToken(), 'fresh-token');
        expect(await storage.getRefreshToken(), 'fresh-refresh-token');
      },
    );
  });
}

class _FakeBackendAuthApi extends BackendAuthApi {
  _FakeBackendAuthApi({this.restoreResult, this.refreshResult})
      : super(JsonApiClient(baseUrl: 'https://example.test'));

  final BackendBootstrapSession? restoreResult;
  final BackendBootstrapSession? refreshResult;

  int restoreCalls = 0;
  int refreshCalls = 0;

  @override
  Future<BackendBootstrapSession> restoreSession({
    required String accessToken,
    String? deviceId,
  }) async {
    restoreCalls += 1;
    if (restoreResult == null) {
      throw StateError('restoreResult not configured');
    }
    return restoreResult!;
  }

  @override
  Future<BackendBootstrapSession> refreshSession({
    required String refreshToken,
    String? deviceId,
  }) async {
    refreshCalls += 1;
    if (refreshResult == null) {
      throw StateError('refreshResult not configured');
    }
    return refreshResult!;
  }
}

class _InMemorySecureStorageService extends SecureStorageService {
  _InMemorySecureStorageService() : super(const FlutterSecureStorage());

  final Map<String, String> _store = <String, String>{};

  Future<void> seedSession({
    required String userId,
    required String appUserId,
    required String merchantId,
    required String merchantName,
    required String subscriptionStatus,
    required String phone,
    required String token,
    required DateTime expiresAt,
    String? refreshToken,
    String? deviceId,
    String? firebaseUid,
  }) async {
    await saveUserId(userId);
    await saveAppUserId(appUserId);
    await saveMerchantId(merchantId);
    await saveMerchantName(merchantName);
    await saveSubscriptionStatus(subscriptionStatus);
    await saveUserPhone(phone);
    await saveToken(token);
    await saveTokenExpiry(expiresAt);
    if (refreshToken != null) {
      await saveRefreshToken(refreshToken);
    }
    if (deviceId != null) {
      await saveDeviceId(deviceId);
    }
    if (firebaseUid != null) {
      await saveFirebaseUid(firebaseUid);
    }
  }

  @override
  Future<void> saveToken(String token) async => _store['token'] = token;

  @override
  Future<String?> getToken() async => _store['token'];

  @override
  Future<void> saveUserId(String userId) async => _store['user_id'] = userId;

  @override
  Future<String?> getUserId() async => _store['user_id'];

  @override
  Future<void> saveAppUserId(String userId) async =>
      _store['app_user_id'] = userId;

  @override
  Future<String?> getAppUserId() async => _store['app_user_id'];

  @override
  Future<void> saveUserPhone(String phone) async =>
      _store['user_phone'] = phone;

  @override
  Future<String?> getUserPhone() async => _store['user_phone'];

  @override
  Future<void> saveMerchantId(String merchantId) async =>
      _store['merchant_id'] = merchantId;

  @override
  Future<String?> getMerchantId() async => _store['merchant_id'];

  @override
  Future<void> saveMerchantName(String merchantName) async =>
      _store['merchant_name'] = merchantName;

  @override
  Future<String?> getMerchantName() async => _store['merchant_name'];

  @override
  Future<void> saveSubscriptionStatus(String status) async =>
      _store['subscription_status'] = status;

  @override
  Future<String?> getSubscriptionStatus() async =>
      _store['subscription_status'];

  @override
  Future<void> saveRefreshToken(String refreshToken) async =>
      _store['refresh_token'] = refreshToken;

  @override
  Future<String?> getRefreshToken() async => _store['refresh_token'];

  @override
  Future<void> saveDeviceId(String deviceId) async =>
      _store['device_id'] = deviceId;

  @override
  Future<String?> getDeviceId() async => _store['device_id'];

  @override
  Future<void> saveTokenExpiry(DateTime expiry) async {
    _store['token_expiry'] = expiry.millisecondsSinceEpoch.toString();
  }

  @override
  Future<DateTime?> getTokenExpiry() async {
    final raw = _store['token_expiry'];
    if (raw == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
  }

  @override
  Future<void> saveFirebaseUid(String uid) async =>
      _store['firebase_uid'] = uid;

  @override
  Future<String?> getFirebaseUid() async => _store['firebase_uid'];

  @override
  Future<void> clearAll() async => _store.clear();
}

