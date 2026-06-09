import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseException, FirebaseFirestore, SetOptions;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_runtime_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/moz_phone_utils.dart';
import 'backend_auth_api.dart';
import '../domain/auth_session.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/domain/plan_catalog.dart';
import '../../subscription/domain/usage_metrics.dart';

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
  static const _defaultAppUserRole = AppConstants.appUserRoleOwner;

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

  Future<AuthSession> signInWithGoogle() async {
    final userCredential = await _firebaseAuth.signInWithGoogle();
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Nao foi possivel autenticar com Google.');
    }
    final phone = (user.phoneNumber ?? '').trim();
    return _sessionFromUser(user, phone);
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
      final existingMerchant = await _findMerchantByPhone(phone);
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
            appUserId: storedAppUserId ??
                existingMerchant?.appUserId ??
                firebaseUser.uid,
            merchantId: storedMerchantId ??
                existingMerchant?.merchantId ??
                firebaseUser.uid,
            merchantName: storedMerchantName ??
                existingMerchant?.merchantName ??
                _defaultMerchantName,
            subscriptionStatus: storedSubscriptionStatus ??
                existingMerchant?.subscriptionStatus ??
                _defaultSubscriptionStatus,
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
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'auth_token_refresh');
        token = await _storage.getToken() ?? '';
        expiry = await _storage.getTokenExpiry() ??
            DateTime.now().add(const Duration(hours: 1));
      }

      final session = AuthSession(
        userId: firebaseUser.uid,
        appUserId:
            storedAppUserId ?? existingMerchant?.appUserId ?? firebaseUser.uid,
        merchantId: storedMerchantId ??
            existingMerchant?.merchantId ??
            storedFirebaseUid ??
            firebaseUser.uid,
        merchantName: storedMerchantName ??
            existingMerchant?.merchantName ??
            _defaultMerchantName,
        subscriptionStatus: storedSubscriptionStatus ??
            existingMerchant?.subscriptionStatus ??
            _defaultSubscriptionStatus,
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
    return updatedSession;
  }

  Future<AuthSession> linkDeviceToMerchantByCode({
    required String linkCode,
  }) async {
    final firestore = _firestore;
    if (firestore == null) {
      throw StateError('Vinculacao por codigo indisponivel neste ambiente.');
    }

    final normalizedCode = _normalizeLinkCode(linkCode);
    if (normalizedCode.isEmpty) {
      throw ArgumentError.value(linkCode, 'linkCode');
    }

    final currentSession =
        await _readStoredSession() ?? await getStoredSession();
    if (currentSession == null) {
      throw StateError('Sessao invalida para vincular dispositivo.');
    }

    final business = await _findMerchantByLinkCode(
      firestore,
      normalizedCode: normalizedCode,
      rawCode: linkCode.trim(),
    );

    if (business == null) {
      throw StateError('Codigo da barbearia invalido ou expirado.');
    }

    final merchantId = business.key;
    final data = business.value;
    final merchantName = ((data['merchant_name'] as String?) ?? '').trim();
    final ownerUserId = (data['owner_user_id'] as String?)?.trim();
    final ownerFirebaseUid = (data['firebase_uid'] as String?)?.trim();
    final subscriptionStatus =
        ((data['subscription_status'] as String?) ?? '').trim();

    final isOwnerSession = (ownerUserId != null &&
            ownerUserId.isNotEmpty &&
            ownerUserId == currentSession.resolvedAppUserId) ||
        (ownerFirebaseUid != null &&
            ownerFirebaseUid.isNotEmpty &&
            currentSession.firebaseUid != null &&
            ownerFirebaseUid == currentSession.firebaseUid);

    await _storage.saveAppUserRole(
      isOwnerSession
          ? AppConstants.appUserRoleOwner
          : AppConstants.appUserRoleStaff,
    );

    final linkedSession = currentSession.copyWith(
      merchantId: merchantId,
      merchantName:
          merchantName.isEmpty ? currentSession.merchantName : merchantName,
      subscriptionStatus: subscriptionStatus.isEmpty
          ? currentSession.subscriptionStatus
          : subscriptionStatus,
      appUserId: isOwnerSession && ownerUserId != null && ownerUserId.isNotEmpty
          ? ownerUserId
          : currentSession.resolvedAppUserId,
    );

    await _persistSession(linkedSession);
    await _storage.setOnboardingPlanConfirmed(true);
    return linkedSession;
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
      } catch (e, st) {
        // Keep the current Firebase-local path active until backend auth is enabled in production.
        AppErrorReporter.report(e, st, hint: 'auth_backend_exchange');
      }
    }

    final existingMerchant = await _findMerchantByPhone(phone);

    final session = AuthSession(
      userId: user.uid,
      appUserId: existingMerchant?.appUserId ?? user.uid,
      merchantId: existingMerchant?.merchantId ?? user.uid,
      merchantName: existingMerchant?.merchantName ?? _defaultMerchantName,
      subscriptionStatus:
          existingMerchant?.subscriptionStatus ?? _defaultSubscriptionStatus,
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
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'auth_backend_restore');
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
    await _syncStoredAppUserRole(session);
    final shouldSyncMerchantDocument = await _shouldSyncMerchantDocument();
    if (!shouldSyncMerchantDocument) {
      return;
    }
    try {
      await _syncMerchantDocument(session);
    } catch (e, st) {
      // Firestore sync is best-effort; local session/bootstrap must remain usable.
      AppErrorReporter.report(e, st, hint: 'auth_sync_merchant_document');
    }
  }

  Future<void> _syncStoredAppUserRole(AuthSession session) async {
    final db = await _database.database;
    final rows = await db.query(
      'app_users',
      columns: ['role'],
      where: 'id = ? AND merchant_id = ?',
      whereArgs: [session.resolvedAppUserId, session.resolvedMerchantId],
      limit: 1,
    );
    final role = rows.isEmpty ? null : rows.first['role'] as String?;
    final normalized = _normalizeAppUserRole(role);
    await _storage.saveAppUserRole(normalized ?? _defaultAppUserRole);
  }

  Future<bool> _shouldSyncMerchantDocument() async {
    final role = _normalizeAppUserRole(await _storage.getAppUserRole());
    // Staff users do not have permissions to update /businesses/{merchantId}.
    return role != AppConstants.appUserRoleStaff;
  }

  Future<_ExistingMerchantData?> _findMerchantByPhone(String rawPhone) async {
    final firestore = _firestore;
    if (firestore == null) {
      return null;
    }

    final candidates = _phoneCandidates(rawPhone);
    if (candidates.isEmpty) {
      return null;
    }

    for (final candidate in candidates) {
      try {
        final query = await firestore
            .collection('businesses')
            .where('phone', isEqualTo: candidate)
            .limit(1)
            .get();
        if (query.docs.isEmpty) {
          continue;
        }

        final doc = query.docs.first;
        final data = doc.data();
        final merchantName = (data['merchant_name'] as String?)?.trim();
        final appUserId = (data['owner_user_id'] as String?)?.trim();
        final subscriptionStatus =
            (data['subscription_status'] as String?)?.trim();

        return _ExistingMerchantData(
          merchantId: doc.id,
          merchantName: (merchantName == null || merchantName.isEmpty)
              ? _defaultMerchantName
              : merchantName,
          appUserId:
              (appUserId == null || appUserId.isEmpty) ? null : appUserId,
          subscriptionStatus:
              (subscriptionStatus == null || subscriptionStatus.isEmpty)
                  ? _defaultSubscriptionStatus
                  : subscriptionStatus,
        );
      } on FirebaseException catch (e, st) {
        // Discovery by phone is optional; keep auth flow running when Firestore blocks it.
        AppErrorReporter.report(
          e,
          st,
          hint: 'auth_find_merchant_by_phone:${e.code}',
        );
        return null;
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'auth_find_merchant_by_phone');
        return null;
      }
    }

    return null;
  }

  Future<MapEntry<String, Map<String, dynamic>>?> _findMerchantByLinkCode(
    FirebaseFirestore firestore, {
    required String normalizedCode,
    required String rawCode,
  }) async {
    var query = await firestore
        .collection('businesses')
        .where('link_code_normalized', isEqualTo: normalizedCode)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      return MapEntry(doc.id, doc.data());
    }

    if (rawCode.isNotEmpty) {
      query = await firestore
          .collection('businesses')
          .where('link_code', isEqualTo: rawCode)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        return MapEntry(doc.id, doc.data());
      }

      final directDoc =
          await firestore.collection('businesses').doc(rawCode).get();
      if (directDoc.exists) {
        return MapEntry(directDoc.id, directDoc.data() ?? <String, dynamic>{});
      }
    }

    return null;
  }

  List<String> _phoneCandidates(String rawPhone) {
    final input = rawPhone.trim();
    if (input.isEmpty) {
      return const [];
    }

    final candidates = <String>{input};
    try {
      final e164 = MozPhoneUtils.normalizeToE164(input);
      candidates.add(e164);
      candidates.add(MozPhoneUtils.normalizeToLocal(input));
    } catch (_) {
      // Keep raw input as fallback candidate when normalization fails.
    }
    return candidates.toList(growable: false);
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
    final planDefinition = PlanCatalog.fromCode('starter');
    final window = _monthlyWindow(DateTime.now());
    final storedRole = _normalizeAppUserRole(await _storage.getAppUserRole()) ??
        _defaultAppUserRole;
    var resolvedRole = storedRole;

    await db.transaction((txn) async {
      final existingUser = await txn.query(
        'app_users',
        columns: ['role'],
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [session.resolvedAppUserId, merchantId],
        limit: 1,
      );
      final existingRole = existingUser.isEmpty
          ? null
          : _normalizeAppUserRole(existingUser.first['role'] as String?);
      resolvedRole = existingRole ?? storedRole;

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
            'role': resolvedRole,
            'status': 'ACTIVE',
            'accepted_at': now,
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
          'role': resolvedRole,
          'accepted_at': now,
          'updated_at': now,
          'last_login_at': now,
        },
        where: 'id = ?',
        whereArgs: [session.resolvedAppUserId],
      );

      await txn.insert(
          'subscription_state',
          {
            'merchant_id': merchantId,
            'plan_code': planDefinition.plan.code,
            'plan_name': planDefinition.displayName,
            'plan_version': 1,
            'pricing_version': 1,
            'status': session.subscriptionStatus,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      for (final featureKey in FeatureKeys.all) {
        await txn.insert(
            'entitlements',
            {
              'id': '${merchantId}_$featureKey',
              'merchant_id': merchantId,
              'feature_key': featureKey,
              'is_enabled': planDefinition.allowsFeature(featureKey) ? 1 : 0,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);

        await txn.insert(
            'feature_flags',
            {
              'id': '${merchantId}_$featureKey',
              'merchant_id': merchantId,
              'flag_key': featureKey,
              'is_enabled': 1,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      await txn.insert(
          'remote_config',
          {
            'id': '${merchantId}_billing_whatsapp_price',
            'merchant_id': merchantId,
            'config_key': 'billing_whatsapp_price',
            'payload': jsonEncode({'currency': 'MZN', 'amount': 2}),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.insert(
          'usage_balances',
          {
            'id':
                '${merchantId}_${UsageMetrics.whatsappMessages}_${window.start.millisecondsSinceEpoch}',
            'merchant_id': merchantId,
            'metric_key': UsageMetrics.whatsappMessages,
            'window_start': window.start.millisecondsSinceEpoch,
            'window_end': window.end.millisecondsSinceEpoch,
            'used': 0,
            'limit_value': planDefinition.whatsappMonthlyLimit,
            'soft_limit': 1,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      await _backfillBusinessData(
        txn,
        merchantId: merchantId,
        deviceId: session.deviceId,
      );
    });

    await _storage.saveAppUserRole(resolvedRole);
  }

  String? _normalizeAppUserRole(String? role) {
    final normalized = role?.trim().toUpperCase();
    if (normalized == AppConstants.appUserRoleStaff) {
      return AppConstants.appUserRoleStaff;
    }
    if (normalized == AppConstants.appUserRoleOwner) {
      return AppConstants.appUserRoleOwner;
    }
    return null;
  }

  _UsageWindow _monthlyWindow(DateTime now) {
    final start = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final end = nextMonth.subtract(const Duration(milliseconds: 1));
    return _UsageWindow(start, end);
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

    final businessRef = firestore.collection('businesses').doc(merchantId);
    final existingBusiness = await businessRef.get();
    final existingData = existingBusiness.data() ?? <String, dynamic>{};
    final existingOwnerUserId =
        (existingData['owner_user_id'] as String?)?.trim() ?? '';
    final existingFirebaseUid =
        (existingData['firebase_uid'] as String?)?.trim() ?? '';
    final existingCreatedAt =
        (existingData['created_at'] as num?)?.toInt() ?? now;
    final existingLinkCode = (existingData['link_code'] as String?)?.trim();
    final linkCode = (existingLinkCode != null && existingLinkCode.isNotEmpty)
        ? existingLinkCode
        : _buildDeviceLinkCode(merchantId);

    await businessRef.set({
      'id': merchantId,
      'merchant_name': merchantName,
      'phone': session.phone,
      'subscription_status': session.subscriptionStatus,
      'owner_user_id': existingOwnerUserId.isNotEmpty
          ? existingOwnerUserId
          : session.resolvedAppUserId,
      'firebase_uid': existingFirebaseUid.isNotEmpty
          ? existingFirebaseUid
          : session.firebaseUid,
      'device_id': session.deviceId,
      'link_code': linkCode,
      'link_code_normalized': _normalizeLinkCode(linkCode),
      'updated_at': now,
      'created_at': existingCreatedAt,
    }, SetOptions(merge: true));

    await _seedPolicyDocuments(
      firestore,
      merchantId: merchantId,
      subscriptionStatus: session.subscriptionStatus,
      now: now,
    );
  }

  String _normalizeLinkCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _buildDeviceLinkCode(String merchantId) {
    final cleaned =
        merchantId.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final padded = cleaned.isEmpty
        ? 'BARB0000'
        : cleaned.length >= 8
            ? cleaned.substring(cleaned.length - 8)
            : cleaned.padLeft(8, '0');
    return '${padded.substring(0, 4)}-${padded.substring(4, 8)}';
  }

  Future<void> _seedPolicyDocuments(
    FirebaseFirestore firestore, {
    required String merchantId,
    required String subscriptionStatus,
    required int now,
  }) async {
    final businessRef = firestore.collection('businesses').doc(merchantId);
    final planDefinition = PlanCatalog.fromCode('starter');
    final window = _monthlyWindow(DateTime.now());

    final subscriptionRef =
        businessRef.collection('subscription_state').doc(merchantId);
    final subscriptionSnap = await subscriptionRef.get();
    if (!subscriptionSnap.exists) {
      await subscriptionRef.set({
        'merchant_id': merchantId,
        'plan_code': planDefinition.plan.code,
        'plan_name': planDefinition.displayName,
        'plan_version': 1,
        'pricing_version': 1,
        'status': subscriptionStatus,
        'updated_at': now,
      });
    }

    for (final featureKey in FeatureKeys.all) {
      final entitlementId = '${merchantId}_$featureKey';
      final entitlementRef =
          businessRef.collection('entitlements').doc(entitlementId);
      final entitlementSnap = await entitlementRef.get();
      if (!entitlementSnap.exists) {
        await entitlementRef.set({
          'id': entitlementId,
          'merchant_id': merchantId,
          'feature_key': featureKey,
          'is_enabled': planDefinition.allowsFeature(featureKey),
          'updated_at': now,
        });
      }

      final flagId = '${merchantId}_$featureKey';
      final flagRef = businessRef.collection('feature_flags').doc(flagId);
      final flagSnap = await flagRef.get();
      if (!flagSnap.exists) {
        await flagRef.set({
          'id': flagId,
          'merchant_id': merchantId,
          'flag_key': featureKey,
          'is_enabled': true,
          'updated_at': now,
        });
      }
    }

    final configId = '${merchantId}_billing_whatsapp_price';
    final configRef = businessRef.collection('remote_config').doc(configId);
    final configSnap = await configRef.get();
    if (!configSnap.exists) {
      await configRef.set({
        'id': configId,
        'merchant_id': merchantId,
        'config_key': 'billing_whatsapp_price',
        'payload': {'currency': 'MZN', 'amount': 2},
        'updated_at': now,
      });
    }

    final quotaId =
        '${merchantId}_${UsageMetrics.whatsappMessages}_${window.start.millisecondsSinceEpoch}';
    final quotaRef = businessRef.collection('usage_balances').doc(quotaId);
    final quotaSnap = await quotaRef.get();
    if (!quotaSnap.exists) {
      await quotaRef.set({
        'id': quotaId,
        'merchant_id': merchantId,
        'metric_key': UsageMetrics.whatsappMessages,
        'window_start': window.start.millisecondsSinceEpoch,
        'window_end': window.end.millisecondsSinceEpoch,
        'used': 0,
        'limit_value': planDefinition.whatsappMonthlyLimit,
        'soft_limit': true,
        'updated_at': now,
      });
    }
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

class _UsageWindow {
  const _UsageWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class _ExistingMerchantData {
  const _ExistingMerchantData({
    required this.merchantId,
    required this.merchantName,
    required this.subscriptionStatus,
    this.appUserId,
  });

  final String merchantId;
  final String merchantName;
  final String subscriptionStatus;
  final String? appUserId;
}
