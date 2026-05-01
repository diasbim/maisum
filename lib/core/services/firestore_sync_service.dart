import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

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
