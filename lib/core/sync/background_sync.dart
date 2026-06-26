import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import '../services/connectivity_service.dart';
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

    const storage = SecureStorageService(FlutterSecureStorage());
    final merchantId = await storage.getMerchantId() ??
        await storage.getFirebaseUid() ??
        await storage.getUserId();
    final deviceId = await storage.getDeviceId();

    final connectivity = ConnectivityService();
    await connectivity.check();

    SyncTransport? transport;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final businessId = await storage.getFirebaseUid() ?? merchantId;
    if (businessId != null && businessId.isNotEmpty) {
      transport = FirestoreSyncService(
        FirebaseFirestore.instance,
        businessId,
      );
    }

    final dao = SyncDao(
      AppDatabase.instance,
      merchantId: merchantId,
      deviceId: deviceId,
    );

    final service = SyncService(
      AppDatabase.instance,
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
          AppDatabase.instance,
          deviceId: deviceId,
        );
        final fallbackStats = await fallbackDao.getStats();
        if (fallbackStats.pendingReady > 0) {
          final fallbackService = SyncService(
            AppDatabase.instance,
            fallbackDao,
            transport,
            connectivity,
          );
          await fallbackService.processQueue();
        }
      }
    }

    connectivity.dispose();
    return Future.value(true);
  });
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
