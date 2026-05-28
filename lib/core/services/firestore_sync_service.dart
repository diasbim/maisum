import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

import '../../features/sync/data/sync_transport.dart';
import '../../features/sync/domain/sync_item.dart';

class FirestoreSyncService implements SyncTransport {
  FirestoreSyncService(this._firestore, this._businessUid);

  final FirebaseFirestore _firestore;
  final String _businessUid;

  static const _collectionMap = {
    'customer': 'customers',
    'sale': 'sales',
    'reward': 'rewards',
    'redemption': 'redemptions',
    'appointment': 'appointments',
    'retention_metric': 'retention_metrics',
    'subscription_state': 'subscription_state',
    'entitlement': 'entitlements',
    'feature_flag': 'feature_flags',
    'remote_config': 'remote_config',
    'usage_balance': 'usage_balances',
    'usage_event': 'usage_events',
  };

  @override
  String get transportName => AppConstants.syncTransportFirestore;

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async {
    try {
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
    } on FirebaseException catch (e) {
      throw SyncTransportException(
        e.message ?? 'Firestore error: ${e.code}',
        code: e.code,
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit = AppConstants.syncPullPageSize,
  }) async {
    try {
      final collection = _collectionMap[entityType] ?? entityType;
      Query<Map<String, dynamic>> query = _firestore
          .collection('businesses')
          .doc(_businessUid)
          .collection(collection)
          .orderBy(orderField)
          .limit(limit);

      if (lastValue != null) {
        query = query.where(orderField, isGreaterThanOrEqualTo: lastValue);
      }

      final snapshot = await query.get();
      var docs = [...snapshot.docs];

      docs.sort((a, b) {
        final aValue = (a.data()[orderField] as num?)?.toInt() ?? 0;
        final bValue = (b.data()[orderField] as num?)?.toInt() ?? 0;
        final byField = aValue.compareTo(bValue);
        if (byField != 0) return byField;
        return a.id.compareTo(b.id);
      });

      if (lastValue != null) {
        docs = docs.where((doc) {
          final value = (doc.data()[orderField] as num?)?.toInt() ?? 0;
          if (value > lastValue) return true;
          if (value < lastValue) return false;
          if (lastDocId == null) return false;
          return doc.id.compareTo(lastDocId) > 0;
        }).toList();
      }

      return docs.take(limit).map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data.putIfAbsent('id', () => doc.id);
        return data;
      }).toList();
    } on FirebaseException catch (e) {
      throw SyncTransportException(
        e.message ?? 'Firestore error: ${e.code}',
        code: e.code,
      );
    }
  }

  @override
  Future<void> processSyncItem(SyncItem item) async {
    try {
      final collection = _collectionMap[item.entityType] ?? item.entityType;
      final docRef = _firestore
          .collection('businesses')
          .doc(_businessUid)
          .collection(collection)
          .doc(item.entityId);

      switch (item.operation) {
        case 'create':
        case 'update':
          final data = jsonDecode(item.payload) as Map<String, dynamic>;
          await docRef.set(data, SetOptions(merge: true));
          break;
        case 'delete':
          await docRef.delete();
          break;
        default:
          throw ArgumentError('Unknown sync operation: ${item.operation}');
      }
    } on FirebaseException catch (e) {
      throw SyncTransportException(
        e.message ?? 'Firestore error: ${e.code}',
        code: e.code,
      );
    }
  }
}
