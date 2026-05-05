import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

import '../../features/sync/domain/sync_item.dart';

class FirestoreSyncService {
  FirestoreSyncService(this._firestore, this._businessUid);

  final FirebaseFirestore _firestore;
  final String _businessUid;

  static const _collectionMap = {
    'customer': 'customers',
    'sale': 'sales',
    'reward': 'rewards',
    'redemption': 'redemptions',
  };

  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async {
    final collection = _collectionMap[entityType] ?? entityType;
    final snapshot = await _firestore
        .collection('businesses')
        .doc(_businessUid)
        .collection(collection)
        .get();

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit = AppConstants.syncPullPageSize,
  }) async {
    final collection = _collectionMap[entityType] ?? entityType;
    Query<Map<String, dynamic>> query = _firestore
        .collection('businesses')
        .doc(_businessUid)
        .collection(collection)
        .orderBy(orderField)
        .orderBy('id')
        .limit(limit);

    if (lastValue != null && lastDocId != null) {
      query = query.startAfter([lastValue, lastDocId]);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return data;
    }).toList();
  }

  Future<void> processSyncItem(SyncItem item) async {
    final collection = _collectionMap[item.entityType] ?? item.entityType;
    final docRef = _firestore
        .collection('businesses')
        .doc(_businessUid)
        .collection(collection)
        .doc(item.entityId);

    switch (item.operation) {
      case 'create' || 'update':
        final data = jsonDecode(item.payload) as Map<String, dynamic>;
        await docRef.set(data, SetOptions(merge: true));
      case 'delete':
        await docRef.delete();
      default:
        throw ArgumentError('Unknown sync operation: ${item.operation}');
    }
  }
}
