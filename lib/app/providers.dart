import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/services/firestore_sync_service.dart';
import '../core/storage/secure_storage.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/customers/data/customer_dao.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/rewards/data/redemption_dao.dart';
import '../features/rewards/data/redemption_repository.dart';
import '../features/rewards/data/reward_dao.dart';
import '../features/rewards/data/reward_repository.dart';
import '../features/sales/data/sale_dao.dart';
import '../features/sales/data/sale_repository.dart';
import '../features/sync/data/sync_dao.dart';
import '../features/sync/domain/sync_item.dart';
import '../features/sync/sync_service.dart';

// ── Firebase ──────────────────────────────────────────────────────────────────

final firebaseAuthInstanceProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firestoreInstanceProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>(
  (ref) => FirebaseAuthService(ref.read(firebaseAuthInstanceProvider)),
);

// Reactive UID — rebuilds when auth state changes
final authStateChangesProvider = StreamProvider<User?>(
  (_) => FirebaseAuth.instance.authStateChanges(),
);

final businessUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateChangesProvider).valueOrNull?.uid,
);

final firestoreSyncServiceProvider = Provider<FirestoreSyncService?>((ref) {
  final uid = ref.watch(businessUidProvider);
  if (uid == null) return null;
  return FirestoreSyncService(ref.read(firestoreInstanceProvider), uid);
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

// ── DAOs ──────────────────────────────────────────────────────────────────────

final customerDaoProvider = Provider<CustomerDao>(
  (ref) => CustomerDao(ref.read(appDatabaseProvider)),
);

final saleDaoProvider = Provider<SaleDao>(
  (ref) => SaleDao(ref.read(appDatabaseProvider)),
);

final rewardDaoProvider = Provider<RewardDao>(
  (ref) => RewardDao(ref.read(appDatabaseProvider)),
);

final syncDaoProvider = Provider<SyncDao>(
  (ref) => SyncDao(ref.read(appDatabaseProvider)),
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
  ),
);

final rewardRepositoryProvider = Provider<RewardRepository>(
  (ref) => RewardRepository(
    ref.read(rewardDaoProvider),
    ref.read(syncDaoProvider),
  ),
);

final redemptionDaoProvider = Provider<RedemptionDao>(
  (ref) => RedemptionDao(ref.read(appDatabaseProvider)),
);

final redemptionRepositoryProvider = Provider<RedemptionRepository>(
  (ref) => RedemptionRepository(
    ref.read(redemptionDaoProvider),
    ref.read(customerDaoProvider),
    ref.read(syncDaoProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.read(firebaseAuthServiceProvider),
    ref.read(secureStorageServiceProvider),
  ),
);

// ── Sync service ──────────────────────────────────────────────────────────────

final syncServiceProvider = Provider<SyncService>((ref) {
  final svc = SyncService(
    ref.read(appDatabaseProvider),
    ref.read(syncDaoProvider),
    ref.watch(firestoreSyncServiceProvider),
    ref.read(connectivityServiceProvider),
  );
  svc.init();
  ref.onDispose(svc.dispose);
  return svc;
});

// ── App lock ──────────────────────────────────────────────────────────────────

final appLockedProvider = StateProvider<bool>((_) => false);

// ── Query providers ───────────────────────────────────────────────────────────

final allSalesWithCustomerProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(saleDaoProvider).getAllWithCustomer();
});

final pendingSyncItemsProvider = FutureProvider<List<SyncItem>>((ref) {
  return ref.read(syncDaoProvider).getAllItems();
});
