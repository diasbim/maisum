import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'providers.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/otp_verification_screen.dart';
import '../features/auth/presentation/phone_auth_screen.dart';
import '../features/auth/presentation/pin_entry_screen.dart';
import '../features/auth/presentation/pin_setup_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/customers/presentation/customer_list_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/rewards/presentation/create_reward_screen.dart';
import '../features/rewards/presentation/rewards_screen.dart';
import '../features/retention/presentation/retention_dashboard_screen.dart';
import '../features/sales/presentation/new_sale_screen.dart';
import '../features/sales/presentation/sales_history_screen.dart';
import '../features/sales/presentation/sale_success_screen.dart';
import '../features/legal/presentation/privacy_screen.dart';
import '../features/legal/presentation/terms_screen.dart';
import '../features/onboarding/presentation/sms_permission_screen.dart';
import '../features/settings/presentation/merchant_config_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/appointments/presentation/appointments_screen.dart';
import '../features/subscription/presentation/subscription_admin_screen.dart';
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

const _smsPermissionRoute = '/sms-permission';

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
        return hasPin ? '/pin-entry' : '/pin-setup';
      }
      if (isAuthenticated && state.matchedLocation != _smsPermissionRoute) {
        final prompted = await ref
            .read(secureStorageServiceProvider)
            .hasSmsPermissionPrompted();
        if (!prompted &&
            state.matchedLocation != '/privacy' &&
            state.matchedLocation != '/terms') {
          return _smsPermissionRoute;
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: _smsPermissionRoute,
        builder: (_, __) => const SmsPermissionScreen(),
      ),
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
      GoRoute(path: '/pin-setup', builder: (_, __) => const PinSetupScreen()),
      GoRoute(path: '/pin-entry', builder: (_, __) => const PinEntryScreen()),
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
          GoRoute(path: 'new', builder: (_, __) => const CreateRewardScreen()),
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
        path: '/pending-sync',
        builder: (_, __) => const PendingSyncScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
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
