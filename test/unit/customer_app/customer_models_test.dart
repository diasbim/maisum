import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/widgets/customer_components.dart';

void main() {
  test('parses customer business and reward DTOs', () {
    final business = CustomerBusiness.fromJson({
      'business_id': 'm1',
      'name': 'Café',
      'confirmed_points': 12,
      'logo_url': 'https://example.test/logo.png',
      'last_visit_at': 1893456000000,
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
      'next_reward': {
        'reward_id': 'r1',
        'name': 'Café grátis',
        'points_required': 10,
        'confirmed_points': 12,
        'points_remaining': 0,
        'eligible': true,
      },
    });
    expect(business.id, 'm1');
    expect(business.rewards.single.eligible, isTrue);
    expect(business.rewards.single.businessId, 'm1');
    expect(business.logoUrl, 'https://example.test/logo.png');
    expect(business.lastVisitAt,
        DateTime.fromMillisecondsSinceEpoch(1893456000000));
    expect(business.nextReward?.id, 'r1');
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

  test('parses reward expiry and activity reward context', () {
    final reward = CustomerReward.fromJson({
      'reward_id': 'r-expiring',
      'business_id': 'm1',
      'name': 'Benefício sazonal',
      'points_required': 500,
      'confirmed_points': 500,
      'points_remaining': 0,
      'eligible': true,
      'expires_at': 1893456000000,
    });

    final activity = CustomerActivity.fromJson({
      'entry_id': 'entry-1',
      'business_id': 'm1',
      'type': 'REDEMPTION',
      'points_delta': -500,
      'occurred_at': 1893456000000,
      'reward_id': 'r-expiring',
      'business_name': 'Café',
      'reward_name': 'Benefício sazonal',
    });

    expect(
        reward.expiresAt, DateTime.fromMillisecondsSinceEpoch(1893456000000));
    expect(activity.rewardId, 'r-expiring');
    expect(activity.businessName, 'Café');
    expect(activity.rewardName, 'Benefício sazonal');
  });

  test('expired reward is never presented as available', () {
    final reward = CustomerReward(
      id: 'expired',
      businessId: 'm1',
      name: 'Prémio expirado',
      description: null,
      pointsRequired: 100,
      confirmedPoints: 150,
      pointsRemaining: 0,
      eligible: true,
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    expect(customerRewardState(reward), CustomerRewardState.expired);
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
