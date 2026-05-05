import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/features/customers/domain/customer.dart';
import 'package:loyalty_app/features/customers/domain/customer_whatsapp_message.dart';
import 'package:loyalty_app/features/rewards/domain/reward.dart';
import 'package:loyalty_app/features/sales/domain/sale.dart';

Customer _customer({int points = 0}) => Customer(
      id: 'c1',
      name: 'Ana Costa',
      phone: '841000001',
      totalPoints: points,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 2),
    );

Reward _reward(String id, String name, int pointsRequired) => Reward(
      id: id,
      name: name,
      pointsRequired: pointsRequired,
      createdAt: DateTime(2024, 1, 1),
    );

Sale _sale(DateTime createdAt) => Sale(
      id: 's-${createdAt.millisecondsSinceEpoch}',
      customerId: 'c1',
      amount: 500,
      points: 5,
      createdAt: createdAt,
    );

void main() {
  group('buildCustomerWhatsAppDraft', () {
    test('prioritizes unlocked reward messaging', () {
      final draft = buildCustomerWhatsAppDraft(
        customer: _customer(points: 25),
        sales: [_sale(DateTime(2026, 5, 1))],
        rewards: [
          _reward('r1', 'Corte grátis', 20),
          _reward('r2', 'Barba grátis', 30),
        ],
        now: DateTime(2026, 5, 5),
      );

      expect(draft.type, CustomerWhatsAppMessageType.rewardUnlocked);
      expect(draft.message, contains('Corte grátis'));
    });

    test('uses near-reward messaging when threshold is close', () {
      final draft = buildCustomerWhatsAppDraft(
        customer: _customer(points: 18),
        sales: [_sale(DateTime(2026, 5, 3))],
        rewards: [_reward('r1', 'Corte grátis', 20)],
        now: DateTime(2026, 5, 5),
      );

      expect(draft.type, CustomerWhatsAppMessageType.nearReward);
      expect(draft.message, contains('faltam só 2 pontos'));
    });

    test('falls back to inactive recovery when last sale is old', () {
      final draft = buildCustomerWhatsAppDraft(
        customer: _customer(points: 8),
        sales: [_sale(DateTime(2026, 3, 1))],
        rewards: [_reward('r1', 'Corte grátis', 30)],
        now: DateTime(2026, 5, 5),
      );

      expect(draft.type, CustomerWhatsAppMessageType.inactive);
      expect(draft.message, contains('sentimos a tua falta'));
    });

    test('uses welcome copy when customer has no sales yet', () {
      final draft = buildCustomerWhatsAppDraft(
        customer: _customer(points: 0),
        sales: const [],
        rewards: const [],
        now: DateTime(2026, 5, 5),
      );

      expect(draft.type, CustomerWhatsAppMessageType.welcome);
      expect(draft.message, contains('próxima visita'));
    });
  });
}
