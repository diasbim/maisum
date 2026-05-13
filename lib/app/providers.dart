import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/constants/app_runtime_config.dart';
import '../core/database/app_database.dart';
import '../core/network/json_api_client.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/services/firestore_sync_service.dart';
import '../core/services/streak/streak_service.dart';
import '../core/matching/customer_match_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/notifications/notification_queue_service.dart';
import '../core/sms/data/sms_inbox_dao.dart';
import '../core/sms/data/sms_transaction_dao.dart';
import '../core/sms/parsers/parser_registry.dart';
import '../core/sms/sms_channel_bridge.dart';
import '../core/sms/sms_listener_service.dart';
import '../core/sms/validation/duplicate_detector.dart';
import '../core/sms/validation/transaction_validator.dart';
import '../core/storage/secure_storage.dart';
import '../features/auth/data/backend_auth_api.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/customers/data/customer_dao.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/rewards/data/redemption_dao.dart';
import '../features/rewards/data/redemption_repository.dart';
import '../features/rewards/data/reward_dao.dart';
import '../features/rewards/data/reward_repository.dart';
import '../features/sales/data/sale_dao.dart';
import '../features/sales/data/sale_repository.dart';
import '../features/sync/data/backend_sync_transport.dart';
import '../features/sync/data/sync_dao.dart';
import '../features/sync/data/sync_transport.dart';
import '../features/sync/domain/sync_item.dart';
import '../features/subscription/data/subscription_dao.dart';
import '../features/subscription/data/subscription_repository.dart';
import '../features/subscription/data/usage_event_dao.dart';
import '../features/subscription/data/remote_config_dao.dart';
import '../features/subscription/data/remote_config_repository.dart';
import '../features/subscription/domain/remote_config.dart';
import '../features/subscription/domain/subscription_snapshot.dart';
import '../features/subscription/domain/subscription_state.dart';
import '../features/subscription/services/feature_gate.dart';
import '../features/subscription/services/remote_config_reader.dart';
import '../features/subscription/services/usage_quota_engine.dart';
import '../features/subscription/services/usage_tracker.dart';
import '../features/sync/sync_service.dart';
import '../features/sales/domain/suggested_sale.dart';

// ── Firebase ──────────────────────────────────────────────────────────────────

final firebaseAuthInstanceProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firestoreInstanceProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

final firebaseAnalyticsProvider = Provider<FirebaseAnalytics>(
  (_) => FirebaseAnalytics.instance,
);

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>(
  (ref) => FirebaseAuthService(ref.read(firebaseAuthInstanceProvider)),
);

// Reactive UID — rebuilds when auth state changes
final authStateChangesProvider = StreamProvider<User?>(
  (_) => FirebaseAuth.instance.authStateChanges(),
);

final businessUidProvider = Provider<String?>((ref) {
  final merchantId = ref.watch(activeMerchantIdProvider);
  if (merchantId != null && merchantId.isNotEmpty) {
    return merchantId;
  }
  return ref.watch(authStateChangesProvider).valueOrNull?.uid;
});

final firestoreSyncServiceProvider = Provider<FirestoreSyncService?>((ref) {
  final uid = ref.watch(businessUidProvider);
  if (uid == null) return null;
  return FirestoreSyncService(ref.read(firestoreInstanceProvider), uid);
});

final appRuntimeConfigProvider = Provider<AppRuntimeConfig>(
  (_) => const AppRuntimeConfig(),
);

final jsonApiClientProvider = Provider<JsonApiClient>((ref) {
  final config = ref.watch(appRuntimeConfigProvider);
  return JsonApiClient(baseUrl: config.apiBaseUrl);
});

final backendAuthApiProvider = Provider<BackendAuthApi>(
  (ref) => BackendAuthApi(ref.read(jsonApiClientProvider)),
);

final backendSyncTransportProvider = Provider<BackendSyncTransport?>((ref) {
  final token = ref.watch(authControllerProvider).valueOrNull?.token;
  if (token == null || token.isEmpty) {
    return null;
  }
  return BackendSyncTransport(ref.read(jsonApiClientProvider), token);
});

final syncTransportProvider = Provider<SyncTransport?>((ref) {
  final config = ref.watch(appRuntimeConfigProvider);
  if (config.usesBackendSync) {
    return ref.watch(backendSyncTransportProvider);
  }
  return ref.watch(firestoreSyncServiceProvider);
});

// ── Core ─────────────────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase.instance);

final secureStorageServiceProvider = Provider<SecureStorageService>(
  (_) => const SecureStorageService(FlutterSecureStorage()),
);

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final svc = ConnectivityService();
  ref.onDispose(svc.dispose);
  return svc;
});

final isOnlineProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).onConnectivityChanged;
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final service = AnalyticsService(
    ref.read(appDatabaseProvider),
    ref.read(jsonApiClientProvider),
    ref.read(connectivityServiceProvider),
    ref.read(secureStorageServiceProvider),
    firebaseAnalytics: ref.read(firebaseAnalyticsProvider),
  );
  unawaited(service.init());
  return service;
});

final notificationQueueServiceProvider =
    Provider<NotificationQueueService>((ref) {
  final service = NotificationQueueService(
    ref.read(appDatabaseProvider),
    ref.read(jsonApiClientProvider),
    ref.read(connectivityServiceProvider),
    ref.read(secureStorageServiceProvider),
  );
  service.init();
  ref.onDispose(service.dispose);
  return service;
});

// ── DAOs ──────────────────────────────────────────────────────────────────────

final customerDaoProvider = Provider<CustomerDao>(
  (ref) => CustomerDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final saleDaoProvider = Provider<SaleDao>(
  (ref) => SaleDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final rewardDaoProvider = Provider<RewardDao>(
  (ref) => RewardDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final syncDaoProvider = Provider<SyncDao>(
  (ref) => SyncDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
    deviceId: ref.watch(activeDeviceIdProvider),
  ),
);

final streakServiceProvider = Provider<StreakService>(
  (ref) => StreakService(ref.read(saleDaoProvider)),
);

final smsInboxDaoProvider = Provider<SmsInboxDao>(
  (ref) => SmsInboxDao(ref.read(appDatabaseProvider)),
);

final smsTransactionDaoProvider = Provider<SmsTransactionDao>(
  (ref) => SmsTransactionDao(ref.read(appDatabaseProvider)),
);

final customerMatchEngineProvider = Provider<CustomerMatchEngine>(
  (ref) => CustomerMatchEngine(ref.read(customerDaoProvider)),
);

final smsListenerServiceProvider = Provider<SmsListenerService>((ref) {
  final service = SmsListenerService(
    SmsChannelBridge(),
    ParserRegistry(),
    const TransactionValidator(),
    DuplicateDetector(ref.read(smsTransactionDaoProvider)),
    ref.read(smsInboxDaoProvider),
    ref.read(customerMatchEngineProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final smsSuggestionStreamProvider = StreamProvider<SuggestedSale>((ref) {
  return ref.watch(smsListenerServiceProvider).suggestions;
});

final subscriptionDaoProvider = Provider<SubscriptionDao>(
  (ref) => SubscriptionDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final remoteConfigDaoProvider = Provider<RemoteConfigDao>(
  (ref) => RemoteConfigDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final usageQuotaEngineProvider = Provider<UsageQuotaEngine>(
  (ref) => UsageQuotaEngine(
    ref.read(subscriptionDaoProvider),
    remoteConfigReader: ref.read(remoteConfigReaderProvider),
  ),
);

final usageEventDaoProvider = Provider<UsageEventDao>(
  (ref) => UsageEventDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

// ── Repositories ──────────────────────────────────────────────────────────────

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(
    ref.read(customerDaoProvider),
    ref.read(syncDaoProvider),
  ),
);

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => SaleRepository(
    ref.read(appDatabaseProvider),
    ref.read(saleDaoProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
    deviceId: ref.watch(activeDeviceIdProvider),
  ),
);

final rewardRepositoryProvider = Provider<RewardRepository>(
  (ref) =>
      RewardRepository(ref.read(rewardDaoProvider), ref.read(syncDaoProvider)),
);

final redemptionDaoProvider = Provider<RedemptionDao>(
  (ref) => RedemptionDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final redemptionRepositoryProvider = Provider<RedemptionRepository>(
  (ref) => RedemptionRepository(
    ref.read(redemptionDaoProvider),
    ref.read(customerDaoProvider),
    ref.read(syncDaoProvider),
  ),
);

final subscriptionStateProvider = FutureProvider<SubscriptionState?>(
  (ref) => ref.read(subscriptionDaoProvider).getSubscriptionState(),
);

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(
    ref.read(subscriptionDaoProvider),
    ref.read(usageQuotaEngineProvider),
  ),
);

final remoteConfigRepositoryProvider = Provider<RemoteConfigRepository>(
  (ref) => RemoteConfigRepository(ref.read(remoteConfigDaoProvider)),
);

final remoteConfigReaderProvider = Provider<RemoteConfigReader>(
  (ref) => RemoteConfigReader(ref.read(remoteConfigRepositoryProvider)),
);

final remoteConfigEntriesProvider = FutureProvider<List<RemoteConfigEntry>>(
  (ref) => ref.read(remoteConfigRepositoryProvider).getAllConfigs(),
);

final usageTrackerProvider = Provider<UsageTracker>(
  (ref) => UsageTracker(
    ref.read(appDatabaseProvider),
    ref.read(subscriptionDaoProvider),
    ref.read(syncDaoProvider),
    remoteConfigReader: ref.read(remoteConfigReaderProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final featureGateProvider = Provider<FeatureGate>(
  (ref) => FeatureGate(
    ref.read(subscriptionDaoProvider),
    ref.read(usageQuotaEngineProvider),
  ),
);

final syncStatusStreamProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).statusStream,
);

class SubscriptionSnapshotController
    extends AsyncNotifier<SubscriptionSnapshot> {
  bool _wasSyncing = false;

  @override
  Future<SubscriptionSnapshot> build() async {
    ref.listen<AsyncValue<SyncStatus>>(syncStatusStreamProvider, (_, next) {
      final status = next.valueOrNull;
      if (status == null) return;
      if (_wasSyncing && !status.isSyncing) {
        unawaited(_refresh());
      }
      _wasSyncing = status.isSyncing;
    });
    return _loadSnapshot();
  }

  Future<void> refresh() async => _refresh();

  Future<void> _refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _loadSnapshot());
  }

  Future<SubscriptionSnapshot> _loadSnapshot() {
    return ref.read(subscriptionRepositoryProvider).getSnapshot();
  }
}

final subscriptionSnapshotProvider =
    AsyncNotifierProvider<SubscriptionSnapshotController, SubscriptionSnapshot>(
  SubscriptionSnapshotController.new,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.read(firebaseAuthServiceProvider),
    ref.read(secureStorageServiceProvider),
    ref.read(appDatabaseProvider),
    config: ref.read(appRuntimeConfigProvider),
    firestore: ref.read(firestoreInstanceProvider),
    backendAuthApi: ref.read(appRuntimeConfigProvider).enableBackendAuth
        ? ref.read(backendAuthApiProvider)
        : null,
  ),
);

// ── Sync service ──────────────────────────────────────────────────────────────

final syncServiceProvider = Provider<SyncService>((ref) {
  final svc = SyncService(
    ref.read(appDatabaseProvider),
    ref.read(syncDaoProvider),
    ref.watch(syncTransportProvider),
    ref.read(connectivityServiceProvider),
    analytics: ref.read(analyticsServiceProvider),
  );
  svc.init();
  ref.onDispose(svc.dispose);
  return svc;
});

// ── App lock ──────────────────────────────────────────────────────────────────

final appLockedProvider = StateProvider<bool>((_) => false);

// ── Query providers ───────────────────────────────────────────────────────────

final allSalesWithCustomerProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) {
    return ref.read(saleDaoProvider).getAllWithCustomer();
  },
);

final pendingSyncItemsProvider = FutureProvider<List<SyncItem>>((ref) {
  return ref.read(syncDaoProvider).getAllItems();
});
