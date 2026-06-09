import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'providers.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/otp_verification_screen.dart';
import '../features/auth/presentation/phone_auth_screen.dart';
import '../features/auth/presentation/pin_entry_screen.dart';
import '../features/auth/presentation/pin_setup_screen.dart';
import '../features/auth/presentation/device_link_screen.dart';
import '../features/auth/presentation/onboarding_entry_screen.dart';
import '../features/auth/presentation/post_auth_navigation.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/customers/presentation/customer_create_screen.dart';
import '../features/customers/presentation/customer_list_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/engage/presentation/engage_dashboard_screen.dart';
import '../features/engage/presentation/recovery_actions_screen.dart';
import '../features/engage/presentation/survey_analytics_screen.dart';
import '../features/engage/presentation/survey_builder_screen.dart';
import '../features/engage/presentation/survey_response_screen.dart';
import '../features/engage/presentation/visit_report_screen.dart';
import '../features/rewards/presentation/create_reward_screen.dart';
import '../features/rewards/presentation/rewards_screen.dart';
import '../features/retention/presentation/retention_dashboard_screen.dart';
import '../features/sales/presentation/new_sale_screen.dart';
import '../features/sales/presentation/sales_history_screen.dart';
import '../features/sales/presentation/sale_success_screen.dart';
import '../features/legal/presentation/privacy_screen.dart';
import '../features/legal/presentation/terms_screen.dart';
import '../features/settings/presentation/merchant_config_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/staff_management_screen.dart';
import '../features/appointments/presentation/appointments_screen.dart';
import '../features/subscription/presentation/subscription_admin_screen.dart';
import '../features/subscription/presentation/onboarding_plan_selection_screen.dart';
import '../features/sync/presentation/pending_sync_screen.dart';

const _publicRoutes = {
  '/splash',
  '/login',
  '/otp',
  '/pin-setup',
  '/pin-entry',
  '/terms',
  '/privacy',
};

const _planOnboardingBypassRoutes = {
  '/splash',
  '/login',
  '/otp',
  '/pin-setup',
  '/pin-entry',
  '/onboarding-entry',
  '/link-device',
  '/merchant-config',
  '/onboarding-plan',
  '/terms',
  '/privacy',
};

const _ownerOnlyRoutes = {
  '/subscription-admin',
  '/staff-management',
};

const _merchantOnboardingBypassRoutes = {
  '/splash',
  '/login',
  '/otp',
  '/pin-setup',
  '/pin-entry',
  '/onboarding-entry',
  '/link-device',
  '/merchant-config',
  '/terms',
  '/privacy',
};

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ValueNotifier<bool>(false);
  ref.onDispose(authNotifier.dispose);

  ref.listen(authControllerProvider, (_, next) {
    authNotifier.value = next.valueOrNull != null;
  });

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final isPublic = _publicRoutes.contains(state.matchedLocation) ||
          state.matchedLocation.startsWith('/otp');
      final isAuthenticated =
          ref.read(authControllerProvider).valueOrNull != null;

      if (!isAuthenticated && !isPublic) return '/login';
      if (isAuthenticated && state.matchedLocation == '/login') {
        final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
        if (hasPin) return '/pin-entry';
        return resolvePostAuthRoute(ref.read);
      }

      if (isAuthenticated) {
        final canAccessWithoutMerchantLink =
            _merchantOnboardingBypassRoutes.contains(state.matchedLocation) ||
                state.matchedLocation.startsWith('/otp');
        if (!canAccessWithoutMerchantLink) {
          final resolvedRoute = await resolvePostAuthRoute(ref.read);
          if (resolvedRoute == '/onboarding-entry') {
            return '/onboarding-entry';
          }
        }

        if (_ownerOnlyRoutes.contains(state.matchedLocation)) {
          final isOwner =
              await ref.read(secureStorageServiceProvider).isOwnerUser();
          if (!isOwner) {
            return '/dashboard';
          }
        }

        final hasConfirmedPlan = await ref
            .read(secureStorageServiceProvider)
            .hasConfirmedOnboardingPlan();
        final canAccessWithoutPlanConfirmation =
            _planOnboardingBypassRoutes.contains(state.matchedLocation) ||
                state.matchedLocation.startsWith('/otp');

        if (!hasConfirmedPlan && !canAccessWithoutPlanConfirmation) {
          return '/onboarding-plan';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const PhoneAuthScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final args = state.extra as OtpScreenArgs;
          return OTPVerificationScreen(
            phoneNumber: args.phone,
            verificationId: args.verificationId,
          );
        },
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (_, state) => PinSetupScreen(
          nextRoute: state.uri.queryParameters['next'],
        ),
      ),
      GoRoute(path: '/pin-entry', builder: (_, __) => const PinEntryScreen()),
      GoRoute(
        path: '/onboarding-entry',
        builder: (_, __) => const OnboardingEntryScreen(),
      ),
      GoRoute(
        path: '/onboarding-plan',
        builder: (_, __) => const OnboardingPlanSelectionScreen(),
      ),
      GoRoute(
        path: '/link-device',
        builder: (_, __) => const DeviceLinkScreen(),
      ),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
      GoRoute(
        path: '/new-sale',
        builder: (_, state) => NewSaleScreen(args: state.extra as NewSaleArgs?),
      ),
      GoRoute(
        path: '/sale-success',
        builder: (_, state) {
          final args = state.extra;
          if (args is! SaleSuccessArgs) {
            return const Scaffold(
              body: Center(child: Text('Venda não encontrada.')),
            );
          }
          return SaleSuccessScreen(args: args);
        },
      ),
      GoRoute(
        path: '/customers',
        builder: (_, __) => const CustomerListScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (_, state) => CustomerCreateScreen(
              returnRoute: state.uri.queryParameters['returnTo'],
              resumeSaleFlow:
                  state.uri.queryParameters['resumeSaleFlow'] == '1',
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                CustomerDetailScreen(id: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/rewards',
        builder: (_, __) => const RewardsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, state) => CreateRewardScreen(
              initialTemplateCode: state.uri.queryParameters['template'],
            ),
          ),
        ],
      ),
      GoRoute(path: '/sales', builder: (_, __) => const SalesHistoryScreen()),
      GoRoute(
        path: '/appointments',
        builder: (_, __) => const AppointmentsScreen(),
      ),
      GoRoute(
        path: '/retention',
        builder: (_, __) => const RetentionDashboardScreen(),
      ),
      GoRoute(
        path: '/engage',
        builder: (_, __) => const EngageDashboardScreen(),
      ),
      GoRoute(
        path: '/engage/actions',
        builder: (_, __) => const RecoveryActionsScreen(),
      ),
      GoRoute(
        path: '/engage/visit-report',
        builder: (_, __) => const VisitReportScreen(),
      ),
      GoRoute(
        path: '/engage/surveys/new',
        builder: (_, __) => const SurveyBuilderScreen(),
      ),
      GoRoute(
        path: '/engage/surveys/respond',
        builder: (_, __) => const SurveyResponseScreen(),
      ),
      GoRoute(
        path: '/engage/surveys/analytics',
        builder: (_, __) => const SurveyAnalyticsScreen(),
      ),
      GoRoute(
        path: '/pending-sync',
        builder: (_, __) => const PendingSyncScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/staff-management',
        builder: (_, __) => const StaffManagementScreen(),
      ),
      GoRoute(
        path: '/subscription-admin',
        builder: (_, __) => const SubscriptionAdminScreen(),
      ),
      GoRoute(
        path: '/merchant-config',
        builder: (_, __) => const MerchantConfigScreen(),
      ),
      GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Página não encontrada: ${state.error}')),
    ),
  );
});
