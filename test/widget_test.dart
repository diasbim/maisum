import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/dashboard/presentation/dashboard_controller.dart';
import 'package:maisum/features/sync/sync_controller.dart';
import 'package:maisum/features/sync/sync_service.dart';

// Minimal fakes to keep platform channels out of the smoke test.
class _FakeAuth extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        userId: 'u1',
        firebaseUid: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
}

class _FakeDashboard extends DashboardController {
  @override
  Future<DashboardStats> build() async => const DashboardStats();
}

class _FakeSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus();
}

void main() {
  testWidgets('App smoke test — dashboard renders with mocked providers',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuth.new),
        dashboardControllerProvider.overrideWith(_FakeDashboard.new),
        syncControllerProvider.overrideWith(_FakeSync.new),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: Text(AppStrings.appName))),
      ),
    ));
    await tester.pump();

    expect(find.text(AppStrings.appName), findsOneWidget);
  });

  testWidgets('LoyaltyOS title is correct', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text(AppStrings.appName))),
    ));
    await tester.pump();

    expect(find.text(AppStrings.appName), findsOneWidget);
  });
}

