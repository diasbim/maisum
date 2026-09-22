import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/admin_portal/domain/admin_audit_event.dart';
import 'package:maisum/features/admin_portal/domain/admin_merchant_summary.dart';
import 'package:maisum/features/admin_portal/domain/admin_operations_summary.dart';
import 'package:maisum/features/admin_portal/domain/admin_plan_catalog.dart';
import 'package:maisum/features/admin_portal/presentation/admin_portal_shell.dart';
import 'package:maisum/features/admin_portal/providers/admin_portal_providers.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';

final _summary = AdminOperationsSummary(
  merchantCount: 3,
  activeSubscriptionCount: 2,
  trialSubscriptionCount: 1,
  attentionSubscriptionCount: 0,
  activeStaffCount: 5,
  usageEvents24h: 12,
  openRecoveryTaskCount: 0,
  visitReports24h: 0,
  surveyResponses24h: 0,
  adminAuditEvents24h: 1,
  lastAdminAuditAt: DateTime(2024, 1, 1),
  lastUsageEventAt: DateTime(2024, 1, 1),
);

final _plans = <AdminPlanCatalogItem>[
  AdminPlanCatalogItem(
    planCode: 'starter',
    version: 1,
    name: 'Starter',
    isActive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
    prices: const [],
    features: const [],
  ),
];

final _merchants = <AdminMerchantSummary>[
  AdminMerchantSummary(
    id: 'merchant-1',
    name: 'Café Acácia',
    phone: '841000001',
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
    staffCount: 2,
    activeStaffCount: 2,
    usageBalanceCount: 4,
    planCode: 'starter',
    planName: 'Starter',
    subscriptionStatus: 'active',
  ),
];

Widget _buildApp({required String initialLocation}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/admin',
        builder: (_, __) =>
            const AdminPortalShell(section: AdminPortalSection.overview),
        routes: [
          GoRoute(
            path: 'merchants',
            builder: (_, __) =>
                const AdminPortalShell(section: AdminPortalSection.merchants),
          ),
          GoRoute(
            path: 'plans',
            builder: (_, __) =>
                const AdminPortalShell(section: AdminPortalSection.plans),
          ),
          GoRoute(
            path: 'operations',
            builder: (_, __) => const AdminPortalShell(
              section: AdminPortalSection.operations,
            ),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      isInternalAdminProvider.overrideWith((ref) async => true),
      isOwnerUserProvider.overrideWith((ref) async => false),
      activeAppUserRoleProvider.overrideWith((ref) async => 'ADMIN'),
      activeMerchantIdProvider.overrideWithValue(null),
      adminOperationsSummaryProvider.overrideWith((ref) async => _summary),
      adminPlanCatalogProvider.overrideWith((ref) async => _plans),
      adminAuditEventsProvider.overrideWith(
        (ref, merchantId) async => const <AdminAuditEvent>[],
      ),
      adminMerchantSummariesProvider.overrideWith(
        (ref, search) async => _merchants,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('renders overview metrics for an internal admin',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp(initialLocation: '/admin'));
    await tester.pumpAndSettle();

    expect(find.text('Visão geral da administração'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // merchantCount metric value
  });

  testWidgets('navigating to the merchants section lists a merchant',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp(initialLocation: '/admin/merchants'));
    await tester.pumpAndSettle();

    expect(find.text('Diretório de negócios'), findsOneWidget);
    expect(find.text('Café Acácia'), findsOneWidget);
    expect(find.text('841000001'), findsOneWidget);
  });

  testWidgets('navigating to the plans section lists the plan catalog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp(initialLocation: '/admin/plans'));
    await tester.pumpAndSettle();

    expect(find.text('Starter'), findsWidgets);
  });

  testWidgets('navigating to the operations section shows the metrics grid',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp(initialLocation: '/admin/operations'));
    await tester.pumpAndSettle();

    expect(find.text('Subscrições ativas'), findsWidgets);
  });

  testWidgets('the nav rail moves from overview to the merchants section',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp(initialLocation: '/admin'));
    await tester.pumpAndSettle();

    expect(find.text('Diretório de negócios'), findsNothing);

    await tester.tap(find.text('Negócios').first);
    await tester.pumpAndSettle();

    expect(find.text('Diretório de negócios'), findsOneWidget);
    expect(find.text('Café Acácia'), findsOneWidget);
  });
}
