import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../errors/app_error_reporter.dart';
import '../network/json_api_client.dart';
import '../services/connectivity_service.dart';
import '../storage/secure_storage.dart';
import 'data/analytics_event_dao.dart';
import 'domain/analytics_event.dart';

class AnalyticsService {
  AnalyticsService(
    this._db,
    this._client,
    this._connectivity,
    this._storage, {
    FirebaseAnalytics? firebaseAnalytics,
  })  : _firebaseAnalytics = firebaseAnalytics,
        _dao = AnalyticsEventDao(_db);

  final AppDatabase _db;
  final JsonApiClient _client;
  final ConnectivityService _connectivity;
  final SecureStorageService _storage;
  final FirebaseAnalytics? _firebaseAnalytics;
  final AnalyticsEventDao _dao;

  static const _uuid = Uuid();
  bool _flushing = false;

  Future<void> record({
    required String eventType,
    Map<String, dynamic>? properties,
    String? source,
  }) async {
    final merchantId = await _storage.getMerchantId();
    if (merchantId == null || merchantId.isEmpty) {
      return;
    }

    final deviceId = await _storage.getDeviceId();
    final event = AnalyticsEvent(
      id: _uuid.v4(),
      eventType: eventType,
      occurredAt: DateTime.now(),
      source: source,
      deviceId: deviceId,
      appVersion: null,
      properties: properties,
    );

    await _dao.insert(event);
    await _logFirebase(eventType, source: source, properties: properties);
    await flush();
  }

  Future<void> _logFirebase(
    String eventType, {
    String? source,
    Map<String, dynamic>? properties,
  }) async {
    final analytics = _firebaseAnalytics;
    if (analytics == null) return;
    final params = _sanitizeParams(properties, source: source);
    try {
      await analytics.logEvent(
        name: eventType,
        parameters: params.isEmpty ? null : params,
      );
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'analytics_firebase_log');
      // Best effort only.
    }
  }

  Map<String, Object> _sanitizeParams(
    Map<String, dynamic>? raw, {
    String? source,
  }) {
    final params = <String, Object>{};
    if (source != null) {
      params['source'] = source;
    }
    raw?.forEach((key, value) {
      if (value is String || value is num) {
        params[key] = value;
        return;
      }
      if (value is bool) {
        params[key] = value ? 1 : 0;
      }
    });
    return params;
  }

  Future<void> flush() async {
    if (_flushing) return;
    if (!_connectivity.isOnline) return;

    _flushing = true;
    try {
      final merchantId = await _storage.getMerchantId();
      if (merchantId == null || merchantId.isEmpty) return;

      final events = await _dao.getPending(limit: 50);
      if (events.isEmpty) return;

      final deviceId = await _storage.getDeviceId();
      final headers = <String, String>{
        'X-Merchant-Id': merchantId,
      };
      if (deviceId != null && deviceId.isNotEmpty) {
        headers['X-Device-Id'] = deviceId;
      }

      await _client.post(
        '/analytics/events',
        headers: headers,
        body: events.map((e) => e.toApiMap()).toList(),
      );

      await _dao.markSynced(events.map((e) => e.id).toList());
    } catch (e, st) {
      // Best effort analytics; failures remain queued.
      if (e is! NetworkException) {
        AppErrorReporter.report(e, st, hint: 'analytics_flush');
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> init() async {
    await _connectivity.check();
    if (_connectivity.isOnline) {
      await flush();
    }
    _connectivity.onConnectivityChanged.listen((online) {
      if (online) {
        flush();
      }
    });
  }
}
