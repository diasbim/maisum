import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

import '../../features/sync/data/sync_transport.dart';
import '../../features/sync/domain/sync_item.dart';

typedef UsageEventSyncHandler = Future<void> Function(SyncItem item);
typedef AuthoritativeSyncHandler = Future<void> Function(SyncItem item);

class FirestoreSyncService implements SyncTransport {
  FirestoreSyncService(
    this._firestore,
    this._businessUid, {
    UsageEventSyncHandler? usageEventSyncHandler,
    AuthoritativeSyncHandler? authoritativeSyncHandler,
  })  : _usageEventSyncHandler = usageEventSyncHandler,
        _authoritativeSyncHandler = authoritativeSyncHandler;

  final FirebaseFirestore _firestore;
  final String _businessUid;
  final UsageEventSyncHandler? _usageEventSyncHandler;
  final AuthoritativeSyncHandler? _authoritativeSyncHandler;

  static const _collectionMap = {
    'customer': 'customers',
    'merchant_item': 'merchant_items',
    'sale': 'sales',
    'sale_item': 'sale_items',
    'reward': 'rewards',
    'redemption': 'redemptions',
    'loyalty_ledger': 'loyalty_ledger',
    'appointment': 'appointments',
    'retention_metric': 'retention_metrics',
    'customer_risk_score': 'customer_risk_scores',
    'recovery_task': 'recovery_tasks',
    'recovery_action': 'recovery_actions',
    'visit_report': 'visit_reports',
    'survey': 'surveys',
    'survey_question': 'survey_questions',
    'survey_response': 'survey_responses',
    'survey_response_answer': 'survey_response_answers',
    'subscription_state': 'subscription_state',
    'entitlement': 'entitlements',
    'feature_flag': 'feature_flags',
    'remote_config': 'remote_config',
    'usage_balance': 'usage_balances',
    'usage_event': 'usage_events',
    'app_user': 'app_users',
    'sync_tombstone': 'sync_tombstones',
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
  Future<SyncProcessResult?> processSyncItem(SyncItem item) async {
    final usageEventSyncHandler = _usageEventSyncHandler;
    if (item.entityType == 'usage_event' && usageEventSyncHandler != null) {
      await usageEventSyncHandler(item);
      return null;
    }

    try {
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;
      final isCustomerArchiveMutation = item.entityType == 'customer' &&
          item.operation == 'update' &&
          payload.containsKey('archived_at');
      final isAuthoritativeMutation = isCustomerArchiveMutation ||
          (item.entityType == 'customer' && item.operation == 'delete') ||
          (item.entityType == 'sale' && item.operation == 'cancel');
      if (isAuthoritativeMutation) {
        final handler = _authoritativeSyncHandler;
        if (handler == null) {
          throw const SyncTransportException(
            'Authoritative sync service is unavailable',
            code: 'unavailable',
          );
        }
        await handler(item);
        return null;
      }

      final collection = _collectionMap[item.entityType] ?? item.entityType;
      final docRef = _firestore
          .collection('businesses')
          .doc(_businessUid)
          .collection(collection)
          .doc(item.entityId);

      switch (item.operation) {
        case 'create':
        case 'update':
          final data = payload;
          if (item.entityType == 'recovery_task') {
            return _processRecoveryTask(item, data, docRef);
          }
          await docRef.set(data, SetOptions(merge: true));
          return null;
        case 'delete':
          await docRef.delete();
          return null;
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

  Future<SyncProcessResult> _processRecoveryTask(
    SyncItem item,
    Map<String, dynamic> data,
    DocumentReference<Map<String, dynamic>> taskRef,
  ) async {
    final customerId = (data['customer_id'] as String?)?.trim() ?? '';
    final status = ((data['status'] as String?) ?? 'open').toLowerCase();
    if (customerId.isEmpty) {
      throw const SyncTransportException(
        'Recovery task is missing customer_id',
        code: 'failed-precondition',
      );
    }
    final slotRef = _firestore
        .collection('businesses')
        .doc(_businessUid)
        .collection('recovery_task_open_slots')
        .doc(customerId);

    return _firestore.runTransaction((transaction) async {
      final slot = await transaction.get(slotRef);
      final canonicalId = slot.data()?['task_id'] as String?;
      if (status == 'open') {
        if (canonicalId != null && canonicalId.isNotEmpty) {
          final canonicalRef = taskRef.parent.doc(canonicalId);
          final canonical = await transaction.get(canonicalRef);
          final canonicalData = canonical.data();
          if (canonical.exists &&
              ((canonicalData?['status'] as String?) ?? 'open').toLowerCase() ==
                  'open') {
            return SyncProcessResult(
              canonicalEntity: {
                ...canonicalData!,
                'id': canonical.id,
              },
            );
          }
        }
        transaction.set(taskRef, data, SetOptions(merge: true));
        transaction.set(slotRef, {
          'task_id': item.entityId,
          'customer_id': customerId,
          'updated_at': data['updated_at'],
        });
        return SyncProcessResult(
          canonicalEntity: {...data, 'id': item.entityId},
        );
      }

      transaction.set(taskRef, data, SetOptions(merge: true));
      if (canonicalId == item.entityId) {
        transaction.delete(slotRef);
      }
      return SyncProcessResult(
        canonicalEntity: {...data, 'id': item.entityId},
      );
    });
  }
}
