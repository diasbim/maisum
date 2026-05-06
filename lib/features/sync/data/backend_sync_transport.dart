import 'dart:convert';

import '../../../core/network/json_api_client.dart';
import '../domain/sync_item.dart';
import 'sync_transport.dart';

class BackendSyncTransport implements SyncTransport {
  const BackendSyncTransport(this._client, this._accessToken);

  final JsonApiClient _client;
  final String _accessToken;

  @override
  String get transportName => 'backend';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async {
    final response = await _client.get(
      '/sync/$entityType',
      bearerToken: _accessToken,
    );
    return _asMapList(response.data);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit = 200,
  }) async {
    final response = await _client.get(
      '/sync/$entityType/changes',
      bearerToken: _accessToken,
      queryParameters: {
        'order_field': orderField,
        'last_value': lastValue,
        'last_doc_id': lastDocId,
        'limit': limit,
      },
    );
    return _asMapList(response.data);
  }

  @override
  Future<void> processSyncItem(SyncItem item) async {
    final payload = jsonDecode(item.payload);
    await _client.post(
      '/sync/${item.entityType}/${item.entityId}',
      bearerToken: _accessToken,
      body: {
        'operation': item.operation,
        'payload': payload,
        'queued_at': item.createdAt.toIso8601String(),
      },
    );
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
