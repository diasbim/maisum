import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/affiliates/providers/affiliate_providers.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';

/// The two facts the sale flow reads before it changes anything.
///
/// Both default to "no". A business that has not switched affiliates on, and a
/// device that cannot yet name itself, are normal states during rollout, and in
/// both the till has to behave exactly as it did before rather than guess.
void main() {
  group('affiliate config', () {
    test('is off for a business that has never configured it', () {
      final config = AffiliateFeatureConfig.fromBusinessData(
        const <String, dynamic>{},
      );

      expect(config.enabled, isFalse);
      expect(config.rewardApprovalRequired, isTrue);
      expect(config.returnWindowDays, 30);
    });

    test('reads the stored switches', () {
      final config = AffiliateFeatureConfig.fromBusinessData(
        const <String, dynamic>{
          'affiliate_config': <String, dynamic>{
            'enabled': true,
            'first_sale_reward_points': 100,
            'return_reward_enabled': true,
            'return_reward_points': 50,
            'return_window_days': 45,
            'reward_approval_required': false,
            'notifications_enabled': false,
          },
        },
      );

      expect(config.enabled, isTrue);
      expect(config.firstSaleRewardPoints, 100);
      expect(config.returnRewardEnabled, isTrue);
      expect(config.returnRewardPoints, 50);
      expect(config.returnWindowDays, 45);
      expect(config.rewardApprovalRequired, isFalse);
      expect(config.notificationsEnabled, isFalse);
    });

    test('ignores a malformed config rather than half-reading it', () {
      final config = AffiliateFeatureConfig.fromBusinessData(
        const <String, dynamic>{'affiliate_config': 'enabled'},
      );

      expect(config.enabled, isFalse);
    });
  });

  group('referred sale repository', () {
    test('is unavailable until the device has an identity', () {
      final container = ProviderContainer(
        overrides: <Override>[
          activeMerchantIdProvider.overrideWithValue('shop-1'),
          activeDeviceIdProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      // No repository rather than one with a placeholder device: the device id
      // is half of the commit's idempotency key, so a stand-in would let two
      // tills share a key and resolve to each other's sale.
      expect(container.read(affiliateSaleRepositoryProvider), isNull);
    });

    test('is unavailable without a merchant session', () {
      final container = ProviderContainer(
        overrides: <Override>[
          activeMerchantIdProvider.overrideWithValue(null),
          activeDeviceIdProvider.overrideWithValue('till-1'),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(affiliateSaleRepositoryProvider), isNull);
    });

    test('exists once both identities are resolved', () {
      final container = ProviderContainer(
        overrides: <Override>[
          activeMerchantIdProvider.overrideWithValue('shop-1'),
          activeDeviceIdProvider.overrideWithValue('till-1'),
          activeAppUserIdProvider.overrideWithValue('user-1'),
          // Stands in for the Firebase token resolver, which needs an
          // initialised app this test has no use for.
          affiliateAccessTokenResolverProvider.overrideWithValue(
            () async => 'token',
          ),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(affiliateSaleRepositoryProvider);
      expect(repository, isNotNull);
      expect(repository!.merchantId, 'shop-1');
      expect(repository.deviceId, 'till-1');
    });
  });
}
