import 'dart:async';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../network/json_api_client.dart';
import '../services/connectivity_service.dart';
import '../storage/secure_storage.dart';
import '../sync/sync_retry_policy.dart';
import 'data/notification_queue_dao.dart';
import 'domain/notification_queue_item.dart';

class NotificationQueueService {
  NotificationQueueService(
    AppDatabase db,
    this._client,
    this._connectivity,
    this._storage,
    this._resolveBearerToken,
  ) : _dao = NotificationQueueDao(db);

  final JsonApiClient _client;
  final ConnectivityService _connectivity;
  final SecureStorageService _storage;
  final Future<String?> Function() _resolveBearerToken;
  final NotificationQueueDao _dao;
  final SyncRetryPolicy _retryPolicy = const SyncRetryPolicy();

  static const _uuid = Uuid();
  bool _processing = false;
  StreamSubscription<bool>? _connectivitySub;

  void init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      if (online) {
        processQueue();
      }
    });
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
  }

  Future<void> enqueueWhatsApp({
    required String phone,
    required String message,
    String? source,
  }) async {
    final payload = {
      'phone': phone,
      'message': message,
      if (source != null) 'source': source,
    };

    final now = DateTime.now();
    final item = NotificationQueueItem(
      id: _uuid.v4(),
      channel: 'whatsapp',
      payload: payload,
      status: 'pending',
      scheduledAt: now,
      createdAt: now,
      retryCount: 0,
      lastError: null,
    );

    await _dao.insert(item);
    await processQueue();
  }

  Future<void> processQueue() async {
    if (_processing) return;
    if (!_connectivity.isOnline) return;

    _processing = true;
    try {
      final merchantId = await _storage.getMerchantId();
      if (merchantId == null || merchantId.isEmpty) return;

      final token = await _resolveBearerToken();
      final deviceId = await _storage.getDeviceId();
      final headers = <String, String>{
        'X-Merchant-Id': merchantId,
      };
      if (deviceId != null && deviceId.isNotEmpty) {
        headers['X-Device-Id'] = deviceId;
      }

      final items = await _dao.getPending(limit: 20);
      for (final item in items) {
        try {
          await _client.post(
            '/notifications/queue',
            headers: headers,
            bearerToken: token,
            body: {
              'channel': item.channel,
              'payload': item.payload,
              'scheduled_at': item.scheduledAt.toIso8601String(),
            },
          );
          await _dao.markSent(item.id);
        } catch (e) {
          final nextAttempt = _retryPolicy.nextAttempt(
            retryCount: item.retryCount + 1,
          );
          await _dao.reschedule(
            item.id,
            nextAttempt: nextAttempt,
            retryCount: item.retryCount + 1,
            lastError: e.toString(),
          );
        }
      }
    } finally {
      _processing = false;
    }
  }
}
