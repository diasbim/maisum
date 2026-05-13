import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/utils/points_calculator.dart';

void main() {
  group('PointsCalculator', () {
    const calculator = PointsCalculator();

    test('calculates points for standard amounts', () {
      expect(calculator.calculate(100), 1);
      expect(calculator.calculate(250), 2);
      expect(calculator.calculate(999), 9);
    });

    test('returns 0 for zero or negative values', () {
      expect(calculator.calculate(0), 0);
      expect(calculator.calculate(-10), 0);
    });
  });
}
