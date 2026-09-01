import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';

class _FakeCustomerRedemptionRepository extends Fake
    implements CustomerAppRepository {
  String? reissueId;
  final reissueKeys = <String>[];

  @override
  Future<Map<String, dynamic>?> redemptionRecord(String rewardId) async => {
        'status': 'completed',
        'reward_id': rewardId,
        'idempotency_key': 'customer_op_123',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'result': _receipt(CustomerRedemptionStatus.expired).toJson(),
      };

  @override
  Future<CustomerRedemptionReceipt> reissueRedemption({
    required String redemptionId,
    required String idempotencyKey,
  }) async {
    reissueId = redemptionId;
    reissueKeys.add(idempotencyKey);
    return _receipt(
      reissueKeys.length == 1
          ? CustomerRedemptionStatus.expired
          : CustomerRedemptionStatus.pending,
      generation: reissueKeys.length,
    );
  }

  @override
  Future<void> event(String eventType) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer can reissue a redemption after repeated expirations',
      (tester) async {
    final repository = _FakeCustomerRedemptionRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerAppRepositoryProvider.overrideWithValue(repository),
          customerFeatureFlagsProvider.overrideWith(
            (ref) async => _flags,
          ),
          customerRewardsProvider.overrideWith(
            (ref) async => CustomerData(
              const [_reward],
              fromCache: false,
              updatedAt: DateTime(2026, 9, 1),
            ),
          ),
          customerBusinessesProvider.overrideWith(
            (ref) async => CustomerData(
              const [_business],
              fromCache: false,
              updatedAt: DateTime(2026, 9, 1),
            ),
          ),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(
            child: CustomerRedeemScreen(rewardId: 'reward-1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Código expirado'), findsOneWidget);
    await tester.tap(find.text('Gerar novo código'));
    await tester.pumpAndSettle();

    expect(repository.reissueId, 'redemption-1');
    expect(repository.reissueKeys.single, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(find.text('Código expirado'), findsOneWidget);

    await tester.tap(find.text('Gerar novo código'));
    await tester.pumpAndSettle();

    expect(repository.reissueKeys, hasLength(2));
    expect(repository.reissueKeys.last, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(repository.reissueKeys.last, isNot(repository.reissueKeys.first));
    expect(find.text('Confirme no negócio'), findsOneWidget);
    expect(find.bySemanticsLabel('Código QR do resgate'), findsOneWidget);
    expect(find.text('Copiar código'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _flags = CustomerFeatureFlags(
  appEnabled: true,
  redemptionEnabled: true,
  qrEnabled: true,
  pushEnabled: true,
  deepLinksEnabled: true,
);

const _reward = CustomerReward(
  id: 'reward-1',
  businessId: 'business-1',
  name: 'Café grátis',
  description: null,
  pointsRequired: 500,
  confirmedPoints: 0,
  pointsRemaining: 500,
  eligible: false,
);

const _business = CustomerBusiness(
  id: 'business-1',
  name: 'Café Central',
  address: 'Maputo',
  phone: null,
  confirmedPoints: 0,
  rewards: [_reward],
);

CustomerRedemptionReceipt _receipt(
  CustomerRedemptionStatus status, {
  int generation = 0,
}) {
  return CustomerRedemptionReceipt(
    id: 'redemption-1',
    businessId: 'business-1',
    rewardId: 'reward-1',
    code: status == CustomerRedemptionStatus.expired
        ? 'r1_expired${generation}abcdefghijklmnop'
        : 'r1_fresh${generation}abcdefghijklmnopqr',
    pointsSpent: 500,
    confirmedPoints: 0,
    redeemedAt: DateTime(2026, 9, 1, 10),
    codeExpiresAt: status == CustomerRedemptionStatus.expired
        ? DateTime.now().subtract(const Duration(minutes: 1))
        : DateTime.now().add(const Duration(minutes: 15)),
    status: status,
  );
}
