import 'dart:convert';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../domain/sync_item.dart';
import 'sync_transport.dart';

class BackendSyncTransport implements SyncTransport {
  const BackendSyncTransport(this._client, this._resolveAccessToken);

  final JsonApiClient _client;
  final Future<String?> Function() _resolveAccessToken;

  @override
  String get transportName => 'backend';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async {
    return _withMappedErrors(() async {
      final accessToken = await _requireAccessToken();
      final response = await _client.get(
        '/sync/$entityType',
        bearerToken: accessToken,
      );
      return _asMapList(response.data);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit = 200,
  }) async {
    return _withMappedErrors(() async {
      final accessToken = await _requireAccessToken();
      final response = await _client.get(
        '/sync/$entityType/changes',
        bearerToken: accessToken,
        queryParameters: {
          'order_field': orderField,
          'last_value': lastValue,
          'last_doc_id': lastDocId,
          'limit': limit,
        },
      );
      return _asMapList(response.data);
    });
  }

  @override
  Future<void> processSyncItem(SyncItem item) async {
    await _withMappedErrors(() async {
      final accessToken = await _requireAccessToken();
      final payload = jsonDecode(item.payload);
      await _client.post(
        '/sync/${item.entityType}/${item.entityId}',
        bearerToken: accessToken,
        body: {
          'operation': item.operation,
          'payload': payload,
          'queued_at': item.createdAt.toIso8601String(),
        },
      );
      return;
    });
  }

  Future<String> _requireAccessToken() async {
    final token = await _resolveAccessToken();
    if (token == null || token.isEmpty) {
      throw const SyncTransportException('Missing sync access token');
    }
    return token;
  }

  Future<T> _withMappedErrors<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SyncTransportException {
      rethrow;
    } on AppException catch (e) {
      throw _mapAppException(e);
    }
  }

  SyncTransportException _mapAppException(AppException exception) {
    if (exception is NetworkException) {
      return SyncTransportException(exception.message, code: 'unavailable');
    }
    if (exception is AuthException) {
      return SyncTransportException(exception.message, code: 'unauthenticated');
    }
    if (exception is ServerException) {
      final statusCode = exception.statusCode;
      if (statusCode == 401) {
        return SyncTransportException(exception.message, code: 'unauthenticated');
      }
      if (statusCode == 403) {
        return SyncTransportException(exception.message, code: 'permission-denied');
      }
      if (statusCode == 429) {
        return SyncTransportException(exception.message, code: 'resource-exhausted');
      }
      if (statusCode == 408 || statusCode == 504) {
        return SyncTransportException(exception.message, code: 'deadline-exceeded');
      }
      if (statusCode >= 500) {
        return SyncTransportException(exception.message, code: 'unavailable');
      }
      return SyncTransportException(exception.message, code: 'failed-precondition');
    }
    return SyncTransportException(exception.message);
  }

  List<Map<String, dynamic>> _asMapList(dynamic data) {
    if (data is! List) {
      return const [];
    }
    return data.whereType<Map>().map((row) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }
}
