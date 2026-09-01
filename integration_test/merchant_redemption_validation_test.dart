import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/merchant_redemption_service.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/merchant_redemption_validation_screen.dart';

class _FakeMerchantRedemptionService extends Fake
    implements MerchantRedemptionService {
  String? resolvedCode;
  String? consumedCode;
  String? idempotencyKey;

  @override
  Future<MerchantRedemptionPreview> resolve(String redemptionCode) async {
    resolvedCode = redemptionCode;
    return _preview(CustomerRedemptionStatus.pending);
  }

  @override
  Future<MerchantRedemptionPreview> consume({
    required String redemptionCode,
    required String idempotencyKey,
  }) async {
    consumedCode = redemptionCode;
    this.idempotencyKey = idempotencyKey;
    return _preview(CustomerRedemptionStatus.consumed);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('merchant validates and consumes a customer redemption',
      (tester) async {
    final service = _FakeMerchantRedemptionService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRedemptionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(
            child: MerchantRedemptionValidationScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'r1_abcdefghijklmnopqrstuvwx',
    );
    await tester.tap(find.text('Validar código'));
    await tester.pumpAndSettle();

    expect(service.resolvedCode, 'r1_abcdefghijklmnopqrstuvwx');
    expect(find.text('Café grátis'), findsOneWidget);
    expect(find.text('Ana Mucavele · 500 pts'), findsOneWidget);
    expect(find.text('Pronto para confirmar'), findsOneWidget);

    await tester.tap(find.text('Confirmar utilização'));
    await tester.pumpAndSettle();

    expect(service.consumedCode, 'r1_abcdefghijklmnopqrstuvwx');
    expect(service.idempotencyKey, isNotEmpty);
    expect(find.text('Já utilizado'), findsOneWidget);
    expect(find.text('Confirmar utilização'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

MerchantRedemptionPreview _preview(CustomerRedemptionStatus status) {
  return MerchantRedemptionPreview(
    receipt: CustomerRedemptionReceipt(
      id: 'redemption-1',
      businessId: 'm1',
      rewardId: 'reward-1',
      code: 'r1_abcdefghijklmnopqrstuvwx',
      pointsSpent: 500,
      confirmedPoints: 250,
      redeemedAt: DateTime(2026, 9, 1, 10),
      codeExpiresAt: DateTime(2026, 9, 1, 10, 15),
      status: status,
      consumedAt: status == CustomerRedemptionStatus.consumed
          ? DateTime(2026, 9, 1, 10, 5)
          : null,
    ),
    customerName: 'Ana Mucavele',
    customerPhone: '841234567',
    rewardName: 'Café grátis',
    businessName: 'Café Central',
    idempotentReplay: false,
  );
}
