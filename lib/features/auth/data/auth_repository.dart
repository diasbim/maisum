import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, SetOptions;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_runtime_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/storage/secure_storage.dart';
import 'backend_auth_api.dart';
import '../domain/auth_session.dart';

class AuthRepository {
  AuthRepository(
    this._firebaseAuth,
    this._storage,
    this._database, {
    this.config = const AppRuntimeConfig(),
    BackendAuthApi? backendAuthApi,
    FirebaseFirestore? firestore,
  })  : _backendAuthApi = backendAuthApi,
        _firestore = firestore;

  static const _uuid = Uuid();
  static const _defaultMerchantName = 'Minha Loja';
  static const _defaultSubscriptionStatus = 'TRIAL';

  final FirebaseAuthService _firebaseAuth;
  final SecureStorageService _storage;
  final AppDatabase _database;
  final AppRuntimeConfig config;
  final BackendAuthApi? _backendAuthApi;
  final FirebaseFirestore? _firestore;

  Future<void> requestOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerify,
  }) =>
      _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phone,
        onCodeSent: onCodeSent,
        onError: onError,
        onAutoVerify: onAutoVerify,
      );

  Future<AuthSession> verifyOtp({
    required String phone,
    required String verificationId,
    required String code,
  }) async {
    final userCredential = await _firebaseAuth.verifyOtp(
      verificationId: verificationId,
      smsCode: code,
    );
    return _sessionFromUser(userCredential.user!, phone);
  }

  Future<AuthSession> signInWithCredential({
    required String phone,
    required PhoneAuthCredential credential,
  }) async {
    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    return _sessionFromUser(userCredential.user!, phone);
  }

  Future<AuthSession?> getStoredSession() async {
    final storedSession = await _readStoredSession();
    if (storedSession != null) {
      final backendSession = await _tryRestoreBackendSession(storedSession);
      if (backendSession != null) {
        await _persistSession(backendSession);
        return backendSession;
      }

      if (storedSession.isValid) {
        await _ensureLocalIdentity(storedSession);
        return storedSession;
      }
    }

    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      final storedAppUserId = storedSession?.appUserId;
      final storedMerchantId = storedSession?.merchantId;
      final storedMerchantName = storedSession?.merchantName;
      final storedSubscriptionStatus = storedSession?.subscriptionStatus;
      final storedRefreshToken = storedSession?.refreshToken;
      final storedDeviceId = storedSession?.deviceId;
      final storedFirebaseUid = storedSession?.firebaseUid;
      final phone =
          await _storage.getUserPhone() ?? firebaseUser.phoneNumber ?? '';
      final deviceId = await _getOrCreateDeviceId();

      String token;
      DateTime expiry;
      try {
        final result = await firebaseUser.getIdTokenResult();
        token = result.token ?? '';
        expiry = result.expirationTime ??
            DateTime.now().add(const Duration(hours: 1));
        // Persist the refreshed token immediately so offline boots use it.
        await _persistSession(
          AuthSession(
            userId: firebaseUser.uid,
            appUserId: storedAppUserId ?? firebaseUser.uid,
            merchantId: storedMerchantId ?? firebaseUser.uid,
            merchantName: storedMerchantName ?? _defaultMerchantName,
            subscriptionStatus:
                storedSubscriptionStatus ?? _defaultSubscriptionStatus,
            refreshToken: storedRefreshToken,
            deviceId: storedDeviceId ?? deviceId,
            firebaseUid: firebaseUser.uid,
            phone: phone,
            token: token,
            expiresAt: expiry,
          ),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-disabled' || e.code == 'user-not-found') {
          await logout();
          return null;
        }
        // Transient network failure — fall back to stored token.
        token = await _storage.getToken() ?? '';
        expiry = await _storage.getTokenExpiry() ??
            DateTime.now().add(const Duration(hours: 1));
      } catch (_) {
        token = await _storage.getToken() ?? '';
        expiry = await _storage.getTokenExpiry() ??
            DateTime.now().add(const Duration(hours: 1));
      }

      final session = AuthSession(
        userId: firebaseUser.uid,
        appUserId: storedAppUserId ?? firebaseUser.uid,
        merchantId: storedMerchantId ?? storedFirebaseUid ?? firebaseUser.uid,
        merchantName: storedMerchantName ?? _defaultMerchantName,
        subscriptionStatus:
            storedSubscriptionStatus ?? _defaultSubscriptionStatus,
        refreshToken: storedRefreshToken,
        deviceId: storedDeviceId ?? deviceId,
        firebaseUid: firebaseUser.uid,
        phone: phone,
        token: token,
        expiresAt: expiry,
      );
      await _ensureLocalIdentity(session);
      return session;
    }

    return null;
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    await _storage.clearAll();
  }

  Future<AuthSession> updateMerchantName(String merchantName) async {
    final normalizedName = merchantName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(merchantName, 'merchantName');
    }

    final session = await _readStoredSession();
    if (session == null) {
      throw StateError('No active session available');
    }

    final updatedSession = session.copyWith(merchantName: normalizedName);
    await _persistSession(updatedSession);
    await _syncMerchantDocument(updatedSession);
    return updatedSession;
  }

  Future<AuthSession> _sessionFromUser(User user, String phone) async {
    final deviceId = await _getOrCreateDeviceId();
    final idToken = await user.getIdToken() ?? '';
    final backendAuthApi = _backendAuthApi;
    if (config.enableBackendAuth && backendAuthApi != null) {
      try {
        final backendSession = await backendAuthApi.exchangeFirebaseSession(
          firebaseIdToken: idToken,
          phone: phone,
          deviceId: deviceId,
        );
        final session = backendSession.toAuthSession(
          fallbackFirebaseUid: user.uid,
          fallbackDeviceId: deviceId,
        );
        await _persistSession(session);
        return session;
      } catch (_) {
        // Keep the current Firebase-local path active until backend auth is enabled in production.
      }
    }

    final session = AuthSession(
      userId: user.uid,
      appUserId: user.uid,
      merchantId: user.uid,
      merchantName: _defaultMerchantName,
      subscriptionStatus: _defaultSubscriptionStatus,
      deviceId: deviceId,
      firebaseUid: user.uid,
      phone: phone,
      token: idToken,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    await _persistSession(session);
    return session;
  }

  Future<AuthSession?> _readStoredSession() async {
    final storedToken = await _storage.getToken();
    final storedUserId = await _storage.getUserId();
    final storedAppUserId = await _storage.getAppUserId();
    final storedPhone = await _storage.getUserPhone();
    final storedMerchantId = await _storage.getMerchantId();
    final storedMerchantName = await _storage.getMerchantName();
    final storedSubscriptionStatus = await _storage.getSubscriptionStatus();
    final storedRefreshToken = await _storage.getRefreshToken();
    final storedDeviceId = await _storage.getDeviceId();
    final storedExpiry = await _storage.getTokenExpiry();
    final storedFirebaseUid = await _storage.getFirebaseUid();

    if (storedToken == null ||
        storedToken.isEmpty ||
        storedUserId == null ||
        storedPhone == null ||
        storedExpiry == null) {
      return null;
    }

    return AuthSession(
      userId: storedUserId,
      appUserId: storedAppUserId ?? storedUserId,
      merchantId: storedMerchantId ?? storedFirebaseUid ?? storedUserId,
      merchantName: storedMerchantName ?? _defaultMerchantName,
      subscriptionStatus:
          storedSubscriptionStatus ?? _defaultSubscriptionStatus,
      refreshToken: storedRefreshToken,
      deviceId: storedDeviceId,
      firebaseUid: storedFirebaseUid,
      phone: storedPhone,
      token: storedToken,
      expiresAt: storedExpiry,
    );
  }

  Future<AuthSession?> _tryRestoreBackendSession(
    AuthSession storedSession,
  ) async {
    final backendAuthApi = _backendAuthApi;
    if (!config.enableBackendAuth || backendAuthApi == null) {
      return null;
    }

    try {
      if (storedSession.isValid) {
        final restored = await backendAuthApi.restoreSession(
          accessToken: storedSession.token,
          deviceId: storedSession.deviceId,
        );
        return restored.toAuthSession(
          fallbackFirebaseUid: storedSession.firebaseUid,
          fallbackDeviceId: storedSession.deviceId,
        );
      }

      final refreshToken = storedSession.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final refreshed = await backendAuthApi.refreshSession(
          refreshToken: refreshToken,
          deviceId: storedSession.deviceId,
        );
        return refreshed.toAuthSession(
          fallbackFirebaseUid: storedSession.firebaseUid,
          fallbackDeviceId: storedSession.deviceId,
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> _persistSession(AuthSession session) async {
    await Future.wait([
      _storage.saveToken(session.token),
      _storage.saveUserId(session.userId),
      _storage.saveAppUserId(session.resolvedAppUserId),
      _storage.saveUserPhone(session.phone),
      _storage.saveMerchantId(session.resolvedMerchantId),
      _storage.saveMerchantName(session.merchantName),
      _storage.saveSubscriptionStatus(session.subscriptionStatus),
      if (session.refreshToken != null)
        _storage.saveRefreshToken(session.refreshToken!),
      if (session.deviceId != null) _storage.saveDeviceId(session.deviceId!),
      _storage.saveTokenExpiry(session.expiresAt),
      if (session.firebaseUid != null)
        _storage.saveFirebaseUid(session.firebaseUid!),
    ]);
    await _ensureLocalIdentity(session);
    await _syncMerchantDocument(session);
  }

  Future<String> _getOrCreateDeviceId() async {
    final existingDeviceId = await _storage.getDeviceId();
    if (existingDeviceId != null && existingDeviceId.isNotEmpty) {
      return existingDeviceId;
    }

    final deviceId = _uuid.v4();
    await _storage.saveDeviceId(deviceId);
    return deviceId;
  }

  Future<void> _ensureLocalIdentity(AuthSession session) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final merchantId = session.resolvedMerchantId;
    final merchantName = session.merchantName.trim().isEmpty
        ? _defaultMerchantName
        : session.merchantName.trim();
    final merchantPhone = session.phone.trim();
    final merchantSlug = _buildMerchantSlug(merchantPhone);

    await db.transaction((txn) async {
      await txn.insert(
          'merchants',
          {
            'id': merchantId,
            'phone': merchantPhone,
            'merchant_name': merchantName,
            'slug': merchantSlug,
            'subscription_status': session.subscriptionStatus,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.update(
        'merchants',
        {
          'phone': merchantPhone,
          'merchant_name': merchantName,
          'slug': merchantSlug,
          'subscription_status': session.subscriptionStatus,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [merchantId],
      );

      await txn.insert(
          'app_users',
          {
            'id': session.resolvedAppUserId,
            'merchant_id': merchantId,
            'phone': merchantPhone,
            'role': 'OWNER',
            'created_at': now,
            'updated_at': now,
            'last_login_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.update(
        'app_users',
        {
          'merchant_id': merchantId,
          'phone': merchantPhone,
          'updated_at': now,
          'last_login_at': now,
        },
        where: 'id = ?',
        whereArgs: [session.resolvedAppUserId],
      );

      await _backfillBusinessData(
        txn,
        merchantId: merchantId,
        deviceId: session.deviceId,
      );
    });
  }

  Future<void> _syncMerchantDocument(AuthSession session) async {
    final firestore = _firestore;
    if (firestore == null) {
      return;
    }

    final merchantId = session.resolvedMerchantId;
    final merchantName = session.merchantName.trim().isEmpty
        ? _defaultMerchantName
        : session.merchantName.trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    await firestore.collection('businesses').doc(merchantId).set({
      'id': merchantId,
      'merchant_name': merchantName,
      'phone': session.phone,
      'subscription_status': session.subscriptionStatus,
      'owner_user_id': session.resolvedAppUserId,
      'firebase_uid': session.firebaseUid,
      'device_id': session.deviceId,
      'updated_at': now,
      'created_at': now,
    }, SetOptions(merge: true));
  }

  Future<void> _backfillBusinessData(
    Transaction txn, {
    required String merchantId,
    required String? deviceId,
  }) async {
    await txn.update(
      'customers',
      {'merchant_id': merchantId},
      where: 'merchant_id IS NULL OR merchant_id = ?',
      whereArgs: [''],
    );
    await txn.update(
      'sales',
      {'merchant_id': merchantId, if (deviceId != null) 'device_id': deviceId},
      where: deviceId == null
          ? 'merchant_id IS NULL OR merchant_id = ?'
          : '(merchant_id IS NULL OR merchant_id = ?) OR device_id IS NULL OR device_id = ?',
      whereArgs: deviceId == null ? [''] : ['', ''],
    );
    await txn.update(
      'rewards',
      {'merchant_id': merchantId},
      where: 'merchant_id IS NULL OR merchant_id = ?',
      whereArgs: [''],
    );
    await txn.update(
      'redemptions',
      {'merchant_id': merchantId},
      where: 'merchant_id IS NULL OR merchant_id = ?',
      whereArgs: [''],
    );
    await txn.update(
      'sync_queue',
      {'merchant_id': merchantId, if (deviceId != null) 'device_id': deviceId},
      where: deviceId == null
          ? 'merchant_id IS NULL OR merchant_id = ?'
          : '(merchant_id IS NULL OR merchant_id = ?) OR device_id IS NULL OR device_id = ?',
      whereArgs: deviceId == null ? [''] : ['', ''],
    );

    final syncRows = await txn.query(
      'sync_queue',
      columns: ['id', 'payload'],
      where: 'merchant_id = ?',
      whereArgs: [merchantId],
    );

    for (final row in syncRows) {
      final payload = row['payload'] as String?;
      if (payload == null || payload.isEmpty) {
        continue;
      }

      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }

      decoded['merchant_id'] = merchantId;
      if (deviceId != null) {
        decoded['device_id'] = deviceId;
      }

      await txn.update(
        'sync_queue',
        {'payload': jsonEncode(decoded)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  String _buildMerchantSlug(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return 'merchant_unknown';
    }
    return 'merchant_$digits';
  }
}
