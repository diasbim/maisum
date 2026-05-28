import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/appointments/domain/appointment.dart';
import 'package:maisum/features/appointments/providers/appointments_providers.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/rewards/domain/reward.dart';
import 'package:maisum/features/rewards/presentation/rewards_controller.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:maisum/features/sales/presentation/sale_success_screen.dart';
import 'package:maisum/features/subscription/data/subscription_dao.dart';
import 'package:maisum/features/subscription/services/feature_gate.dart';
import 'package:maisum/features/subscription/services/usage_quota_engine.dart';

class _FakeRewardsController extends RewardsController {
  @override
  Future<List<Reward>> build() async => const <Reward>[];
}

class _FakeCreateAppointmentController extends CreateAppointmentController {
  @override
  Future<Appointment?> build() async => null;
}

class _FakeFeatureGate extends FeatureGate {
  _FakeFeatureGate({required this.delay})
      : super(
          SubscriptionDao(AppDatabase.instance),
          UsageQuotaEngine(SubscriptionDao(AppDatabase.instance)),
        );

  final Duration delay;

  @override
  Future<GateDecision> check({
    required String featureKey,
    String? metricKey,
  }) async {
    await Future<void>.delayed(delay);
    return const GateDecision(allowed: true, status: 'ACTIVE');
  }
}

Customer _customer() => Customer(
      id: 'customer-1',
      name: 'Ana Costa',
      phone: '841000001',
      totalPoints: 15,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 2),
    );

SaleResult _saleResult() => SaleResult(
      sale: Sale(
        id: 'sale-1',
        customerId: 'customer-1',
        amount: 250,
        points: 3,
        createdAt: DateTime(2024, 1, 1),
      ),
      customer: _customer(),
    );

Widget _buildScreen() {
  final connectivity = ConnectivityService(
    initialOnline: true,
    onConnectivityChanged: Stream<List<ConnectivityResult>>.empty(),
    checkConnectivity: () async => [ConnectivityResult.wifi],
  );

  return ProviderScope(
    overrides: [
      rewardsControllerProvider.overrideWith(_FakeRewardsController.new),
      createAppointmentProvider.overrideWith(
        _FakeCreateAppointmentController.new,
      ),
      featureGateProvider.overrideWithValue(
        _FakeFeatureGate(delay: const Duration(milliseconds: 250)),
      ),
      connectivityServiceProvider.overrideWithValue(connectivity),
    ],
    child: MaterialApp(
      home: SaleSuccessScreen(args: SaleSuccessArgs(result: _saleResult())),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SaleSuccessScreen — WhatsApp lock', () {
    testWidgets('double tap triggers a single send path while loading', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      var launchCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch' || call.method == 'launchUrl') {
          launchCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return false;
        }
        if (call.method == 'canLaunch' || call.method == 'canLaunchUrl') {
          return true;
        }
        return true;
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      final whatsappButton = find.widgetWithText(
        ElevatedButton,
        AppStrings.enviarWhatsApp,
      );

      await tester.ensureVisible(whatsappButton);
      await tester.tap(whatsappButton, warnIfMissed: false);
      await tester.pump();

      expect(find.text('A enviar...'), findsOneWidget);
      final loadingButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'A enviar...'),
      );
      expect(loadingButton.onPressed, isNull);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'A enviar...'),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(find.text('A enviar...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      expect(launchCalls, 1);
      expect(
        find.widgetWithText(ElevatedButton, AppStrings.enviarWhatsApp),
        findsOneWidget,
      );
      final restoredButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, AppStrings.enviarWhatsApp),
      );
      expect(restoredButton.onPressed, isNotNull);
    });
  });
}
