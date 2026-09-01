import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/services/connectivity_service.dart';
import '../domain/customer_models.dart';
import 'customer_app_api.dart';
import 'customer_cache_dao.dart';

class CustomerData<T> {
  const CustomerData(
    this.value, {
    required this.fromCache,
    required this.updatedAt,
    this.isDemo = false,
    this.isOffline = false,
  });
  final T value;
  final bool fromCache;
  final DateTime updatedAt;
  final bool isDemo;
  final bool isOffline;
}

class CustomerAppRepository {
  CustomerAppRepository(this._api, this._cache, this._auth, this._connectivity);
  final CustomerAppApi _api;
  final CustomerCacheDao _cache;
  final FirebaseAuth _auth;
  final ConnectivityService _connectivity;

  Future<CustomerFeatureFlags> featureFlags() async {
    if (!await _connectivity.check()) {
      throw const NetworkException(
        'É necessária ligação à internet para verificar funcionalidades.',
      );
    }
    final credential = await _credential();
    final session = await _api.session(credential.token);
    if (_auth.currentUser?.uid != credential.accountId) {
      throw StateError('A sessão de cliente mudou durante a atualização.');
    }
    return session.flags;
  }

  Future<CustomerData<List<CustomerBusiness>>> home() => _resource(
        'home',
        _api.home,
        (json) => ((json['businesses'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                CustomerBusiness.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );
  Future<CustomerData<List<CustomerBusiness>>> businesses() => _resource(
        'businesses',
        _api.businesses,
        (json) => ((json['businesses'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                CustomerBusiness.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );
  Future<CustomerData<CustomerBusiness>> business(String id) => _resource(
        'business:$id',
        (token) => _api.business(token, id),
        CustomerBusiness.fromJson,
      );
  Future<CustomerData<List<CustomerReward>>> rewards() => _resource(
        'rewards',
        _api.rewards,
        (json) => ((json['rewards'] as List?) ?? const [])
            .whereType<Map>()
            .map(
                (item) => CustomerReward.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );
  Future<CustomerData<List<CustomerActivity>>> activity() => _resource(
        'activity',
        _api.activity,
        (json) => ((json['activity'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                CustomerActivity.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );
  Future<CustomerData<CustomerProfile>> profile() =>
      _resource('profile', _api.profile, CustomerProfile.fromJson);
  Future<CustomerData<CustomerQr>> qr() =>
      _resource('qr', _api.qr, CustomerQr.fromJson);
  Future<CustomerData<Map<String, dynamic>>> notifications() =>
      _resource('notifications', _api.notifications, (json) => json);
  Future<CustomerData<Map<String, dynamic>>> deepLinks() =>
      _resource('deep-links', _api.deepLinks, (json) => json);

  Future<CustomerPreferences> updatePreferences(
      CustomerPreferences value) async {
    final credential = await _credential();
    final updated = await _api.updatePreferences(credential.token, value);
    if (_auth.currentUser?.uid != credential.accountId) {
      throw StateError('A sessão de cliente mudou durante a atualização.');
    }
    final profile = await _cache.read(credential.accountId, 'profile');
    if (profile != null) {
      await _cache.write(credential.accountId, 'profile', {
        ...profile.payload,
        'preferences': updated.toJson(),
      });
    }
    return updated;
  }

  Future<CustomerRedemptionReceipt> redeem(
      String rewardId, String idempotencyKey) async {
    if (!await _connectivity.check()) {
      throw const NetworkException(
        'É necessária ligação à internet para resgatar.',
      );
    }
    final credential = await _credential();
    await _cache.write(credential.accountId, 'redemption:$rewardId', {
      'status': 'pending',
      'reward_id': rewardId,
      'idempotency_key': idempotencyKey,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    final result = await _api.redeem(
      credential.token,
      rewardId: rewardId,
      idempotencyKey: idempotencyKey,
    );
    if (_auth.currentUser?.uid != credential.accountId) {
      throw StateError('A sessão de cliente mudou durante o resgate.');
    }
    await _cache.write(credential.accountId, 'redemption:$rewardId', {
      'status': 'completed',
      'reward_id': rewardId,
      'idempotency_key': idempotencyKey,
      'result': result.toJson(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _cache.clearTransactionalData(credential.accountId);
    return result;
  }

  Future<CustomerRedemptionReceipt> redemptionStatus(
    String redemptionId,
  ) async {
    if (!await _connectivity.check()) {
      throw const NetworkException(
        'É necessária ligação à internet para atualizar o resgate.',
      );
    }
    final credential = await _credential();
    final result = await _api.redemptionStatus(credential.token, redemptionId);
    await _verifyAndStoreRedemptionReceipt(credential, result);
    return result;
  }

  Future<CustomerRedemptionReceipt> reissueRedemption({
    required String redemptionId,
    required String idempotencyKey,
  }) async {
    if (!await _connectivity.check()) {
      throw const NetworkException(
        'É necessária ligação à internet para gerar um novo código.',
      );
    }
    final credential = await _credential();
    final result = await _api.reissueRedemption(
      credential.token,
      redemptionId: redemptionId,
      idempotencyKey: idempotencyKey,
    );
    await _verifyAndStoreRedemptionReceipt(credential, result);
    return result;
  }

  Future<void> _verifyAndStoreRedemptionReceipt(
    _CustomerCredential credential,
    CustomerRedemptionReceipt receipt,
  ) async {
    if (_auth.currentUser?.uid != credential.accountId) {
      throw StateError('A sessão de cliente mudou durante o resgate.');
    }
    final key = 'redemption:${receipt.rewardId}';
    final current = await _cache.read(credential.accountId, key);
    await _cache.write(credential.accountId, key, {
      ...?current?.payload,
      'status': 'completed',
      'reward_id': receipt.rewardId,
      'result': receipt.toJson(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, dynamic>?> redemptionRecord(String rewardId) async {
    final accountId = await _accountId();
    return (await _cache.read(accountId, 'redemption:$rewardId'))?.payload;
  }

  Future<void> startNewRedemption(String rewardId) async {
    final accountId = await _accountId();
    await _cache.clear(accountId, 'redemption:$rewardId');
  }

  Future<void> event(String eventType) async {
    try {
      if (!await _connectivity.check()) return;
      final credential = await _credential();
      await _api.event(credential.token, eventType);
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace,
          hint: 'customer_event:$eventType');
    }
  }

  Future<CustomerData<T>> _resource<T>(
      String key,
      Future<Map<String, dynamic>> Function(String token) fetch,
      T Function(Map<String, dynamic>) decode) async {
    final accountId = await _accountId();
    final cached = await _cache.read(accountId, key);
    final isOnline = await _connectivity.check();
    if (cached != null && !isOnline) {
      return CustomerData(
        decode(cached.payload),
        fromCache: true,
        updatedAt: cached.updatedAt,
        isOffline: true,
      );
    }
    if (!isOnline) {
      throw const NetworkException('Sem ligação e sem dados guardados.');
    }
    try {
      final credential = await _credential(accountId);
      final payload = await fetch(credential.token);
      if (_auth.currentUser?.uid != accountId) {
        throw StateError('A sessão de cliente mudou durante a atualização.');
      }
      await _cache.write(accountId, key, payload);
      return CustomerData(decode(payload),
          fromCache: false, updatedAt: DateTime.now());
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'customer_read:$key');
      if (cached != null && error is NetworkException) {
        return CustomerData(
          decode(cached.payload),
          fromCache: true,
          updatedAt: cached.updatedAt,
          isOffline: true,
        );
      }
      rethrow;
    }
  }

  Future<String> _accountId() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sessão de cliente indisponível.');
    }
    return uid;
  }

  Future<_CustomerCredential> _credential([String? expectedAccountId]) async {
    final user = _auth.currentUser;
    final accountId = user?.uid;
    if (user == null ||
        accountId == null ||
        accountId.isEmpty ||
        (expectedAccountId != null && expectedAccountId != accountId)) {
      throw StateError('Sessão de cliente indisponível.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Token Firebase indisponível.');
    }
    if (_auth.currentUser?.uid != accountId) {
      throw StateError('A sessão de cliente mudou durante a autenticação.');
    }
    return _CustomerCredential(accountId, token);
  }
}

class _CustomerCredential {
  const _CustomerCredential(this.accountId, this.token);

  final String accountId;
  final String token;
}
