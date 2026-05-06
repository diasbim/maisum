import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/utils/app_logger.dart';
import 'data/sync_dao.dart';
import 'data/sync_transport.dart';
import 'domain/sync_item.dart';

const _tag = 'Sync';
const _backgroundSyncInterval = Duration(seconds: 30);

class _SyncCursor {
  const _SyncCursor({required this.lastValue, required this.lastDocId});

  final int? lastValue;
  final String? lastDocId;
}

class _SyncEntityConfig {
  const _SyncEntityConfig({
    required this.entityType,
    required this.cursorField,
  });

  final String entityType;
  final String cursorField;
}

const _syncEntities = [
  _SyncEntityConfig(entityType: 'customer', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'sale', cursorField: 'created_at'),
  _SyncEntityConfig(entityType: 'reward', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'redemption', cursorField: 'redeemed_at'),
];

class SyncStatus {
  const SyncStatus({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.lastError,
  });

  final bool isSyncing;
  final int pendingCount;
  final String? lastError;

  SyncStatus copyWith({
    bool? isSyncing,
    int? pendingCount,
    // Use a sentinel so null can be passed explicitly to clear lastError.
    Object? lastError = _keep,
  }) =>
      SyncStatus(
        isSyncing: isSyncing ?? this.isSyncing,
        pendingCount: pendingCount ?? this.pendingCount,
        lastError: lastError == _keep ? this.lastError : lastError as String?,
      );
}

const _keep = Object();

class SyncService {
  SyncService(
    this._database,
    this._syncDao,
    this._transport,
    this._connectivity,
  );

  final AppDatabase _database;

  final SyncDao _syncDao;
  final SyncTransport? _transport;
  final ConnectivityService _connectivity;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _backgroundSyncTimer;

  void init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        Log.i(_tag, 'Back online — triggering queue');
        unawaited(processQueue());
      }
    });
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (_) {
      if (_connectivity.isOnline) {
        unawaited(processQueue());
      }
    });
    _refreshPendingCount();
    if (_connectivity.isOnline) {
      unawaited(processQueue());
    }
  }

  Future<void> processQueue() async {
    if (_status.isSyncing) {
      Log.d(_tag, 'Already syncing — skipping');
      return;
    }
    if (!_connectivity.isOnline) {
      Log.d(_tag, 'Offline — skipping queue');
      await _refreshPendingCount();
      return;
    }

    Log.i(_tag, 'Starting sync queue');
    _emit(_status.copyWith(isSyncing: true, lastError: null));

    String? lastError;
    try {
      final items = await _syncDao.getPending();
      Log.i(_tag, '${items.length} item(s) pending');
      for (final item in items) {
        await _processItem(item);
      }
      await _pullRemoteChanges();
      await _syncDao.clearSynced();
      Log.i(_tag, 'Queue processed successfully');
    } catch (e, st) {
      lastError = e.toString();
      Log.e(_tag, 'processQueue failed', e, st);
    } finally {
      final pending = await _syncDao.getPendingCount();
      _emit(SyncStatus(pendingCount: pending, lastError: lastError));
      Log.i(
        _tag,
        'Sync done — $pending pending item(s)'
        '${lastError != null ? ", error: $lastError" : ""}',
      );
    }
  }

  Future<void> _processItem(SyncItem item) async {
    final transport = _transport;
    if (transport == null) {
      Log.w(_tag, 'No sync transport — skipping ${item.id}');
      return;
    }
    try {
      Log.d(
        _tag,
        'Syncing ${item.entityType}/${item.entityId} [${item.operation}]',
      );
      await transport.processSyncItem(item);
      await _syncDao.markSynced(item.id);
      await _markEntitySynced(item.entityType, item.entityId);
      Log.i(_tag, '✓ ${item.entityType}/${item.entityId}');
    } catch (e, st) {
      Log.e(_tag, '✗ ${item.entityType}/${item.entityId}', e, st);
      await _syncDao.incrementRetry(item.id);
      final nextAttempt = item.retryCount + 1;
      if (nextAttempt >= AppConstants.maxSyncRetries) {
        await _syncDao.markFailed(item.id);
        Log.w(
          _tag,
          'Item ${item.id} marked failed after $nextAttempt attempt(s)',
        );
      } else {
        Log.d(
          _tag,
          'Item ${item.id} will retry (attempt $nextAttempt/${AppConstants.maxSyncRetries})',
        );
      }
    }
  }

  Future<void> _pullRemoteChanges() async {
    if (_transport == null) {
      return;
    }

    final db = await _database.database;
    for (final entity in _syncEntities) {
      await _pullEntityChanges(db, entity);
    }
  }

  Future<void> _pullEntityChanges(Database db, _SyncEntityConfig entity) async {
    var cursor = await _readSyncCursor(db, entity.entityType);

    if (cursor.lastValue == null || cursor.lastDocId == null) {
      final bootstrapDocs = await _transport!.fetchCollection(
        entity.entityType,
      );
      if (bootstrapDocs.isEmpty) {
        return;
      }

      final sortedDocs = [...bootstrapDocs]
        ..sort((left, right) => _compareRemoteDocs(entity, left, right));

      await db.transaction((txn) async {
        for (final remote in sortedDocs) {
          await _applyRemoteEntity(txn, entity.entityType, remote);
          cursor = _advanceCursor(entity, cursor, remote);
          if (cursor.lastValue != null && cursor.lastDocId != null) {
            await _writeSyncCursor(txn, entity.entityType, cursor);
          }
        }
      });
      return;
    }

    while (true) {
      final docs = await _transport!.fetchCollectionSince(
        entityType: entity.entityType,
        orderField: entity.cursorField,
        lastValue: cursor.lastValue,
        lastDocId: cursor.lastDocId,
        limit: AppConstants.syncPullPageSize,
      );

      if (docs.isEmpty) {
        return;
      }

      await db.transaction((txn) async {
        for (final remote in docs) {
          await _applyRemoteEntity(txn, entity.entityType, remote);
          cursor = _advanceCursor(entity, cursor, remote);
          if (cursor.lastValue != null && cursor.lastDocId != null) {
            await _writeSyncCursor(txn, entity.entityType, cursor);
          }
        }
      });

      if (docs.length < AppConstants.syncPullPageSize) {
        return;
      }
    }
  }

  Future<void> _applyRemoteEntity(
    dynamic txn,
    String entityType,
    Map<String, dynamic> remote,
  ) {
    switch (entityType) {
      case 'customer':
        return _applyCustomer(txn, remote);
      case 'sale':
        return _applySale(txn, remote);
      case 'reward':
        return _applyReward(txn, remote);
      case 'redemption':
        return _applyRedemption(txn, remote);
      default:
        return Future.value();
    }
  }

  int _compareRemoteDocs(
    _SyncEntityConfig entity,
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftValue = _cursorValueForRemote(entity, left) ?? 0;
    final rightValue = _cursorValueForRemote(entity, right) ?? 0;
    final byValue = leftValue.compareTo(rightValue);
    if (byValue != 0) {
      return byValue;
    }

    final leftId = left['id'] as String? ?? '';
    final rightId = right['id'] as String? ?? '';
    return leftId.compareTo(rightId);
  }

  int? _cursorValueForRemote(
    _SyncEntityConfig entity,
    Map<String, dynamic> remote,
  ) {
    final rawValue = remote[entity.cursorField] ??
        (entity.entityType == 'reward' ? remote['created_at'] : null);
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return null;
  }

  _SyncCursor _advanceCursor(
    _SyncEntityConfig entity,
    _SyncCursor current,
    Map<String, dynamic> remote,
  ) {
    final value = _cursorValueForRemote(entity, remote);
    final docId = remote['id'] as String?;
    if (value == null || docId == null) {
      return current;
    }
    return _SyncCursor(lastValue: value, lastDocId: docId);
  }

  Future<_SyncCursor> _readSyncCursor(Database db, String entityType) async {
    final rows = await db.query(
      'sync_state',
      where: 'entity_type = ?',
      whereArgs: [entityType],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const _SyncCursor(lastValue: null, lastDocId: null);
    }

    final row = rows.first;
    return _SyncCursor(
      lastValue: row['last_value'] as int?,
      lastDocId: row['last_doc_id'] as String?,
    );
  }

  Future<void> _writeSyncCursor(
    dynamic txn,
    String entityType,
    _SyncCursor cursor,
  ) async {
    await txn.insert(
        'sync_state',
        {
          'entity_type': entityType,
          'last_value': cursor.lastValue,
          'last_doc_id': cursor.lastDocId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _applyCustomer(dynamic txn, Map<String, dynamic> remote) async {
    final id = remote['id'] as String?;
    if (id == null) return;

    final row = await txn.query(
      'customers',
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
      limit: 1,
    );
    final incoming = _normalizedIncoming(remote)..['synced'] = 1;

    if (row.isEmpty) {
      await txn.insert('customers', incoming);
      return;
    }

    final local = Map<String, dynamic>.from(row.first);
    final localSynced = (local['synced'] as int? ?? 0) == 1;
    final sameData = local['name'] == incoming['name'] &&
        local['phone'] == incoming['phone'] &&
        local['total_points'] == incoming['total_points'] &&
        local['updated_at'] == incoming['updated_at'];

    if (!localSynced && !sameData) {
      return;
    }

    await txn.update(
      'customers',
      incoming,
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
    );
  }

  Future<void> _applySale(dynamic txn, Map<String, dynamic> remote) async {
    final id = remote['id'] as String?;
    if (id == null) return;

    final row = await txn.query(
      'sales',
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
      limit: 1,
    );
    final incoming = _normalizedIncoming(remote, includeDevice: true)
      ..['synced'] = 1;

    if (row.isEmpty) {
      await txn.insert('sales', incoming);
      return;
    }

    final local = Map<String, dynamic>.from(row.first);
    final sameData = local['customer_id'] == incoming['customer_id'] &&
        local['amount'] == incoming['amount'] &&
        local['points'] == incoming['points'] &&
        local['created_at'] == incoming['created_at'];
    if ((local['synced'] as int? ?? 0) == 0 && !sameData) {
      return;
    }

    await txn.update(
      'sales',
      incoming,
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
    );
  }

  Future<void> _applyReward(dynamic txn, Map<String, dynamic> remote) async {
    final id = remote['id'] as String?;
    if (id == null) return;

    final row = await txn.query(
      'rewards',
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
      limit: 1,
    );
    final incoming = _normalizedIncoming(remote)..['synced'] = 1;

    if (row.isEmpty) {
      await txn.insert('rewards', incoming);
      return;
    }

    final local = Map<String, dynamic>.from(row.first);
    final sameData = local['name'] == incoming['name'] &&
        local['points_required'] == incoming['points_required'] &&
        local['description'] == incoming['description'] &&
        local['active'] == incoming['active'] &&
        local['updated_at'] == incoming['updated_at'];
    if ((local['synced'] as int? ?? 0) == 0 && !sameData) {
      return;
    }

    await txn.update(
      'rewards',
      incoming,
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
    );
  }

  Future<void> _applyRedemption(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final id = remote['id'] as String?;
    if (id == null) return;

    final row = await txn.query(
      'redemptions',
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
      limit: 1,
    );
    final incoming = _normalizedIncoming(remote)..['synced'] = 1;

    if (row.isEmpty) {
      await txn.insert('redemptions', incoming);
      return;
    }

    final local = Map<String, dynamic>.from(row.first);
    final sameData = local['customer_id'] == incoming['customer_id'] &&
        local['reward_id'] == incoming['reward_id'] &&
        local['points_spent'] == incoming['points_spent'] &&
        local['redeemed_at'] == incoming['redeemed_at'];
    if ((local['synced'] as int? ?? 0) == 0 && !sameData) {
      return;
    }

    await txn.update(
      'redemptions',
      incoming,
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
    );
  }

  Future<void> _markEntitySynced(String entityType, String entityId) async {
    final db = await _database.database;
    switch (entityType) {
      case 'customer':
        await db.update(
          'customers',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
      case 'sale':
        await db.update(
          'sales',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
      case 'reward':
        await db.update(
          'rewards',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
      case 'redemption':
        await db.update(
          'redemptions',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
    }
  }

  Map<String, dynamic> _normalizedIncoming(
    Map<String, dynamic> remote, {
    bool includeDevice = false,
  }) {
    final incoming = Map<String, dynamic>.from(remote);
    if (incoming['merchant_id'] == null && _syncDao.merchantId != null) {
      incoming['merchant_id'] = _syncDao.merchantId;
    }
    if (includeDevice &&
        incoming['device_id'] == null &&
        _syncDao.deviceId != null) {
      incoming['device_id'] = _syncDao.deviceId;
    }
    return incoming;
  }

  String _entityWhereClause(String clause) {
    if (_syncDao.merchantId == null) {
      return clause;
    }
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _entityWhereArgs(List<Object?> args) {
    if (_syncDao.merchantId == null) {
      return args;
    }
    return [_syncDao.merchantId, ...args];
  }

  Future<void> _refreshPendingCount() async {
    final count = await _syncDao.getPendingCount();
    _emit(_status.copyWith(pendingCount: count));
  }

  void _emit(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  void dispose() {
    _connectivitySub?.cancel();
    _backgroundSyncTimer?.cancel();
    _statusController.close();
    Log.d(_tag, 'SyncService disposed');
  }
}
