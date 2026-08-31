import 'package:flutter/foundation.dart';

import 'customer_models.dart';

const customerDemoDataEnabled = bool.fromEnvironment(
  'CUSTOMER_DEMO_DATA',
  defaultValue: kDebugMode,
);

class CustomerDemoData {
  const CustomerDemoData._();

  static const coffeeReward = CustomerReward(
    id: 'demo-reward-coffee',
    businessId: 'demo-cafe-acacia',
    name: 'Café e pastel grátis',
    description: 'Escolha um café e um pastel do dia.',
    pointsRequired: 500,
    confirmedPoints: 1250,
    pointsRemaining: 0,
    eligible: true,
  );
  static const brunchReward = CustomerReward(
    id: 'demo-reward-brunch',
    businessId: 'demo-cafe-acacia',
    name: 'Brunch para duas pessoas',
    description: 'Uma experiência de brunch para partilhar.',
    pointsRequired: 1500,
    confirmedPoints: 1250,
    pointsRemaining: 250,
    eligible: false,
  );
  static const pharmacyReward = CustomerReward(
    id: 'demo-reward-pharmacy',
    businessId: 'demo-farmacia-vida',
    name: '10% de desconto',
    description: 'Desconto numa compra à sua escolha.',
    pointsRequired: 600,
    confirmedPoints: 680,
    pointsRemaining: 0,
    eligible: true,
  );
  static const wellnessReward = CustomerReward(
    id: 'demo-reward-wellness',
    businessId: 'demo-farmacia-vida',
    name: 'Kit de bem-estar',
    description: 'Uma seleção exclusiva de produtos de cuidado.',
    pointsRequired: 1200,
    confirmedPoints: 680,
    pointsRemaining: 520,
    eligible: false,
  );
  static const barberReward = CustomerReward(
    id: 'demo-reward-barber',
    businessId: 'demo-barbearia-25',
    name: 'Corte premium',
    description: 'Corte, lavagem e finalização.',
    pointsRequired: 800,
    confirmedPoints: 340,
    pointsRemaining: 460,
    eligible: false,
  );

  static const rewards = [
    coffeeReward,
    brunchReward,
    pharmacyReward,
    wellnessReward,
    barberReward,
  ];

  static const businesses = [
    CustomerBusiness(
      id: 'demo-cafe-acacia',
      name: 'Café Acácia',
      address: 'Av. Julius Nyerere, Maputo',
      phone: '+258 84 123 4567',
      confirmedPoints: 1250,
      rewards: [coffeeReward, brunchReward],
    ),
    CustomerBusiness(
      id: 'demo-farmacia-vida',
      name: 'Farmácia Vida',
      address: 'Av. 24 de Julho, Maputo',
      phone: '+258 82 765 4321',
      confirmedPoints: 680,
      rewards: [pharmacyReward, wellnessReward],
    ),
    CustomerBusiness(
      id: 'demo-barbearia-25',
      name: 'Barbearia 25',
      address: 'Av. Eduardo Mondlane, Maputo',
      phone: '+258 86 246 8100',
      confirmedPoints: 340,
      rewards: [barberReward],
    ),
  ];

  static final activity = [
    CustomerActivity(
      id: 'demo-activity-1',
      businessId: 'demo-cafe-acacia',
      type: 'SALE',
      pointsDelta: 250,
      occurredAt: DateTime(2026, 8, 30, 9, 35),
    ),
    CustomerActivity(
      id: 'demo-activity-2',
      businessId: 'demo-farmacia-vida',
      type: 'SALE',
      pointsDelta: 120,
      occurredAt: DateTime(2026, 8, 28, 17, 10),
    ),
    CustomerActivity(
      id: 'demo-activity-3',
      businessId: 'demo-cafe-acacia',
      type: 'REDEEM',
      pointsDelta: -500,
      occurredAt: DateTime(2026, 8, 24, 10, 5),
    ),
    CustomerActivity(
      id: 'demo-activity-4',
      businessId: 'demo-barbearia-25',
      type: 'SALE',
      pointsDelta: 340,
      occurredAt: DateTime(2026, 8, 20, 14, 45),
    ),
    CustomerActivity(
      id: 'demo-activity-5',
      businessId: 'demo-cafe-acacia',
      type: 'SALE',
      pointsDelta: 500,
      occurredAt: DateTime(2026, 8, 16, 8, 20),
    ),
  ];

  static CustomerProfile profileFrom(CustomerProfile profile) =>
      CustomerProfile(
        displayName: profile.displayName ?? 'Ana Mucavele',
        phone: profile.phone,
        linkedBusinessCount: businesses.length,
        preferences: profile.preferences,
      );

  static CustomerBusiness? businessById(String id) {
    for (final business in businesses) {
      if (business.id == id) return business;
    }
    return null;
  }
}
