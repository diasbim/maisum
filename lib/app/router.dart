import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'providers.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/domain/auth_session.dart';
import '../features/auth/presentation/otp_verification_screen.dart';
import '../features/auth/presentation/phone_auth_screen.dart';
import '../features/auth/presentation/pin_entry_screen.dart';
import '../features/auth/presentation/pin_setup_screen.dart';
import '../features/auth/presentation/device_link_screen.dart';
import '../features/auth/presentation/onboarding_entry_screen.dart';
import '../features/auth/presentation/post_auth_navigation.dart';
import '../features/auth/presentation/role_gate_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/admin_portal/presentation/admin_portal_shell.dart';
import '../features/catalog/presentation/merchant_catalog_screen.dart';
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
import '../features/merchant_onboarding/presentation/controllers/merchant_onboarding_controller.dart';
import '../features/merchant_onboarding/presentation/pages/business_info_page.dart';
import '../features/merchant_onboarding/presentation/pages/business_location_page.dart';
import '../features/merchant_onboarding/presentation/pages/business_type_page.dart';
import '../features/merchant_onboarding/presentation/pages/review_page.dart';
import '../features/merchant_onboarding/presentation/pages/services_page.dart';
import '../features/merchant_onboarding/presentation/pages/working_hours_page.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/staff_management_screen.dart';
import '../features/appointments/presentation/appointments_screen.dart';
import '../features/subscription/presentation/subscription_admin_screen.dart';
import '../features/subscription/presentation/onboarding_plan_selection_screen.dart';
import '../features/subscription/presentation/feature_upsell_screen.dart';
import '../features/sync/presentation/pending_sync_screen.dart';
import '../core/theme/customer_experience_theme.dart';
import '../features/customer_app/presentation/customer_route_guards.dart';
import '../features/customer_app/presentation/customer_screens.dart';
import '../features/customer_app/presentation/merchant_redemption_validation_screen.dart';

const _publicRoutes = {
  '/splash',
  '/choose-role',
  '/login',
  '/customer-login',
  '/customer-login/phone',
  '/customer-disabled',
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
  '/merchant-onboarding/type',
  '/merchant-onboarding/info',
  '/merchant-onboarding/location',
  '/merchant-onboarding/hours',
  '/merchant-onboarding/services',
  '/merchant-onboarding/review',
  '/onboarding-plan',
  featureUpsellRoutePath,
  '/terms',
  '/privacy',
};

const _ownerOnlyRoutes = {
  '/onboarding-plan',
  '/merchant-onboarding/type',
  '/merchant-onboarding/info',
  '/merchant-onboarding/location',
  '/merchant-onboarding/hours',
  '/merchant-onboarding/services',
  '/merchant-onboarding/review',
  '/subscription-admin',
  '/staff-management',
};

const _pinSetupBypassRoutes = {
  '/splash',
  '/login',
  '/otp',
  '/pin-setup',
  '/pin-entry',
  '/terms',
  '/privacy',
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
  '/merchant-onboarding/type',
  '/merchant-onboarding/info',
  '/merchant-onboarding/location',
  '/merchant-onboarding/hours',
  '/merchant-onboarding/services',
  '/merchant-onboarding/review',
  '/terms',
  '/privacy',
};

bool _isAdminPortalRoute(String location) {
  return location == '/admin' || location.startsWith('/admin/');
}

bool _isAdminSelfServiceRoute(String location) {
  return location == '/admin/self-service';
}

bool canAccessWithoutOnboardingPlanConfirmation(String location) {
  return _planOnboardingBypassRoutes.contains(location) ||
      location.startsWith('/otp');
}

String? resolveAdminPortalRedirect({
  required bool isWeb,
  required bool isSelfServiceRoute,
  required bool isInternalAdmin,
  required bool isOwner,
}) {
  if (!isWeb) return '/dashboard';
  if (isSelfServiceRoute) return isOwner ? null : '/dashboard';
  if (isInternalAdmin) return null;
  if (isOwner) return '/admin/self-service';
  return '/dashboard';
}

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
      final isAdminPortalRoute = _isAdminPortalRoute(state.matchedLocation);
      final isPublic = _publicRoutes.contains(state.matchedLocation) ||
          state.matchedLocation.startsWith('/otp');
      final session = ref.read(authControllerProvider).valueOrNull;
      final isAuthenticated = session != null;

      final customerRedirect = resolveCustomerActorRedirect(
        location: state.matchedLocation,
        session: session,
      );
      if (customerRedirect != null) return customerRedirect;
      if (!isAuthenticated && !isPublic) return '/login';
      if (isAuthenticated &&
          (state.matchedLocation == '/login' ||
              state.matchedLocation == '/choose-role')) {
        final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
        if (hasPin) return '/pin-entry';
        return resolvePostAuthRoute(ref.read);
      }

      if (isAuthenticated && !session.isCustomer && isAdminPortalRoute) {
        final isSelfServiceRoute =
            _isAdminSelfServiceRoute(state.matchedLocation);
        final isOwner = await ref.read(isOwnerUserProvider.future);
        final isInternalAdmin = isSelfServiceRoute
            ? false
            : await ref.read(isInternalAdminProvider.future);
        return resolveAdminPortalRedirect(
          isWeb: kIsWeb,
          isSelfServiceRoute: isSelfServiceRoute,
          isInternalAdmin: isInternalAdmin,
          isOwner: isOwner,
        );
      }

      if (isAuthenticated && !session.isCustomer) {
        final storage = ref.read(secureStorageServiceProvider);
        final canAccessWithoutPinSetup =
            _pinSetupBypassRoutes.contains(state.matchedLocation) ||
                state.matchedLocation.startsWith('/otp');
        if (!canAccessWithoutPinSetup) {
          final hasPin = await storage.hasPin();
          if (!hasPin) {
            final nextRoute = Uri.encodeComponent(state.uri.toString());
            return '/pin-setup?next=$nextRoute';
          }
        }

        final canAccessWithoutMerchantLink =
            _merchantOnboardingBypassRoutes.contains(state.matchedLocation) ||
                state.matchedLocation.startsWith('/otp');
        if (!canAccessWithoutMerchantLink) {
          final resolvedRoute = await resolvePostAuthRoute(ref.read);
          if (resolvedRoute == '/onboarding-entry' ||
              isMerchantOnboardingRoute(resolvedRoute)) {
            return resolvedRoute;
          }
        }

        final appUserRole = await storage.getAppUserRole();
        final isOwner = await storage.isOwnerUser();
        if (_ownerOnlyRoutes.contains(state.matchedLocation)) {
          if (!isOwner) {
            return '/dashboard';
          }
        }

        if (isOwner) {
          final hasConfirmedPlan = await storage.hasConfirmedOnboardingPlan(
            merchantId: ref.read(activeMerchantIdProvider),
            role: appUserRole,
          );
          final canAccessWithoutPlanConfirmation =
              canAccessWithoutOnboardingPlanConfirmation(
            state.matchedLocation,
          );

          if (!hasConfirmedPlan && !canAccessWithoutPlanConfirmation) {
            return '/onboarding-plan';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/choose-role',
        builder: (_, __) => const CustomerExperienceTheme(
          child: RoleGateScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) => PhoneAuthScreen(
          showPhoneFormInitially: state.uri.queryParameters['source'] == 'role',
          backRoute: state.uri.queryParameters['source'] == 'role'
              ? '/choose-role'
              : null,
        ),
      ),
      GoRoute(
        path: '/customer-login',
        builder: (_, __) => const CustomerExperienceTheme(
          child: CustomerLoginScreen(),
        ),
        routes: [
          GoRoute(
            path: 'phone',
            builder: (_, state) => CustomerExperienceTheme(
              child: PhoneAuthScreen(
                actor: AuthActor.customer,
                backRoute: state.uri.queryParameters['source'] == 'role'
                    ? '/choose-role'
                    : null,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/customer-disabled',
        builder: (_, __) => const CustomerExperienceTheme(
          child: CustomerFeatureDisabledScreen(),
        ),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminPortalShell(
          section: AdminPortalSection.overview,
        ),
        routes: [
          GoRoute(
            path: 'merchants',
            builder: (_, __) => const AdminPortalShell(
              section: AdminPortalSection.merchants,
            ),
          ),
          GoRoute(
            path: 'merchants/:merchantId',
            builder: (_, state) => AdminPortalShell(
              section: AdminPortalSection.merchants,
              merchantId: state.pathParameters['merchantId'] ?? '',
            ),
          ),
          GoRoute(
            path: 'plans',
            builder: (_, __) => const AdminPortalShell(
              section: AdminPortalSection.plans,
            ),
          ),
          GoRoute(
            path: 'operations',
            builder: (_, __) => const AdminPortalShell(
              section: AdminPortalSection.operations,
            ),
          ),
          GoRoute(
            path: 'self-service',
            builder: (_, __) => const AdminPortalShell(
              section: AdminPortalSection.selfService,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final args = state.extra as OtpScreenArgs;
          final screen = OTPVerificationScreen(
            phoneNumber: args.phone,
            verificationId: args.verificationId,
            actor: args.actor,
          );
          return args.actor == AuthActor.customer
              ? CustomerExperienceTheme(child: screen)
              : screen;
        },
      ),
      GoRoute(path: '/customer', redirect: (_, __) => '/customer/home'),
      ShellRoute(
        builder: (_, __, child) => CustomerExperienceTheme(
          child: CustomerShell(child: child),
        ),
        routes: [
          GoRoute(
            path: '/customer/home',
            builder: (_, __) => const CustomerHomeScreen(),
          ),
          GoRoute(
            path: '/customer/rewards',
            builder: (_, __) => const CustomerRewardsScreen(),
          ),
          GoRoute(
            path: '/customer/activity',
            builder: (_, __) => const CustomerActivityScreen(),
          ),
          GoRoute(
            path: '/customer/businesses',
            builder: (_, __) => const CustomerBusinessesScreen(),
          ),
          GoRoute(
            path: '/customer/profile',
            builder: (_, __) => const CustomerProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/customer/business/:businessId',
        builder: (_, state) => CustomerBusinessDetailScreen(
          businessId: state.pathParameters['businessId'] ?? '',
        ),
      ),
      GoRoute(
          path: '/customer/qr', builder: (_, __) => const CustomerQrScreen()),
      GoRoute(
        path: '/merchant/customer-qr',
        builder: (_, __) => const MerchantCustomerQrResolveScreen(),
      ),
      GoRoute(
        path: '/merchant/redemptions/validate',
        builder: (_, __) => const MerchantRedemptionValidationScreen(),
      ),
      GoRoute(
        path: '/customer/redeem/:rewardId',
        builder: (_, state) => CustomerRedeemScreen(
            rewardId: state.pathParameters['rewardId'] ?? ''),
      ),
      GoRoute(
        path: '/customer/preferences',
        builder: (_, __) => const CustomerPreferencesScreen(),
      ),
      GoRoute(
        path: '/customer/terms',
        builder: (_, __) => const TermsScreen(),
      ),
      GoRoute(
        path: '/customer/privacy',
        builder: (_, __) => const PrivacyScreen(),
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
      GoRoute(
        path: '/merchant-onboarding/type',
        builder: (_, state) => BusinessTypePage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/info',
        builder: (_, state) => BusinessInfoPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/location',
        builder: (_, state) => BusinessLocationPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/hours',
        builder: (_, state) => WorkingHoursPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/services',
        builder: (_, state) => ServicesPage(
          returnRoute: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: '/merchant-onboarding/review',
        builder: (_, __) => const ReviewPage(),
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
        path: '/catalog',
        builder: (_, __) => const MerchantCatalogScreen(),
      ),
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
        path: '/settings/support-diagnostics',
        builder: (_, __) => const SupportDiagnosticsScreen(),
      ),
      GoRoute(
        path: '/staff-management',
        builder: (_, __) => const StaffManagementScreen(),
      ),
      GoRoute(
        path: '/subscription-admin',
        builder: (_, __) => const SubscriptionAdminScreen(),
      ),
      GoRoute(
        path: featureUpsellRoutePath,
        builder: (_, state) {
          final extra = state.extra;
          return FeatureUpsellScreen(
            args: extra is FeatureUpsellArgs
                ? extra
                : FeatureUpsellArgs.fromQuery(state.uri.queryParameters),
          );
        },
      ),
      GoRoute(
        path: '/merchant-config',
        redirect: (_, __) => merchantOnboardingStartRoute,
      ),
      GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Página não encontrada: ${state.error}')),
    ),
  );
});
