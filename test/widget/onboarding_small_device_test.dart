import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/auth/presentation/otp_verification_screen.dart';
import 'package:maisum/features/auth/presentation/phone_auth_screen.dart';
import 'package:maisum/features/auth/presentation/pin_entry_screen.dart';
import 'package:maisum/features/auth/presentation/pin_setup_screen.dart';
import 'package:maisum/features/settings/presentation/merchant_config_screen.dart';
import 'package:maisum/features/subscription/domain/plan.dart';
import 'package:maisum/features/subscription/domain/subscription_snapshot.dart';
import 'package:maisum/features/subscription/domain/subscription_status.dart';
import 'package:maisum/features/subscription/domain/usage_quota.dart';
import 'package:maisum/features/subscription/presentation/onboarding_plan_selection_screen.dart';

import '../helpers/fake_secure_storage.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);

  AuthSession _session;

  @override
  Future<AuthSession?> build() async => _session;

  @override
  Future<AuthSession> updateMerchantName(String merchantName) async {
    _session = _session.copyWith(merchantName: merchantName);
    return _session;
  }

  @override
  Future<void> logout() async {}
}

class _FakeSubscriptionSnapshotController
    extends SubscriptionSnapshotController {
  _FakeSubscriptionSnapshotController(this.snapshot);

  final SubscriptionSnapshot snapshot;

  @override
  Future<SubscriptionSnapshot> build() async => snapshot;

  @override
  Future<void> refresh() async {}
}

class _InMemorySecureStorageService extends FakeSecureStorageService {
  bool _confirmed = true;

  void setPlanConfirmed(bool value) {
    _confirmed = value;
  }

  @override
  Future<void> setOnboardingPlanConfirmed(bool value) async {
    _confirmed = value;
  }

  @override
  Future<bool> hasConfirmedOnboardingPlan() async => _confirmed;
}

Future<int> _pumpSmallDevice(
  WidgetTester tester,
  Widget widget, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    KeyedSubtree(
      key: UniqueKey(),
      child: widget,
    ),
  );
  int settleFrames;
  if (settle) {
    settleFrames = await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 50));
    settleFrames = 1;
  }
  expect(tester.takeException(), isNull);
  return settleFrames;
}

void main() {
  group('Onboarding small-device layout', () {
    testWidgets('phone auth renders and key actions stay reachable',
        (tester) async {
      final frames = await _pumpSmallDevice(
        tester,
        const ProviderScope(
          child: MaterialApp(home: PhoneAuthScreen()),
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('send_code_button')));
      await tester.ensureVisible(find.byKey(const Key('google_auth_button')));

      await tester.enterText(find.byKey(const Key('phone_input')), '843262347');
      await tester.pump();

      expect(frames, lessThan(120));
      expect(find.byKey(const Key('send_code_button')), findsOneWidget);
      expect(find.byKey(const Key('google_auth_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('otp verification renders and verify action stays reachable',
        (tester) async {
      final frames = await _pumpSmallDevice(
        tester,
        const ProviderScope(
          child: MaterialApp(
            home: OTPVerificationScreen(
              phoneNumber: '+258841234567',
              verificationId: 'test-verification-id',
            ),
          ),
        ),
        settle: false,
      );

      await tester.ensureVisible(find.byKey(const Key('verify_button')));

      expect(frames, lessThan(120));
      expect(find.byKey(const Key('otp_input')), findsOneWidget);
      expect(find.byKey(const Key('verify_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pin setup and pin entry render without overflow',
        (tester) async {
      final storage = _InMemorySecureStorageService();
      await storage.savePinAttempts(1);

      final setupFrames = await _pumpSmallDevice(
        tester,
        ProviderScope(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(home: PinSetupScreen()),
        ),
      );
      expect(setupFrames, lessThan(120));
      expect(find.byType(PinSetupScreen), findsOneWidget);

      final entryFrames = await _pumpSmallDevice(
        tester,
        ProviderScope(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(home: PinEntryScreen()),
        ),
      );
      expect(entryFrames, lessThan(120));
      expect(find.byType(PinEntryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('merchant setup and onboarding plan render on small device',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final storage = _InMemorySecureStorageService()..setPlanConfirmed(false);
      final session = AuthSession(
        userId: 'user-1',
        merchantId: 'merchant-1',
        merchantName: 'Minha Loja',
        phone: '+258841234567',
        expiresAt: DateTime.now().add(const Duration(days: 3)),
      );

      await firestore.collection('businesses').doc('merchant-1').set({
        'merchant_name': 'Minha Loja',
        'phone': '+258841234567',
        'city': 'Maputo',
        'business_type': 'Barbearia',
      });

      final merchantFrames = await _pumpSmallDevice(
        tester,
        ProviderScope(
          overrides: [
            authControllerProvider
                .overrideWith(() => _FakeAuthController(session)),
            firestoreInstanceProvider.overrideWithValue(firestore),
            secureStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(home: MerchantConfigScreen()),
        ),
      );

      await tester.ensureVisible(find.text('Continuar'));
      expect(merchantFrames, lessThan(160));
      expect(find.text('Continuar'), findsOneWidget);

      final snapshot = SubscriptionSnapshot(
        plan: Plan.starter,
        status: SubscriptionStatus.active,
        entitlements: const [],
        flags: const [],
        usageBalances: const [],
        whatsappQuota: UsageQuotaSummary(
          metricKey: 'whatsapp_messages',
          used: 0,
          limit: 200,
          resetAt: DateTime.now().add(const Duration(days: 30)),
        ),
      );

      final planFrames = await _pumpSmallDevice(
        tester,
        ProviderScope(
          overrides: [
            subscriptionSnapshotProvider.overrideWith(
                () => _FakeSubscriptionSnapshotController(snapshot)),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(session)),
            secureStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(home: OnboardingPlanSelectionScreen()),
        ),
      );

      expect(planFrames, lessThan(160));
      expect(find.byType(OnboardingPlanSelectionScreen), findsOneWidget);
      expect(find.text('Escolha o seu plano'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
