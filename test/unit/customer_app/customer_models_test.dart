import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';

void main() {
  test('parses customer business and reward DTOs', () {
    final business = CustomerBusiness.fromJson({
      'business_id': 'm1',
      'name': 'Café',
      'confirmed_points': 12,
      'rewards': [
        {
          'reward_id': 'r1',
          'name': 'Café grátis',
          'points_required': 10,
          'confirmed_points': 12,
          'points_remaining': 0,
          'eligible': true,
        }
      ],
    });
    expect(business.id, 'm1');
    expect(business.rewards.single.eligible, isTrue);
    expect(business.rewards.single.businessId, 'm1');
  });

  test('parses customer session flags', () {
    final session = CustomerSessionDto.fromJson({
      'phone_e164': '+258841234567',
      'feature_flags': {
        'customer_app_enabled': true,
        'customer_redemption_enabled': true,
        'customer_qr_enabled': false,
        'customer_push_enabled': false,
        'customer_deep_links_enabled': true,
      },
      'business_relationships': [],
    });
    expect(session.flags.appEnabled, isTrue);
    expect(session.flags.qrEnabled, isFalse);
  });

  test('customer actor does not resolve a merchant identifier', () {
    final session = AuthSession(
      userId: 'uid-customer',
      phone: '+258841234567',
      expiresAt: DateTime(2030),
      actor: AuthActor.customer,
    );
    expect(session.merchantId, isNull);
    expect(session.resolvedMerchantId, isEmpty);
  });
}
