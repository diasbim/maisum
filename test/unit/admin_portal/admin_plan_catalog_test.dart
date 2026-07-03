import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/admin_portal/domain/admin_plan_catalog.dart';

void main() {
  group('AdminPlanCatalogItem.fromJson', () {
    test('parses plan catalog rows with prices and features', () {
      final item = AdminPlanCatalogItem.fromJson({
        'plan_code': ' pro ',
        'version': '3',
        'name': ' Pro ',
        'is_active': 'true',
        'created_at': 1710000000000,
        'updated_at': '1710001000000',
        'prices': [
          {
            'pricing_version': 2.0,
            'currency': 'MZN',
            'amount': '1499',
            'billing_period': 'monthly',
            'is_active': 1,
            'created_at': 1710002000000,
            'updated_at': '2026-07-03T12:00:00.000Z',
          },
        ],
        'features': [
          {
            'feature_key': 'analytics',
            'is_enabled': true,
            'limit_value': '3000',
            'unit': 'monthly',
            'updated_at': 1710003000000,
          },
        ],
      });

      expect(item.planCode, 'pro');
      expect(item.version, 3);
      expect(item.name, 'Pro');
      expect(item.isActive, isTrue);
      expect(item.createdAt.millisecondsSinceEpoch, 1710000000000);
      expect(item.updatedAt.millisecondsSinceEpoch, 1710001000000);
      expect(item.prices, hasLength(1));
      expect(item.prices.first.pricingVersion, 2);
      expect(item.prices.first.currency, 'MZN');
      expect(item.prices.first.amount, 1499);
      expect(item.prices.first.isActive, isTrue);
      expect(
        item.prices.first.updatedAt,
        DateTime.parse('2026-07-03T12:00:00.000Z'),
      );
      expect(item.features, hasLength(1));
      expect(item.features.first.featureKey, 'analytics');
      expect(item.features.first.isEnabled, isTrue);
      expect(item.features.first.limitValue, 3000);
      expect(item.features.first.unit, 'monthly');
    });

    test('uses safe defaults for absent optional arrays', () {
      final item = AdminPlanCatalogItem.fromJson({});

      expect(item.planCode, isEmpty);
      expect(item.version, 0);
      expect(item.name, 'Plan');
      expect(item.isActive, isFalse);
      expect(item.prices, isEmpty);
      expect(item.features, isEmpty);
    });
  });
}
