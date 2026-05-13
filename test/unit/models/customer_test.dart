import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/customers/domain/customer.dart';

void main() {
  final baseMap = <String, dynamic>{
    'id': 'c1',
    'name': 'João Silva',
    'phone': '840000001',
    'total_points': 50,
    'created_at': 1700000000000,
    'updated_at': 1700000001000,
    'synced': 0,
  };

  group('customerFromMap', () {
    test('parses all fields correctly', () {
      final c = customerFromMap(baseMap);
      expect(c.id, 'c1');
      expect(c.name, 'João Silva');
      expect(c.phone, '840000001');
      expect(c.totalPoints, 50);
      expect(c.synced, false);
      expect(c.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(c.updatedAt, DateTime.fromMillisecondsSinceEpoch(1700000001000));
    });

    test('defaults totalPoints to 0 when null', () {
      final c = customerFromMap({...baseMap, 'total_points': null});
      expect(c.totalPoints, 0);
    });

    test('synced=0 → false', () => expect(customerFromMap({...baseMap, 'synced': 0}).synced, false));
    test('synced=1 → true', () => expect(customerFromMap({...baseMap, 'synced': 1}).synced, true));
    test('null synced → false', () => expect(customerFromMap({...baseMap, 'synced': null}).synced, false));

    test('null updated_at → null updatedAt', () {
      final c = customerFromMap({...baseMap, 'updated_at': null});
      expect(c.updatedAt, isNull);
    });
  });

  group('toDbMap', () {
    test('produces all expected keys', () {
      final keys = customerFromMap(baseMap).toDbMap().keys;
      expect(keys, containsAll(['id', 'name', 'phone', 'total_points', 'created_at', 'updated_at', 'synced']));
    });

    test('synced false → 0', () {
      expect(customerFromMap({...baseMap, 'synced': 0}).toDbMap()['synced'], 0);
    });

    test('synced true → 1', () {
      expect(customerFromMap({...baseMap, 'synced': 1}).toDbMap()['synced'], 1);
    });

    test('values roundtrip correctly', () {
      final c = customerFromMap(baseMap);
      final m = c.toDbMap();
      expect(m['id'], 'c1');
      expect(m['name'], 'João Silva');
      expect(m['phone'], '840000001');
      expect(m['total_points'], 50);
    });
  });

  group('equality', () {
    test('same data → equal', () {
      expect(customerFromMap(baseMap), equals(customerFromMap(baseMap)));
    });

    test('different phone → not equal', () {
      final c1 = customerFromMap(baseMap);
      final c2 = customerFromMap({...baseMap, 'phone': '840000002'});
      expect(c1, isNot(equals(c2)));
    });
  });
}

