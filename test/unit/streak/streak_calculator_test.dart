import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/services/streak/streak_calculator.dart';

void main() {
  group('StreakCalculator', () {
    const calc = StreakCalculator();

    test('returns 0 for no sales', () {
      final result = calc.calculate(saleDays: []);
      expect(result.days, 0);
      expect(result.isAtRisk, false);
    });

    test('counts consecutive days with one grace day', () {
      final today = DateTime(2026, 5, 13);
      final days = [
        DateTime(2026, 5, 13),
        DateTime(2026, 5, 12),
        DateTime(2026, 5, 10),
      ];
      final result = calc.calculate(saleDays: days, today: today);
      expect(result.days, 3);
      expect(result.isAtRisk, false);
    });

    test('flags streak at risk when no sale today', () {
      final today = DateTime(2026, 5, 13);
      final days = [
        DateTime(2026, 5, 12),
        DateTime(2026, 5, 11),
      ];
      final result = calc.calculate(saleDays: days, today: today);
      expect(result.days, 2);
      expect(result.isAtRisk, true);
    });
  });
}
