import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/constants/app_constants.dart';
import 'package:loyalty_app/features/sales/domain/sale.dart';

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
      expect(s.synced, false);
      expect(s.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('amount as int is coerced to double', () {
      final s = saleFromMap({...baseMap, 'amount': 300});
      expect(s.amount, 300.0);
      expect(s.amount, isA<double>());
    });

    test('synced=1 → true', () => expect(saleFromMap({...baseMap, 'synced': 1}).synced, true));
    test('null synced → false', () => expect(saleFromMap({...baseMap, 'synced': null}).synced, false));
  });

  group('toDbMap', () {
    test('produces all expected keys', () {
      final keys = saleFromMap(baseMap).toDbMap().keys;
      expect(keys, containsAll(['id', 'customer_id', 'amount', 'points', 'created_at', 'synced']));
    });

    test('synced bool → int', () {
      expect(saleFromMap({...baseMap, 'synced': 0}).toDbMap()['synced'], 0);
      expect(saleFromMap({...baseMap, 'synced': 1}).toDbMap()['synced'], 1);
    });
  });

  group('points calculation (amount / pointsPerMzn).floor()', () {
    int calcPoints(double amount) => (amount / AppConstants.pointsPerMzn).floor();

    test('100 MZN → 1 pt', () => expect(calcPoints(100), 1));
    test('200 MZN → 2 pts', () => expect(calcPoints(200), 2));
    test('150 MZN → 1 pt (floor)', () => expect(calcPoints(150), 1));
    test('99 MZN → 0 pts', () => expect(calcPoints(99), 0));
    test('0 MZN → 0 pts', () => expect(calcPoints(0), 0));
    test('500 MZN → 5 pts', () => expect(calcPoints(500), 5));
    test('1000 MZN → 10 pts', () => expect(calcPoints(1000), 10));
  });
}
