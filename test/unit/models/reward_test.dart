import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/rewards/domain/reward.dart';

void main() {
  final baseMap = <String, dynamic>{
    'id': 'r1',
    'name': 'Corte Grátis',
    'points_required': 10,
    'description': 'Corte de cabelo grátis',
    'active': 1,
    'created_at': 1700000000000,
    'synced': 0,
  };

  group('rewardFromMap', () {
    test('parses all fields', () {
      final r = rewardFromMap(baseMap);
      expect(r.id, 'r1');
      expect(r.name, 'Corte Grátis');
      expect(r.pointsRequired, 10);
      expect(r.description, 'Corte de cabelo grátis');
      expect(r.active, true);
      expect(r.synced, false);
      expect(r.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('active=1 → true', () => expect(rewardFromMap({...baseMap, 'active': 1}).active, true));
    test('active=0 → false', () => expect(rewardFromMap({...baseMap, 'active': 0}).active, false));
    test('null active defaults to true', () => expect(rewardFromMap({...baseMap, 'active': null}).active, true));
    test('null description → null', () => expect(rewardFromMap({...baseMap, 'description': null}).description, isNull));
    test('synced=1 → true', () => expect(rewardFromMap({...baseMap, 'synced': 1}).synced, true));
    test('null synced → false', () => expect(rewardFromMap({...baseMap, 'synced': null}).synced, false));
  });

  group('toDbMap', () {
    test('active true → 1', () => expect(rewardFromMap({...baseMap, 'active': 1}).toDbMap()['active'], 1));
    test('active false → 0', () => expect(rewardFromMap({...baseMap, 'active': 0}).toDbMap()['active'], 0));

    test('null description preserved in map', () {
      final r = rewardFromMap({...baseMap, 'description': null});
      expect(r.toDbMap()['description'], isNull);
    });

    test('produces all expected keys', () {
      final keys = rewardFromMap(baseMap).toDbMap().keys;
      expect(keys, containsAll(['id', 'name', 'points_required', 'description', 'active', 'created_at', 'synced']));
    });

    test('name and pointsRequired roundtrip', () {
      final r = rewardFromMap(baseMap);
      expect(r.toDbMap()['name'], 'Corte Grátis');
      expect(r.toDbMap()['points_required'], 10);
    });
  });
}

