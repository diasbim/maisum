import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/app_runtime_config.dart';
import '../database/app_database.dart';
import '../network/json_api_client.dart';
import '../services/connectivity_service.dart';
import '../storage/secure_storage.dart';
import '../../features/sync/data/backend_sync_transport.dart';
import '../../features/sync/data/sync_dao.dart';
import '../../features/sync/data/sync_transport.dart';
import '../../features/sync/sync_service.dart';
import '../services/firestore_sync_service.dart';
import '../../firebase_options.dart';

const backgroundSyncTaskName = 'background-sync';
const backgroundSyncUniqueName = 'sync-task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    const storage = SecureStorageService(const FlutterSecureStorage());
    final merchantId = await storage.getMerchantId() ??
        await storage.getFirebaseUid() ??
        await storage.getUserId();
    final deviceId = await storage.getDeviceId();

    final connectivity = ConnectivityService();
    await connectivity.check();

    const config = AppRuntimeConfig();
    SyncTransport? transport;

    if (config.usesBackendSync) {
      final token = await storage.getToken();
      if (token != null && token.isNotEmpty) {
        transport = BackendSyncTransport(
          JsonApiClient(baseUrl: config.apiBaseUrl),
          token,
        );
      }
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final businessId = merchantId ?? await storage.getFirebaseUid();
      if (businessId != null && businessId.isNotEmpty) {
        transport = FirestoreSyncService(
          FirebaseFirestore.instance,
          businessId,
        );
      }
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
      await service.processQueue();
    }

    connectivity.dispose();
    return Future.value(true);
  });
}

Future<void> registerBackgroundSync({bool debug = false}) async {
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: debug,
  );

  await Workmanager().registerPeriodicTask(
    backgroundSyncUniqueName,
    backgroundSyncTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
