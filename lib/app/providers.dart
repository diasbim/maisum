import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/constants/app_runtime_config.dart';
import '../core/database/app_database.dart';
import '../core/errors/app_error_reporter.dart';
import '../core/errors/app_exception.dart';
import '../core/network/json_api_client.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/services/firestore_sync_service.dart';
import '../core/services/streak/streak_service.dart';
import '../core/matching/customer_match_engine.dart';
import '../core/analytics/analytics_service.dart';
import '../core/notifications/notification_queue_service.dart';
import '../core/storage/secure_storage.dart';
import '../features/auth/data/backend_auth_api.dart';
import '../features/appointments/data/appointment_dao.dart';
import '../features/appointments/data/appointment_repository.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/customer_app/data/customer_app_api.dart';
import '../features/customer_app/data/customer_app_repository.dart';
import '../features/customer_app/data/customer_cache_dao.dart';
import '../features/customer_app/data/customer_platform_service.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/business_profile/domain/business_profile.dart';
import '../features/catalog/data/merchant_catalog_dao.dart';
import '../features/catalog/data/merchant_catalog_repository.dart';
import '../features/catalog/domain/merchant_item.dart';
import '../features/customers/data/customer_dao.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/rewards/data/redemption_dao.dart';
import '../features/rewards/data/redemption_repository.dart';
import '../features/rewards/data/loyalty_ledger_dao.dart';
import '../features/rewards/data/loyalty_redemption_api.dart';
import '../features/rewards/data/reward_dao.dart';
import '../features/rewards/data/reward_repository.dart';
import '../features/retention/data/retention_dao.dart';
import '../features/retention/data/retention_repository.dart';
import '../features/sales/data/sale_dao.dart';
import '../features/sales/data/sale_item_dao.dart';
import '../features/sales/data/sale_item_repository.dart';
import '../features/sales/data/sale_repository.dart';
import '../features/settings/data/staff_management_repository.dart';
import '../features/settings/domain/staff_member.dart';
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

final businessUidProvider = Provider<String?>((ref) {
  return ref.watch(activeMerchantIdProvider);
});

final activeBusinessProfileProvider =
    FutureProvider<BusinessProfile>((ref) async {
  final merchantId = ref.watch(activeMerchantIdProvider);
  if (merchantId == null || merchantId.isEmpty) {
    return BusinessProfiles.generic;
  }

  try {
    final doc = await ref
        .read(firestoreInstanceProvider)
        .collection('businesses')
        .doc(merchantId)
        .get();
    final data = doc.data() ?? const <String, dynamic>{};
    final profile = doc.exists
        ? BusinessProfiles.resolveBusinessData(data)
        : BusinessProfiles.generic;
    return profile;
  } catch (error, stackTrace) {
    AppErrorReporter.report(
      error,
      stackTrace,
      hint: 'active_business_profile_load',
    );
    return BusinessProfiles.generic;
  }
});

final firestoreSyncServiceProvider = Provider<FirestoreSyncService?>((ref) {
  final uid = ref.watch(businessUidProvider);
  if (uid == null) return null;
  final apiClient = ref.read(cloudFunctionsApiClientProvider);
  final firebaseAuth = ref.read(firebaseAuthInstanceProvider);
  return FirestoreSyncService(
    ref.read(firestoreInstanceProvider),
    uid,
    authoritativeSyncHandler: (item) async {
      final token = await firebaseAuth.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw const SyncTransportException(
          'Firebase session is not available',
          code: 'unauthenticated',
        );
      }
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;
      try {
        final response = await apiClient.post(
          '/sync/${Uri.encodeComponent(item.entityType)}/'
          '${Uri.encodeComponent(item.entityId)}',
          bearerToken: token,
          body: {
            'operation': item.operation,
            'payload': payload,
          },
        );
        if (!response.success) {
          throw SyncTransportException(
            response.message ?? 'Authoritative sync failed',
            code: 'failed-precondition',
          );
        }
      } on NetworkException catch (error) {
        throw SyncTransportException(error.message, code: 'unavailable');
      } on ServerException catch (error) {
        final code = switch (error.statusCode) {
          401 => 'unauthenticated',
          403 => 'permission-denied',
          >= 500 => 'unavailable',
          _ => 'failed-precondition',
        };
        throw SyncTransportException(error.message, code: code);
      }
    },
    usageEventSyncHandler: (item) async {
      if (item.operation != 'create') {
        throw const SyncTransportException(
          'usage_event only supports create operations',
          code: 'failed-precondition',
        );
      }
      final token = await firebaseAuth.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw const SyncTransportException(
          'Firebase session is not available',
          code: 'unauthenticated',
        );
      }
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;
      try {
        final response = await apiClient.post(
          '/sync/usage_event/${Uri.encodeComponent(item.entityId)}',
          bearerToken: token,
          body: {
            'operation': item.operation,
            'payload': payload,
          },
        );
        if (!response.success) {
          throw SyncTransportException(
            response.message ?? 'Usage event sync failed',
            code: 'failed-precondition',
          );
        }
      } on NetworkException catch (error) {
        throw SyncTransportException(error.message, code: 'unavailable');
      } on ServerException catch (error) {
        final code = switch (error.statusCode) {
          401 => 'unauthenticated',
          403 => 'permission-denied',
          >= 500 => 'unavailable',
          _ => 'failed-precondition',
        };
        throw SyncTransportException(error.message, code: code);
      }
    },
  );
});

final appRuntimeConfigProvider = Provider<AppRuntimeConfig>(
  (_) => const AppRuntimeConfig(),
);

final jsonApiClientProvider = Provider<JsonApiClient>((ref) {
  final config = ref.watch(appRuntimeConfigProvider);
  return JsonApiClient(baseUrl: config.apiBaseUrl);
});

final cloudFunctionsApiClientProvider = Provider<JsonApiClient>((ref) {
  final config = ref.watch(appRuntimeConfigProvider);
  final baseUrl = config.cloudFunctionsApiBaseUrl.isNotEmpty
      ? config.cloudFunctionsApiBaseUrl
      : config.apiBaseUrl;
  return JsonApiClient(baseUrl: baseUrl);
});

final backendAuthApiProvider = Provider<BackendAuthApi>(
  (ref) => BackendAuthApi(ref.read(jsonApiClientProvider)),
);

final customerAppApiProvider = Provider<CustomerAppApi>(
  (ref) => CustomerAppApi(ref.read(cloudFunctionsApiClientProvider)),
);

final customerPlatformServiceProvider =
    Provider<CustomerPlatformService>((ref) {
  final service = CustomerPlatformService(
    FirebaseMessaging.instance,
    AppLinks(),
    ref.read(customerAppApiProvider),
    ref.read(firebaseAuthInstanceProvider),
    ref.read(connectivityServiceProvider),
    ref.read(secureStorageServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final syncTransportProvider = Provider<SyncTransport?>((ref) {
  return ref.watch(firestoreSyncServiceProvider);
});

// ── Core ─────────────────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase.instance);

final customerCacheDaoProvider = Provider<CustomerCacheDao>(
  (ref) => CustomerCacheDao(ref.read(appDatabaseProvider)),
);

final customerAppRepositoryProvider = Provider<CustomerAppRepository>(
  (ref) => CustomerAppRepository(
    ref.read(customerAppApiProvider),
    ref.read(customerCacheDaoProvider),
    ref.read(firebaseAuthInstanceProvider),
    ref.read(connectivityServiceProvider),
  ),
);

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
    ref.read(cloudFunctionsApiClientProvider),
    ref.read(connectivityServiceProvider),
    ref.read(secureStorageServiceProvider),
    () async {
      final backendToken =
          await ref.read(secureStorageServiceProvider).getToken();
      if (backendToken != null && backendToken.isNotEmpty) {
        return backendToken;
      }
      final currentUser = ref.read(firebaseAuthInstanceProvider).currentUser;
      return currentUser?.getIdToken();
    },
  );
  service.init();
  ref.onDispose(service.dispose);
  return service;
});

// ── DAOs ──────────────────────────────────────────────────────────────────────

final customerDaoProvider = Provider<CustomerDao>(
  (ref) {
    final merchantId = ref.watch(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      throw StateError('Customer data requires an active merchant');
    }
    return CustomerDao(
      ref.read(appDatabaseProvider),
      merchantId: merchantId,
    );
  },
);

final saleDaoProvider = Provider<SaleDao>(
  (ref) => SaleDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
    pointsPerMzn: ref
            .watch(activeBusinessProfileProvider)
            .valueOrNull
            ?.loyalty
            .pointsPerMzn ??
        BusinessProfiles.generic.loyalty.pointsPerMzn,
  ),
);

final saleItemDaoProvider = Provider<SaleItemDao>(
  (ref) => SaleItemDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final merchantCatalogDaoProvider = Provider<MerchantCatalogDao>(
  (ref) => MerchantCatalogDao(
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

final loyaltyLedgerDaoProvider = Provider<LoyaltyLedgerDao>(
  (ref) {
    final merchantId = ref.watch(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      throw StateError('Loyalty ledger requires an active merchant');
    }
    return LoyaltyLedgerDao(
      ref.read(appDatabaseProvider),
      merchantId: merchantId,
    );
  },
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

final customerMatchEngineProvider = Provider<CustomerMatchEngine>(
  (ref) => CustomerMatchEngine(ref.read(customerDaoProvider)),
);

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

final appointmentDaoProvider = Provider<AppointmentDao>(
  (ref) => AppointmentDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
  ),
);

final retentionDaoProvider = Provider<RetentionDao>(
  (ref) => RetentionDao(
    ref.read(appDatabaseProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
    retentionDefaults:
        ref.watch(activeBusinessProfileProvider).valueOrNull?.retention ??
            BusinessProfiles.generic.retention,
  ),
);

// ── Repositories ──────────────────────────────────────────────────────────────

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(
    ref.read(customerDaoProvider),
    ref.read(syncDaoProvider),
    syncTransport: ref.watch(syncTransportProvider),
    connectivity: ref.read(connectivityServiceProvider),
    appUserId: ref.watch(activeAppUserIdProvider),
  ),
);

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => SaleRepository(
    ref.read(appDatabaseProvider),
    ref.read(saleDaoProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
    deviceId: ref.watch(activeDeviceIdProvider),
    appUserId: ref.watch(activeAppUserIdProvider),
    pointsPerMzn: ref
            .watch(activeBusinessProfileProvider)
            .valueOrNull
            ?.loyalty
            .pointsPerMzn ??
        BusinessProfiles.generic.loyalty.pointsPerMzn,
    saleItemDao: ref.read(saleItemDaoProvider),
  ),
);

final saleItemRepositoryProvider = Provider<SaleItemRepository>(
  (ref) => SaleItemRepository(
    ref.read(saleItemDaoProvider),
    ref.read(syncDaoProvider),
    appUserId: ref.watch(activeAppUserIdProvider),
  ),
);

final merchantCatalogRepositoryProvider = Provider<MerchantCatalogRepository>(
  (ref) => MerchantCatalogRepository(
    ref.read(merchantCatalogDaoProvider),
    ref.read(syncDaoProvider),
    appUserId: ref.watch(activeAppUserIdProvider),
  ),
);

final rewardRepositoryProvider = Provider<RewardRepository>(
  (ref) =>
      RewardRepository(ref.read(rewardDaoProvider), ref.read(syncDaoProvider)),
);

final redemptionDaoProvider = Provider<RedemptionDao>(
  (ref) {
    final merchantId = ref.watch(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      throw StateError('Redemption requires an active merchant');
    }
    return RedemptionDao(
      ref.read(appDatabaseProvider),
      merchantId: merchantId,
    );
  },
);

final loyaltyRedemptionApiProvider = Provider<LoyaltyRedemptionApi>(
  (ref) => LoyaltyRedemptionApi(
    ref.read(cloudFunctionsApiClientProvider),
  ),
);

final redemptionRepositoryProvider = Provider<RedemptionRepository>(
  (ref) {
    final merchantId = ref.watch(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      throw StateError('Redemption requires an active merchant');
    }
    return RedemptionRepository(
      ref.read(redemptionDaoProvider),
      ref.read(customerDaoProvider),
      ref.read(loyaltyRedemptionApiProvider),
      ref.read(connectivityServiceProvider),
      merchantId: merchantId,
      resolveBearerToken: () async {
        final token = await ref.read(secureStorageServiceProvider).getToken();
        if (token != null && token.isNotEmpty) return token;
        return ref.read(firebaseAuthInstanceProvider).currentUser?.getIdToken();
      },
    );
  },
);

final appointmentRepositoryProvider = Provider<AppointmentRepository>(
  (ref) => AppointmentRepository(
    ref.read(appointmentDaoProvider),
    ref.read(syncDaoProvider),
    appUserId: ref.watch(activeAppUserIdProvider),
  ),
);

final retentionRepositoryProvider = Provider<RetentionRepository>(
  (ref) => RetentionRepository(
    ref.read(retentionDaoProvider),
    ref.read(syncDaoProvider),
  ),
);

final staffManagementRepositoryProvider = Provider<StaffManagementRepository>(
  (ref) => StaffManagementRepository(
    ref.read(appDatabaseProvider),
    ref.read(syncDaoProvider),
    merchantId: ref.watch(activeMerchantIdProvider),
    currentAppUserId: ref.watch(activeAppUserIdProvider),
  ),
);

final staffMembersProvider = FutureProvider<List<StaffMember>>(
  (ref) => ref.read(staffManagementRepositoryProvider).listMembers(),
);

final subscriptionStateProvider = FutureProvider<SubscriptionState?>(
  (ref) => ref.read(subscriptionDaoProvider).getSubscriptionState(),
);

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(
    ref.read(subscriptionDaoProvider),
    ref.read(usageQuotaEngineProvider),
    ref.read(syncDaoProvider),
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
    customerAppApi: ref.read(customerAppApiProvider),
  ),
);

// ── Sync service ──────────────────────────────────────────────────────────────

final syncServiceProvider = Provider<SyncService>((ref) {
  final merchantId = ref.watch(activeMerchantIdProvider);
  final svc = SyncService(
    ref.read(appDatabaseProvider),
    ref.read(syncDaoProvider),
    ref.watch(syncTransportProvider),
    ref.read(connectivityServiceProvider),
    analytics: ref.read(analyticsServiceProvider),
  );
  if (merchantId != null && merchantId.isNotEmpty) {
    svc.init();
  }
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

final merchantCatalogServicesProvider = FutureProvider<List<MerchantItem>>(
  (ref) => ref.read(merchantCatalogRepositoryProvider).getServices(),
);

final merchantCatalogProductsProvider = FutureProvider<List<MerchantItem>>(
  (ref) => ref.read(merchantCatalogRepositoryProvider).getProducts(),
);

final activeMerchantItemsProvider = FutureProvider<List<MerchantItem>>(
  (ref) => ref.read(merchantCatalogRepositoryProvider).getActiveItems(),
);

final pendingSyncItemsProvider = FutureProvider<List<SyncItem>>((ref) {
  return ref.read(syncDaoProvider).getAllItems();
});
