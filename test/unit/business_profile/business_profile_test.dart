import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/business_profile/domain/business_profile.dart';

void main() {
  group('BusinessProfiles', () {
    test('unknown and missing types use the neutral profile', () {
      expect(BusinessProfiles.resolve(null), same(BusinessProfiles.generic));
      expect(
        BusinessProfiles.resolve('custom_remote_type'),
        same(BusinessProfiles.generic),
      );
    });

    test('barbershop remains an appointment-enabled preset', () {
      final profile = BusinessProfiles.resolve('barbershop');

      expect(profile.id, 'barbershop');
      expect(profile.capabilities.appointments, isTrue);
      expect(profile.itemPresets.map((item) => item.id), contains('haircut'));
    });

    test('retail supports products without forcing appointments', () {
      final profile = BusinessProfiles.resolve('retail');

      expect(profile.capabilities.products, isTrue);
      expect(profile.capabilities.services, isFalse);
      expect(profile.capabilities.appointments, isFalse);
    });

    test('legacy labels resolve to their compatible profile', () {
      expect(BusinessProfiles.resolve('Barbearia').id, 'barbershop');
      expect(BusinessProfiles.resolve('Salao de beleza').id, 'salon');
    });

    test('legacy businesses keep the original barbershop behavior', () {
      expect(
        BusinessProfiles.resolveBusinessData({
          'merchant_name': 'Legacy business',
        }).id,
        'barbershop',
      );
      expect(
        BusinessProfiles.resolveBusinessData({
          'merchant_name': 'New business',
          'business_profile_version': 1,
        }).id,
        'other',
      );
    });

    test('merchant overrides customize loyalty, retention, and appointments',
        () {
      final profile = BusinessProfiles.resolve('retail').withMerchantOverrides({
        'loyalty_config': {
          'points_per_mzn': 50,
          'quick_amounts': [50, 250],
        },
        'retention_config': {
          'active_days': 10,
          'attention_days': 20,
          'risk_days': 40,
        },
        'appointment_config': {
          'default_hour': 8,
          'quick_intervals_days': [3, 7],
        },
      });

      expect(profile.loyalty.pointsPerMzn, 50);
      expect(profile.loyalty.quickAmounts, [50, 250]);
      expect(profile.retention.riskDays, 40);
      expect(profile.defaultAppointmentHour, 8);
      expect(profile.appointmentIntervalsDays, [3, 7]);
    });
  });
}
