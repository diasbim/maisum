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

    test('local business expansion profiles have coherent defaults', () {
      final expectedProfiles = {
        'car_wash': (
          label: 'Lavagem Automóvel',
          iconKey: 'car_wash',
          services: true,
          products: true,
          appointments: true,
          intervals: [7, 14, 30, 60],
          presets: [
            'basic_wash',
            'interior_cleaning',
            'polishing',
            'air_freshener',
          ],
        ),
        'laundry': (
          label: 'Lavandaria',
          iconKey: 'laundry',
          services: true,
          products: false,
          appointments: true,
          intervals: [7, 14, 30],
          presets: ['wash_and_fold', 'dry_cleaning', 'ironing'],
        ),
        'bakery': (
          label: 'Padaria',
          iconKey: 'bakery',
          services: false,
          products: true,
          appointments: false,
          intervals: [7, 14, 30],
          presets: ['bread', 'cake', 'pastry'],
        ),
        'pharmacy': (
          label: 'Farmácia',
          iconKey: 'pharmacy',
          services: true,
          products: true,
          appointments: false,
          intervals: [7, 14, 30],
          presets: ['medicine', 'health_product', 'basic_care'],
        ),
        'pet_care': (
          label: 'Pet care',
          iconKey: 'pet_care',
          services: true,
          products: true,
          appointments: true,
          intervals: [14, 30, 60, 90],
          presets: ['pet_bath', 'grooming', 'pet_food'],
        ),
        'tailoring': (
          label: 'Alfaiataria',
          iconKey: 'tailoring',
          services: true,
          products: true,
          appointments: true,
          intervals: [7, 14, 30, 90],
          presets: ['adjustment', 'custom_clothing', 'clothing_repair'],
        ),
        'phone_repair': (
          label: 'Reparação de Telemóveis',
          iconKey: 'phone_repair',
          services: true,
          products: true,
          appointments: true,
          intervals: [7, 30, 90, 180],
          presets: [
            'screen_replacement',
            'battery_replacement',
            'phone_accessory',
          ],
        ),
      };

      for (final MapEntry(key: id, value: expected)
          in expectedProfiles.entries) {
        final profile = BusinessProfiles.resolve(id);

        expect(profile.id, id);
        expect(profile.label, expected.label);
        expect(profile.iconKey, expected.iconKey);
        expect(profile.capabilities.services, expected.services);
        expect(profile.capabilities.products, expected.products);
        expect(profile.capabilities.appointments, expected.appointments);
        expect(profile.retention.activeDays,
            lessThan(profile.retention.attentionDays));
        expect(profile.retention.attentionDays,
            lessThan(profile.retention.riskDays));
        expect(profile.appointmentIntervalsDays, expected.intervals);
        expect(
          profile.itemPresets.map((item) => item.id),
          expected.presets,
        );
      }
    });

    test('legacy labels resolve to their compatible profile', () {
      expect(BusinessProfiles.resolve('Barbearia').id, 'barbershop');
      expect(BusinessProfiles.resolve('Salao de beleza').id, 'salon');
    });

    test('new profile labels and aliases resolve to built-in profiles', () {
      expect(BusinessProfiles.resolve('Lavagem Automovel').id, 'car_wash');
      expect(BusinessProfiles.resolve('lava car').id, 'car_wash');
      expect(BusinessProfiles.resolve('Lavanderia').id, 'laundry');
      expect(BusinessProfiles.resolve('dry cleaning').id, 'laundry');
      expect(BusinessProfiles.resolve('Panificadora').id, 'bakery');
      expect(BusinessProfiles.resolve('Farmacia').id, 'pharmacy');
      expect(BusinessProfiles.resolve('Drogaria').id, 'pharmacy');
      expect(BusinessProfiles.resolve('Cuidados de animais').id, 'pet_care');
      expect(BusinessProfiles.resolve('Pet shop').id, 'pet_care');
      expect(BusinessProfiles.resolve('Costura').id, 'tailoring');
      expect(BusinessProfiles.resolve('Reparacao de telemoveis').id,
          'phone_repair');
      expect(BusinessProfiles.resolve('phone repair').id, 'phone_repair');
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
