import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/analytics/analytics_service.dart';
import '../../core/database/app_database.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/sync/sync_retry_policy.dart';
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
  _SyncEntityConfig(entityType: 'appointment', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'retention_metric', cursorField: 'updated_at'),
  _SyncEntityConfig(
      entityType: 'subscription_state', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'entitlement', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'feature_flag', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'remote_config', cursorField: 'updated_at'),
  _SyncEntityConfig(entityType: 'usage_balance', cursorField: 'updated_at'),
];

class SyncStatus {
  const SyncStatus({
    required this.isOnline,
    this.phase = SyncPhase.synced,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastError,
    this.lastSyncAt,
    this.nextRetryAt,
  });

  final bool isOnline;
  final SyncPhase phase;
  final int pendingCount;
  final int failedCount;
  final String? lastError;
  final DateTime? lastSyncAt;
  final DateTime? nextRetryAt;

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get hasPending => pendingCount > 0;
  bool get hasFailures => failedCount > 0;
  SyncViewState get viewState {
    if (!isOnline) return SyncViewState.idle;
    if (phase == SyncPhase.syncing || phase == SyncPhase.retrying) {
      return SyncViewState.syncing;
    }
    if (phase == SyncPhase.syncFailed || lastError != null || hasFailures) {
      return SyncViewState.failed;
    }
    if (phase == SyncPhase.synced && pendingCount == 0) {
      return SyncViewState.success;
    }
    return SyncViewState.idle;
  }

  SyncStatus copyWith({
    bool? isOnline,
    SyncPhase? phase,
    int? pendingCount,
    int? failedCount,
    // Use a sentinel so null can be passed explicitly to clear lastError.
    Object? lastError = _keep,
    DateTime? lastSyncAt,
    DateTime? nextRetryAt,
  }) =>
      SyncStatus(
        isOnline: isOnline ?? this.isOnline,
        phase: phase ?? this.phase,
        pendingCount: pendingCount ?? this.pendingCount,
        failedCount: failedCount ?? this.failedCount,
        lastError: lastError == _keep ? this.lastError : lastError as String?,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

enum SyncPhase {
  synced,
  syncing,
  offline,
  pendingChanges,
  syncFailed,
  retrying,
}

enum SyncViewState { idle, syncing, success, failed }

const _keep = Object();

class SyncService {
  SyncService(
    this._database,
    this._syncDao,
    this._transport,
    this._connectivity, {
    AnalyticsService? analytics,
    SyncRetryPolicy? retryPolicy,
  })  : _retryPolicy = retryPolicy ?? const SyncRetryPolicy(),
        _analytics = analytics;

  final AppDatabase _database;

  final SyncDao _syncDao;
  final SyncTransport? _transport;
  final ConnectivityService _connectivity;
  final SyncRetryPolicy _retryPolicy;
  final AnalyticsService? _analytics;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  late SyncStatus _status = SyncStatus(
    isOnline: _connectivity.isOnline,
    phase: _connectivity.isOnline ? SyncPhase.synced : SyncPhase.offline,
  );
  SyncStatus get status => _status;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _backgroundSyncTimer;
  DateTime? _lastSyncAt;
  SyncQueueStats _cachedStats = const SyncQueueStats(
    pendingTotal: 0,
    pendingReady: 0,
    failed: 0,
  );

  void init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((isOnline) {
      _emit(_status.copyWith(
        isOnline: isOnline,
        phase: _derivePhase(
          isOnline: isOnline,
          isSyncing: _status.isSyncing,
          stats: _cachedStats,
          lastError: _status.lastError,
        ),
      ));
      if (!isOnline) return;
      Log.i(_tag, 'Back online — triggering queue');
      unawaited(processQueue());
    });
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (_) {
      if (_connectivity.isOnline) {
        unawaited(processQueue());
      }
    });
    unawaited(_refreshStatus());
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
      await _refreshStatus();
      return;
    }

    Log.i(_tag, 'Starting sync queue');
    _emit(_status.copyWith(phase: SyncPhase.syncing, lastError: null));
    unawaited(_logSyncEvent('sync_started', {
      'pending_ready': _cachedStats.pendingReady,
      'pending_total': _cachedStats.pendingTotal,
    }));

    String? lastError;
    String? itemError;
    try {
      final items = await _syncDao.getPending();
      Log.i(_tag, '${items.length} item(s) pending');
      for (final item in items) {
        final error = await _processItem(item);
        if (error != null) {
          itemError = error;
        }
      }
      await _pullRemoteChanges();
      await _syncDao.clearSynced();
      _lastSyncAt = DateTime.now();
      unawaited(_logSyncEvent('sync_success', {
        'processed': items.length,
      }));
      Log.i(_tag, 'Queue processed successfully');
    } catch (e, st) {
      lastError = _formatSyncError(e);
      Log.e(_tag, 'processQueue failed', e, st);
      unawaited(_logSyncEvent('sync_failed', {
        'error': lastError ?? AppStrings.erroGenerico,
      }));
    } finally {
      final resolvedError = lastError ?? itemError;
      await _refreshStatus(lastErrorOverride: resolvedError);
    }
  }

  Future<void> retryFailed({String? itemId}) async {
    await _syncDao.retryFailed(id: itemId);
    await _refreshStatus(lastErrorOverride: null);
    if (_connectivity.isOnline) {
      await processQueue();
    }
  }

  Future<String?> _processItem(SyncItem item) async {
    final transport = _transport;
    if (transport == null) {
      Log.w(_tag, 'No sync transport — skipping ${item.id}');
      return null;
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
      return null;
    } catch (e, st) {
      Log.e(_tag, '✗ ${item.entityType}/${item.entityId}', e, st);
      final transportError = e is SyncTransportException ? e : null;
      final isPermanent = transportError != null &&
          (transportError.code == 'failed-precondition' ||
              transportError.code == 'permission-denied' ||
              transportError.code == 'unauthenticated');

      if (isPermanent) {
        await _syncDao.markFailed(item.id);
        Log.w(_tag, 'Item ${item.id} marked failed (non-retryable)');
        return _formatSyncError(e);
      }

      await _syncDao.incrementRetry(item.id);
      final retryCount = item.retryCount + 1;
      if (retryCount >= AppConstants.maxSyncRetries) {
        await _syncDao.markFailed(item.id);
        Log.w(
          _tag,
          'Item ${item.id} marked failed after $retryCount attempt(s)',
        );
      } else {
        final nextAttemptAt = _retryPolicy.nextAttempt(retryCount: retryCount);
        await _syncDao.scheduleRetry(item.id, nextAttemptAt);
        Log.d(
          _tag,
          'Item ${item.id} will retry (attempt $retryCount/${AppConstants.maxSyncRetries})',
        );
      }
      return _formatSyncError(e);
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
      case 'appointment':
        return _applyAppointment(txn, remote);
      case 'retention_metric':
        return _applyRetentionMetric(txn, remote);
      case 'subscription_state':
        return _applySubscriptionState(txn, remote);
      case 'entitlement':
        return _applyEntitlement(txn, remote);
      case 'feature_flag':
        return _applyFeatureFlag(txn, remote);
      case 'remote_config':
        return _applyRemoteConfig(txn, remote);
      case 'usage_balance':
        return _applyUsageBalance(txn, remote);
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

  Future<void> _applyAppointment(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final id = remote['id'] as String?;
    if (id == null) return;

    final row = await txn.query(
      'appointments',
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
      limit: 1,
    );
    final incoming = _filterKeys(_normalizedIncoming(remote), {
      'id',
      'merchant_id',
      'customer_id',
      'scheduled_date',
      'status',
      'source',
      'reminder_sent',
      'created_at',
      'updated_at',
      'synced',
    })
      ..['synced'] = 1;

    if (row.isEmpty) {
      await txn.insert('appointments', incoming);
      return;
    }

    final local = Map<String, dynamic>.from(row.first);
    final sameData = local['customer_id'] == incoming['customer_id'] &&
        local['scheduled_date'] == incoming['scheduled_date'] &&
        local['status'] == incoming['status'] &&
        local['source'] == incoming['source'] &&
        local['reminder_sent'] == incoming['reminder_sent'] &&
        local['updated_at'] == incoming['updated_at'];
    if ((local['synced'] as int? ?? 0) == 0 && !sameData) {
      return;
    }

    await txn.update(
      'appointments',
      incoming,
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
    );
  }

  Future<void> _applyRetentionMetric(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final id = remote['id'] as String?;
    if (id == null) return;

    final row = await txn.query(
      'retention_metrics',
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
      limit: 1,
    );
    final incoming = _normalizedIncoming(remote)..['synced'] = 1;

    if (row.isEmpty) {
      await txn.insert('retention_metrics', incoming);
      return;
    }

    final local = Map<String, dynamic>.from(row.first);
    final sameData = local['customer_id'] == incoming['customer_id'] &&
        local['last_visit_at'] == incoming['last_visit_at'] &&
        local['days_inactive'] == incoming['days_inactive'] &&
        local['risk_level'] == incoming['risk_level'] &&
        local['total_visits'] == incoming['total_visits'] &&
        local['average_visit_interval'] == incoming['average_visit_interval'] &&
        local['total_spent'] == incoming['total_spent'] &&
        local['is_recurring'] == incoming['is_recurring'] &&
        local['recovered'] == incoming['recovered'] &&
        local['updated_at'] == incoming['updated_at'];
    if ((local['synced'] as int? ?? 0) == 0 && !sameData) {
      return;
    }

    await txn.update(
      'retention_metrics',
      incoming,
      where: _entityWhereClause('id = ?'),
      whereArgs: _entityWhereArgs([id]),
    );
  }

  Future<void> _applySubscriptionState(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final incoming = _normalizedIncoming(remote);
    _copyIfAbsent(incoming, 'merchant_id', 'merchantId');
    _copyIfAbsent(incoming, 'plan_code', 'planCode');
    _copyIfAbsent(incoming, 'plan_name', 'planName');
    _copyIfAbsent(incoming, 'plan_version', 'planVersion');
    _copyIfAbsent(incoming, 'pricing_version', 'pricingVersion');
    _copyIfAbsent(incoming, 'status', 'subscription_status');
    _copyIfAbsent(incoming, 'trial_ends_at', 'trialEndsAt');
    _copyIfAbsent(incoming, 'grace_ends_at', 'graceEndsAt');
    _copyIfAbsent(incoming, 'period_start', 'periodStart');
    _copyIfAbsent(incoming, 'period_end', 'periodEnd');

    final merchantId =
        incoming['merchant_id'] as String? ?? _syncDao.merchantId;
    if (merchantId == null) return;
    incoming['merchant_id'] = merchantId;
    incoming['updated_at'] ??= DateTime.now().millisecondsSinceEpoch;

    final filtered = _filterKeys(incoming, {
      'merchant_id',
      'plan_code',
      'plan_name',
      'plan_version',
      'pricing_version',
      'status',
      'trial_ends_at',
      'grace_ends_at',
      'period_start',
      'period_end',
      'updated_at',
    });

    await txn.insert(
      'subscription_state',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyEntitlement(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final incoming = _normalizedIncoming(remote);
    _copyIfAbsent(incoming, 'merchant_id', 'merchantId');
    _copyIfAbsent(incoming, 'feature_key', 'featureKey');
    _copyIfAbsent(incoming, 'is_enabled', 'isEnabled');
    _copyIfAbsent(incoming, 'limit_value', 'limitValue');

    final merchantId =
        incoming['merchant_id'] as String? ?? _syncDao.merchantId;
    final featureKey = incoming['feature_key'] as String?;
    if (merchantId == null || featureKey == null) return;
    incoming['merchant_id'] = merchantId;
    incoming['id'] ??= '${merchantId}_$featureKey';
    incoming['updated_at'] ??= DateTime.now().millisecondsSinceEpoch;
    _normalizeBoolean(incoming, 'is_enabled');

    final filtered = _filterKeys(incoming, {
      'id',
      'merchant_id',
      'feature_key',
      'is_enabled',
      'limit_value',
      'unit',
      'updated_at',
    });

    await txn.insert(
      'entitlements',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyFeatureFlag(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final incoming = _normalizedIncoming(remote);
    _copyIfAbsent(incoming, 'merchant_id', 'merchantId');
    _copyIfAbsent(incoming, 'flag_key', 'flagKey');
    _copyIfAbsent(incoming, 'is_enabled', 'isEnabled');

    final merchantId =
        incoming['merchant_id'] as String? ?? _syncDao.merchantId;
    final flagKey = incoming['flag_key'] as String?;
    if (merchantId == null || flagKey == null) return;
    incoming['merchant_id'] = merchantId;
    incoming['id'] ??= '${merchantId}_$flagKey';
    incoming['updated_at'] ??= DateTime.now().millisecondsSinceEpoch;
    _normalizeBoolean(incoming, 'is_enabled');

    final filtered = _filterKeys(incoming, {
      'id',
      'merchant_id',
      'flag_key',
      'is_enabled',
      'payload',
      'updated_at',
    });

    await txn.insert(
      'feature_flags',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyRemoteConfig(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final incoming = _normalizedIncoming(remote);
    _copyIfAbsent(incoming, 'merchant_id', 'merchantId');
    _copyIfAbsent(incoming, 'config_key', 'configKey');

    final merchantId =
        incoming['merchant_id'] as String? ?? _syncDao.merchantId;
    final configKey = incoming['config_key'] as String?;
    if (merchantId == null || configKey == null) return;
    incoming['merchant_id'] = merchantId;
    incoming['id'] ??= '${merchantId}_$configKey';
    incoming['updated_at'] ??= DateTime.now().millisecondsSinceEpoch;

    final filtered = _filterKeys(incoming, {
      'id',
      'merchant_id',
      'config_key',
      'payload',
      'updated_at',
    });

    await txn.insert(
      'remote_config',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyUsageBalance(
    dynamic txn,
    Map<String, dynamic> remote,
  ) async {
    final incoming = _normalizedIncoming(remote);
    _copyIfAbsent(incoming, 'merchant_id', 'merchantId');
    _copyIfAbsent(incoming, 'metric_key', 'metricKey');
    _copyIfAbsent(incoming, 'window_start', 'windowStart');
    _copyIfAbsent(incoming, 'window_end', 'windowEnd');
    _copyIfAbsent(incoming, 'limit_value', 'limitValue');
    _copyIfAbsent(incoming, 'soft_limit', 'softLimit');

    final merchantId =
        incoming['merchant_id'] as String? ?? _syncDao.merchantId;
    final metricKey = incoming['metric_key'] as String?;
    if (merchantId == null || metricKey == null) return;
    incoming['merchant_id'] = merchantId;
    incoming['updated_at'] ??= DateTime.now().millisecondsSinceEpoch;
    _normalizeBoolean(incoming, 'soft_limit');

    final windowStart = incoming['window_start'];
    incoming['id'] ??= '${merchantId}_${metricKey}_${windowStart}';

    final filtered = _filterKeys(incoming, {
      'id',
      'merchant_id',
      'metric_key',
      'window_start',
      'window_end',
      'used',
      'limit_value',
      'soft_limit',
      'updated_at',
    });

    await txn.insert(
      'usage_balances',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
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
        break;
      case 'sale':
        await db.update(
          'sales',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
        break;
      case 'reward':
        await db.update(
          'rewards',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
        break;
      case 'redemption':
        await db.update(
          'redemptions',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
        break;
      case 'appointment':
        await db.update(
          'appointments',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
        break;
      case 'retention_metric':
        await db.update(
          'retention_metrics',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
        break;
      case 'usage_event':
        await db.update(
          'usage_events',
          {'synced': 1},
          where: _entityWhereClause('id = ?'),
          whereArgs: _entityWhereArgs([entityId]),
        );
        break;
      default:
        break;
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

  void _copyIfAbsent(
    Map<String, dynamic> target,
    String targetKey,
    String sourceKey,
  ) {
    if (target[targetKey] == null && target[sourceKey] != null) {
      target[targetKey] = target[sourceKey];
    }
  }

  void _normalizeBoolean(Map<String, dynamic> target, String key) {
    final value = target[key];
    if (value is bool) {
      target[key] = value ? 1 : 0;
    }
  }

  Map<String, dynamic> _filterKeys(
    Map<String, dynamic> source,
    Set<String> allowed,
  ) {
    return {
      for (final entry in source.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
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

  Future<void> _refreshStatus({String? lastErrorOverride}) async {
    final stats = await _syncDao.getStats();
    _cachedStats = stats;

    final effectiveError = lastErrorOverride ??
        (stats.failed > 0 ? AppStrings.syncFalhaPendentes : null);
    final phase = _derivePhase(
      isOnline: _connectivity.isOnline,
      isSyncing: _status.isSyncing,
      stats: stats,
      lastError: effectiveError,
    );

    _emit(_status.copyWith(
      isOnline: _connectivity.isOnline,
      phase: phase,
      pendingCount: stats.pendingTotal,
      failedCount: stats.failed,
      nextRetryAt: stats.nextRetryAt,
      lastError: effectiveError,
      lastSyncAt: _lastSyncAt,
    ));
  }

  SyncPhase _derivePhase({
    required bool isOnline,
    required bool isSyncing,
    required SyncQueueStats stats,
    required String? lastError,
  }) {
    if (!isOnline) return SyncPhase.offline;
    if (isSyncing) return SyncPhase.syncing;
    if (lastError != null || stats.failed > 0) return SyncPhase.syncFailed;
    if (stats.pendingTotal > 0) {
      if (stats.pendingReady == 0 && stats.nextRetryAt != null) {
        return SyncPhase.retrying;
      }
      return SyncPhase.pendingChanges;
    }
    return SyncPhase.synced;
  }

  Future<void> _logSyncEvent(
    String eventType, [
    Map<String, Object?>? properties,
  ]) async {
    final analytics = _analytics;
    if (analytics == null) return;
    await analytics.record(
      eventType: eventType,
      properties: properties == null
          ? null
          : {
              for (final entry in properties.entries)
                entry.key: entry.value ?? 'unknown',
            },
      source: 'sync',
    );
  }

  String _formatSyncError(Object error) {
    if (error is SyncTransportException) {
      switch (error.code) {
        case 'failed-precondition':
          return AppStrings.syncIndiceFaltando;
        case 'unauthenticated':
          return AppStrings.erroAuth;
        case 'resource-exhausted':
        case 'deadline-exceeded':
        case 'unavailable':
          return AppStrings.erroRede;
        default:
          break;
      }
    }
    return AppStrings.erroGenerico;
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
