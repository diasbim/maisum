import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart' as app_providers;
import '../../auth/presentation/auth_controller.dart' as auth_providers;
import '../../../features/subscription/domain/feature_keys.dart';
import '../data/engage_api.dart';
import '../data/engage_dao.dart';
import '../data/engage_repository.dart';
import '../domain/engage_models.dart';

class EngageOverview {
  const EngageOverview({required this.dashboard, required this.queue});

  final EngageDashboardData dashboard;
  final List<RecoveryQueueItem> queue;
}

final engageDaoProvider = Provider<EngageDao>(
  (ref) => EngageDao(
    ref.read(app_providers.appDatabaseProvider),
    merchantId: ref.watch(auth_providers.activeMerchantIdProvider),
  ),
);

final engageAccessProvider = FutureProvider<EngageAccess>((ref) async {
  final gate = ref.read(app_providers.featureGateProvider);

  final viewRisk = await gate.check(featureKey: FeatureKeys.engageViewRisk);
  final manageRecovery = await gate.check(
    featureKey: FeatureKeys.engageManageRecovery,
  );
  final manageVisits = await gate.check(
    featureKey: FeatureKeys.engageManageVisits,
  );
  final manageSurveys = await gate.check(
    featureKey: FeatureKeys.engageManageSurveys,
  );

  return EngageAccess(
    canViewRisk: viewRisk.allowed,
    canManageRecovery: manageRecovery.allowed,
    canManageVisits: manageVisits.allowed,
    canManageSurveys: manageSurveys.allowed,
  );
});

final engageApiProvider = Provider<EngageApi>(
  (ref) => EngageApi(
    ref.read(app_providers.cloudFunctionsApiClientProvider),
    () async {
      final backendToken =
          ref.read(auth_providers.authControllerProvider).valueOrNull?.token;
      if (backendToken != null && backendToken.isNotEmpty) {
        return backendToken;
      }
      final currentUser =
          ref.read(app_providers.firebaseAuthInstanceProvider).currentUser;
      return currentUser?.getIdToken();
    },
  ),
);

final engageRemoteModeProvider = Provider<bool>(
  (ref) => ref.watch(app_providers.appRuntimeConfigProvider).usesBackendSync,
);

final engageRepositoryProvider = Provider<EngageRepository>(
  (ref) => EngageRepository(
    ref.read(engageDaoProvider),
    ref.read(app_providers.syncDaoProvider),
    api: ref.read(engageApiProvider),
    useRemote: ref.watch(engageRemoteModeProvider),
  ),
);

class EngageOverviewController extends AsyncNotifier<EngageOverview> {
  @override
  Future<EngageOverview> build() => _load(refreshRisk: true);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load(refreshRisk: true));
  }

  Future<void> softRefresh() async {
    state = AsyncData(await _load(refreshRisk: false));
  }

  Future<EngageOverview> _load({required bool refreshRisk}) async {
    final repository = ref.read(engageRepositoryProvider);
    final dashboard = await repository.loadDashboard(
      refreshRiskScores: refreshRisk,
    );
    final queue = await repository.getRecoveryQueue(limit: 12);
    return EngageOverview(dashboard: dashboard, queue: queue);
  }
}

final engageOverviewProvider =
    AsyncNotifierProvider<EngageOverviewController, EngageOverview>(
  EngageOverviewController.new,
);

class EngageSurveysController extends AsyncNotifier<List<EngageSurvey>> {
  @override
  Future<List<EngageSurvey>> build() {
    return ref.read(engageRepositoryProvider).getSurveys();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await ref.read(engageRepositoryProvider).getSurveys());
  }
}

final engageSurveysProvider =
    AsyncNotifierProvider<EngageSurveysController, List<EngageSurvey>>(
  EngageSurveysController.new,
);

class EngageSurveyAnalyticsController
    extends AsyncNotifier<EngageSurveyAnalytics> {
  @override
  Future<EngageSurveyAnalytics> build() {
    return ref.read(engageRepositoryProvider).getSurveyAnalytics();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref.read(engageRepositoryProvider).getSurveyAnalytics(),
    );
  }
}

final engageSurveyAnalyticsProvider = AsyncNotifierProvider<
    EngageSurveyAnalyticsController,
    EngageSurveyAnalytics>(EngageSurveyAnalyticsController.new);
