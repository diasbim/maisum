class StreakSummary {
  const StreakSummary({
    required this.days,
    required this.isAtRisk,
    required this.lastActiveDay,
  });

  final int days;
  final bool isAtRisk;
  final DateTime? lastActiveDay;
}

class StreakCalculator {
  StreakSummary calculate({
    required List<DateTime> saleDays,
    DateTime? today,
    int maxLookbackDays = 45,
  }) {
    if (saleDays.isEmpty) {
      return const StreakSummary(days: 0, isAtRisk: false, lastActiveDay: null);
    }

    final daySet = saleDays.map(_dayKey).toSet();
    final baseDay = _normalizeDay(today ?? DateTime.now());
    final hasSaleToday = daySet.contains(_dayKey(baseDay));

    var streak = 0;
    var misses = 0;
    DateTime? lastActiveDay;

    for (var i = 0; i < maxLookbackDays; i++) {
      final day = baseDay.subtract(Duration(days: i));
      if (daySet.contains(_dayKey(day))) {
        streak += 1;
        lastActiveDay ??= day;
        misses = 0;
      } else {
        misses += 1;
        if (misses >= 2) {
          break;
        }
      }
    }

    return StreakSummary(
      days: streak,
      isAtRisk: streak > 0 && !hasSaleToday,
      lastActiveDay: lastActiveDay,
    );
  }

  int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

  DateTime _normalizeDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
