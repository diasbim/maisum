import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import '../services/connectivity_service.dart';
import '../utils/app_logger.dart';
import '../storage/secure_storage.dart';
import '../../features/sync/data/sync_dao.dart';
import '../../features/sync/data/sync_transport.dart';
import '../../features/sync/sync_service.dart';
import '../services/firestore_sync_service.dart';
import '../../firebase_options.dart';

const backgroundSyncTaskName = 'background-sync';
const backgroundSyncUniqueName = 'sync-task';
const backgroundSyncImmediateUniqueName = 'sync-task-immediate';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    try {
      Log.i('BackgroundSync', 'Starting background task $task');

      final appDatabase = AppDatabase.instance;
      final unscopedStats = await SyncDao(appDatabase).getStats();
      if (unscopedStats.pendingReady == 0) {
        Log.i('BackgroundSync', 'No ready sync items');
        return Future.value(true);
      }

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      const storage = SecureStorageService(FlutterSecureStorage());
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      final storedFirebaseUid = await storage.getFirebaseUid();
      final storedUserId = await storage.getUserId();
      final localMerchantId = await _readLocalMerchantId(appDatabase);
      final merchantId = await storage.getMerchantId() ??
          storedFirebaseUid ??
          authUid ??
          localMerchantId ??
          storedUserId;
      final deviceId = await storage.getDeviceId() ??
          await _readLocalDeviceId(appDatabase, merchantId: merchantId);

      final connectivity = ConnectivityService();
      await connectivity.check();

      SyncTransport? transport;

      final businessId = authUid ?? storedFirebaseUid ?? merchantId;
      if (businessId != null && businessId.isNotEmpty) {
        transport = FirestoreSyncService(
          FirebaseFirestore.instance,
          businessId,
        );
      }

      final dao = SyncDao(
        appDatabase,
        merchantId: merchantId,
        deviceId: deviceId,
      );

      final service = SyncService(
        appDatabase,
        dao,
        transport,
        connectivity,
      );

      if (connectivity.isOnline) {
        if (transport == null) {
          final pendingReady = (await dao.getStats()).pendingReady;
          connectivity.dispose();
          // Mark work as unsuccessful when we have pending items but no transport
          // so WorkManager can retry later.
          return Future.value(pendingReady == 0);
        }

        final scopedStats = await dao.getStats();
        if (scopedStats.pendingReady > 0 || merchantId == null) {
          await service.processQueue();
        } else {
          // If current merchant scope has no ready rows, fall back to unscoped
          // processing to avoid a false-success no-op when context drifts.
          final fallbackDao = SyncDao(
            appDatabase,
            deviceId: deviceId,
          );
          if (unscopedStats.pendingReady > 0) {
            final fallbackService = SyncService(
              appDatabase,
              fallbackDao,
              transport,
              connectivity,
            );
            await fallbackService.processQueue();
          }
        }
      }

      connectivity.dispose();
      Log.i('BackgroundSync', 'Finished background task $task');
      return Future.value(true);
    } catch (error, stack) {
      Log.e('BackgroundSync', 'Background task $task failed', error, stack);
      return Future.value(false);
    }
  });
}

Future<String?> _readLocalMerchantId(AppDatabase appDatabase) async {
  try {
    final db = await appDatabase.database;
    final merchants = await db.query(
      'merchants',
      columns: ['id'],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (merchants.isNotEmpty) {
      final id = merchants.first['id'] as String?;
      if (id != null && id.isNotEmpty) return id;
    }

    final queued = await db.rawQuery('''
      SELECT merchant_id
      FROM sync_queue
      WHERE merchant_id IS NOT NULL AND merchant_id != ''
      ORDER BY created_at DESC
      LIMIT 1
    ''');
    if (queued.isEmpty) return null;
    final id = queued.first['merchant_id'] as String?;
    return id == null || id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}

Future<String?> _readLocalDeviceId(
  AppDatabase appDatabase, {
  String? merchantId,
}) async {
  try {
    final db = await appDatabase.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT device_id
            FROM sync_queue
            WHERE device_id IS NOT NULL AND device_id != ''
            ORDER BY created_at DESC
            LIMIT 1
          '''
          : '''
            SELECT device_id
            FROM sync_queue
            WHERE merchant_id = ? AND device_id IS NOT NULL AND device_id != ''
            ORDER BY created_at DESC
            LIMIT 1
          ''',
      merchantId == null ? const [] : [merchantId],
    );
    if (rows.isEmpty) return null;
    final id = rows.first['device_id'] as String?;
    return id == null || id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}

Future<void> registerBackgroundSync({bool debug = false}) async {
  await Workmanager().initialize(callbackDispatcher);

  // Enqueue an immediate connected run so sync does not wait for the next
  // periodic window after app startup.
  await Workmanager().registerOneOffTask(
    backgroundSyncImmediateUniqueName,
    backgroundSyncTaskName,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    initialDelay: Duration.zero,
  );

  await Workmanager().registerPeriodicTask(
    backgroundSyncUniqueName,
    backgroundSyncTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.connected),
  );

  if (debug) {
    // Best-effort debugging aid now that isInDebugMode no longer has effect.
    try {
      await Workmanager().printScheduledTasks();
    } catch (_) {}
  }
}
