import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/firestore_sync_service.dart';
import '../../core/utils/app_logger.dart';
import 'data/sync_dao.dart';
import 'domain/sync_item.dart';

const _tag = 'Sync';

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
  SyncService(this._syncDao, this._firestoreSync, this._connectivity);

  final SyncDao _syncDao;
  final FirestoreSyncService? _firestoreSync;
  final ConnectivityService _connectivity;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  StreamSubscription<bool>? _connectivitySub;

  void init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        Log.i(_tag, 'Back online — triggering queue');
        processQueue();
      }
    });
    _refreshPendingCount();
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
      await _syncDao.clearSynced();
      Log.i(_tag, 'Queue processed successfully');
    } catch (e, st) {
      lastError = e.toString();
      Log.e(_tag, 'processQueue failed', e, st);
    } finally {
      final pending = await _syncDao.getPendingCount();
      _emit(SyncStatus(pendingCount: pending, lastError: lastError));
      Log.i(_tag, 'Sync done — $pending pending item(s)'
          '${lastError != null ? ", error: $lastError" : ""}');
    }
  }

  Future<void> _processItem(SyncItem item) async {
    if (_firestoreSync == null) {
      Log.w(_tag, 'No Firestore service — skipping ${item.id}');
      return;
    }
    try {
      Log.d(_tag,
          'Syncing ${item.entityType}/${item.entityId} [${item.operation}]');
      await _firestoreSync!.processSyncItem(item);
      await _syncDao.markSynced(item.id);
      Log.i(_tag, '✓ ${item.entityType}/${item.entityId}');
    } catch (e, st) {
      Log.e(_tag, '✗ ${item.entityType}/${item.entityId}', e, st);
      await _syncDao.incrementRetry(item.id);
      final nextAttempt = item.retryCount + 1;
      if (nextAttempt >= AppConstants.maxSyncRetries) {
        await _syncDao.markFailed(item.id);
        Log.w(_tag,
            'Item ${item.id} marked failed after $nextAttempt attempt(s)');
      } else {
        Log.d(_tag,
            'Item ${item.id} will retry (attempt $nextAttempt/${AppConstants.maxSyncRetries})');
      }
    }
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
    _statusController.close();
    Log.d(_tag, 'SyncService disposed');
  }
}
