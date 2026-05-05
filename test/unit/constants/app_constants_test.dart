import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/constants/app_constants.dart';

void main() {
  group('AppConstants values', () {
    test('pointsPerMzn is 100', () => expect(AppConstants.pointsPerMzn, 100));
    test('maxSyncRetries is 3', () => expect(AppConstants.maxSyncRetries, 3));
    test('dbVersion is 5', () => expect(AppConstants.dbVersion, 5));
    test('connectTimeout is 10 s',
        () => expect(AppConstants.connectTimeout, const Duration(seconds: 10)));
    test('receiveTimeout is 15 s',
        () => expect(AppConstants.receiveTimeout, const Duration(seconds: 15)));
  });

  group('Points calculation formula (amount / pointsPerMzn).floor()', () {
    int pts(double amount) => (amount / AppConstants.pointsPerMzn).floor();

    test('100 MZN → 1 pt', () => expect(pts(100), 1));
    test('200 MZN → 2 pts', () => expect(pts(200), 2));
    test('150 MZN → 1 pt (floor)', () => expect(pts(150), 1));
    test('99 MZN → 0 pts (below threshold)', () => expect(pts(99), 0));
    test('0 MZN → 0 pts', () => expect(pts(0), 0));
    test('500 MZN → 5 pts', () => expect(pts(500), 5));
    test('1000 MZN → 10 pts', () => expect(pts(1000), 10));
    test('1 MZN → 0 pts', () => expect(pts(1), 0));
  });
}
