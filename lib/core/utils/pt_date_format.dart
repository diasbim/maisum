class PtDateFormat {
  static const List<String> _months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  static String dayMonthTime(DateTime value) {
    return '${_twoDigits(value.day)} ${_months[value.month - 1]}, '
        '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }

  static String dayMonthYearTime(DateTime value) {
    return '${_twoDigits(value.day)} ${_months[value.month - 1]} '
        '${value.year}, ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
