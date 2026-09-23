import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/data/customer_platform_service.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';

const _profile = CustomerProfile(
  displayName: 'Ana Mucavele',
  phone: '+258820000001',
  linkedBusinessCount: 2,
  preferences: CustomerPreferences(
    notificationsEnabled: true,
    marketingEnabled: false,
    deepLinksEnabled: true,
  ),
);

CustomerData<CustomerProfile> _profileData() => CustomerData(
      _profile,
      fromCache: false,
      updatedAt: DateTime(2025),
    );

CustomerData<Map<String, dynamic>> _notificationsData(String delivery) =>
    CustomerData(
      {
        'push': {'enabled': true, 'delivery': delivery},
      },
      fromCache: false,
      updatedAt: DateTime(2025),
    );

class _FakeAuthController extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        userId: 'customer-1',
        firebaseUid: 'customer-1',
        phone: '+258820000001',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        actor: AuthActor.customer,
      );
}

/// Fake platform service whose [synchronize] call flips [becomesConfigured]
/// so the test can simulate "the retry actually fixed it" vs. "still broken".
class _FakePlatformService extends Fake implements CustomerPlatformService {
  _FakePlatformService({required this.becomesConfigured});
  final bool becomesConfigured;
  int synchronizeCalls = 0;

  @override
  Future<void> synchronize(AuthSession? session) async {
    synchronizeCalls++;
  }
}

Widget _buildScreen({
  required String initialDelivery,
  required bool becomesConfigured,
}) {
  var delivery = initialDelivery;
  final platformService = _FakePlatformService(
    becomesConfigured: becomesConfigured,
  );
  return ProviderScope(
    overrides: [
      customerProfileProvider.overrideWith((ref) async => _profileData()),
      customerNotificationsProvider.overrideWith((ref) async {
        if (platformService.synchronizeCalls > 0 && becomesConfigured) {
          delivery = 'configured';
        }
        return _notificationsData(delivery);
      }),
      authControllerProvider.overrideWith(() => _FakeAuthController()),
      customerPlatformServiceProvider.overrideWithValue(platformService),
    ],
    child: const MaterialApp(
      home: CustomerExperienceTheme(
        child: CustomerProfileScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'push retry that succeeds tells the customer notifications are now on',
    (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          initialDelivery: 'not_configured',
          becomesConfigured: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Toque para tentar ativar.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Notificações push'));

      // Drain the async retry chain (synchronize -> invalidate -> re-fetch)
      // before letting the final SnackBar's own animation settle: pumpAndSettle
      // alone only waits out scheduled *frames*, not unrelated pending Futures.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(
        find.text('Notificações ativadas neste dispositivo.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'push retry that fails tells the customer to check phone settings',
    (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          initialDelivery: 'not_configured',
          becomesConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notificações push'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Continuam indisponíveis. Ative as notificações nas definições do telemóvel para o MaisUm.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'already-working push notifications open preferences instead of retrying',
    (tester) async {
      await tester.pumpWidget(
        _buildScreen(initialDelivery: 'configured', becomesConfigured: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ativas neste dispositivo.'), findsOneWidget);
      expect(find.textContaining('Toque para tentar ativar.'), findsNothing);
    },
  );
}
