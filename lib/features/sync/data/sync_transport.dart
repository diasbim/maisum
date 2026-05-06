import '../domain/sync_item.dart';

abstract class SyncTransport {
  String get transportName;

  Future<List<Map<String, dynamic>>> fetchCollection(String entityType);

  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit,
  });

  Future<void> processSyncItem(SyncItem item);
}
