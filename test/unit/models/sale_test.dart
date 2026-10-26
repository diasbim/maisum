import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/constants/app_constants.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';
import 'package:maisum/features/sales/domain/sale.dart';

void main() {
  final baseMap = <String, dynamic>{
    'id': 's1',
    'customer_id': 'c1',
    'amount': 200.0,
    'points': 2,
    'created_at': 1700000000000,
    'synced': 0,
  };

  group('saleFromMap', () {
    test('parses all fields', () {
      final s = saleFromMap(baseMap);
      expect(s.id, 's1');
      expect(s.customerId, 'c1');
      expect(s.amount, 200.0);
      expect(s.points, 2);
      expect(s.confirmationStatus, SaleConfirmationStatus.pending);
      expect(s.confirmedPoints, isNull);
      expect(s.synced, false);
      expect(s.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('amount as int is coerced to double', () {
      final s = saleFromMap({...baseMap, 'amount': 300});
      expect(s.amount, 300.0);
      expect(s.amount, isA<double>());
    });

    test('synced=1 → true',
        () => expect(saleFromMap({...baseMap, 'synced': 1}).synced, true));
    test('null synced → false',
        () => expect(saleFromMap({...baseMap, 'synced': null}).synced, false));
  });

  group('toDbMap', () {
    test('produces all expected keys', () {
      final keys = saleFromMap(baseMap).toDbMap().keys;
      expect(
          keys,
          containsAll([
            'id',
            'customer_id',
            'amount',
            'points',
            'created_at',
            'synced'
          ]));
    });

    test('synced bool → int', () {
      expect(saleFromMap({...baseMap, 'synced': 0}).toDbMap()['synced'], 0);
      expect(saleFromMap({...baseMap, 'synced': 1}).toDbMap()['synced'], 1);
    });

    test('client sync excludes server-owned confirmation fields', () {
      final sale = saleFromMap({
        ...baseMap,
        'confirmation_status': 'CONFIRMED',
        'confirmed_points': 2,
      });

      final syncMap = sale.toClientSyncMap();

      expect(syncMap['points'], 2);
      expect(syncMap, isNot(contains('confirmation_status')));
      expect(syncMap, isNot(contains('confirmed_points')));
    });
  });

  group('referral fields', () {
    final referredMap = <String, dynamic>{
      ...baseMap,
      'amount': 450.0,
      'gross_amount': 500.0,
      'referral_benefit_type': 'FIXED_AMOUNT',
      'referral_benefit_value': 50.0,
      'referral_benefit_amount': 50.0,
      'affiliate_code_id': 'ac1',
      'referral_status': 'ATTRIBUTED',
    };

    test('a sale with no code carries none of them', () {
      final sale = saleFromMap(baseMap);

      expect(sale.grossAmount, isNull);
      expect(sale.referralBenefitType, isNull);
      expect(sale.referralBenefitValue, isNull);
      expect(sale.referralBenefitAmount, isNull);
      expect(sale.affiliateCodeId, isNull);
      expect(sale.referralStatus, isNull);
      expect(sale.isReferred, isFalse);
      // A legacy row round-trips to null columns, not to missing keys.
      final db = sale.toDbMap();
      expect(db['gross_amount'], isNull);
      expect(db['referral_status'], isNull);
    });

    test('a referred sale keeps the gross beside what was paid', () {
      final sale = saleFromMap(referredMap);

      expect(sale.amount, 450.0);
      expect(sale.grossAmount, 500.0);
      expect(sale.referralBenefitType, ReferralBenefitType.fixedAmount);
      expect(sale.referralBenefitValue, 50.0);
      expect(sale.referralBenefitAmount, 50.0);
      expect(sale.affiliateCodeId, 'ac1');
      expect(sale.referralStatus, ReferralSaleStatus.attributed);
      expect(sale.isReferred, isTrue);
    });

    test('the db map writes the stored spellings, and reads them back', () {
      final db = saleFromMap(referredMap).toDbMap();

      expect(db['gross_amount'], 500.0);
      expect(db['referral_benefit_type'], 'FIXED_AMOUNT');
      expect(db['referral_status'], 'ATTRIBUTED');
      expect(saleFromMap({...baseMap, ...db}).referralStatus,
          ReferralSaleStatus.attributed);
    });

    test('a value this version does not know reads as absent, not as a crash',
        () {
      // A server that adds a benefit type later must not stop a till from
      // showing the sale it already made.
      final sale = saleFromMap({
        ...referredMap,
        'referral_benefit_type': 'SOMETHING_NEW',
        'referral_status': 'SOMETHING_NEW',
      });

      expect(sale.referralBenefitType, isNull);
      expect(sale.referralStatus, isNull);
      expect(sale.amount, 450.0);
    });

    test('nothing about a referral is ever sent back up', () {
      // The discount, the code and the gross are decided by the commit
      // transaction; a sale that uploaded them would be asking the server to
      // trust a price the till chose.
      final syncMap = saleFromMap(referredMap).toClientSyncMap();

      for (final field in [
        'gross_amount',
        'referral_benefit_type',
        'referral_benefit_value',
        'referral_benefit_amount',
        'affiliate_code_id',
        'referral_status',
      ]) {
        expect(syncMap, isNot(contains(field)), reason: field);
      }
      expect(syncMap['amount'], 450.0);
    });

    test('legacy JSON with no referral keys still decodes', () {
      final sale = Sale.fromJson({
        'id': 's1',
        'customerId': 'c1',
        'amount': 200.0,
        'points': 2,
        'createdAt': '2026-09-15T10:00:00.000',
      });

      expect(sale.grossAmount, isNull);
      expect(sale.referralStatus, isNull);
      expect(sale.isReferred, isFalse);
    });
  });

  group('points calculation (amount / pointsPerMzn).floor()', () {
    int calcPoints(double amount) =>
        (amount / AppConstants.pointsPerMzn).floor();

    test('100 MZN → 1 pt', () => expect(calcPoints(100), 1));
    test('200 MZN → 2 pts', () => expect(calcPoints(200), 2));
    test('150 MZN → 1 pt (floor)', () => expect(calcPoints(150), 1));
    test('99 MZN → 0 pts', () => expect(calcPoints(99), 0));
    test('0 MZN → 0 pts', () => expect(calcPoints(0), 0));
    test('500 MZN → 5 pts', () => expect(calcPoints(500), 5));
    test('1000 MZN → 10 pts', () => expect(calcPoints(1000), 10));
  });
}
