import 'dart:convert';

const Object _missingEnumValue = Object();

String readRequiredString(Map<String, dynamic> map, List<String> keys) {
  final value = readNullableString(map, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required string: ${keys.join('/')}');
}

String? readNullableString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

int readRequiredInt(Map<String, dynamic> map, List<String> keys) {
  final value = readNullableInt(map, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required int: ${keys.join('/')}');
}

int? readNullableInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double readRequiredDouble(Map<String, dynamic> map, List<String> keys) {
  final value = readNullableDouble(map, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required double: ${keys.join('/')}');
}

double? readNullableDouble(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool readBool(
  Map<String, dynamic> map,
  List<String> keys, {
  bool defaultValue = false,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is num) return value.toInt() == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
  }
  return defaultValue;
}

DateTime readRequiredDateTime(Map<String, dynamic> map, List<String> keys) {
  final value = readNullableDateTime(map, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required date: ${keys.join('/')}');
}

DateTime? readNullableDateTime(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String && value.trim().isNotEmpty) {
      final normalized = value.trim();
      final epoch = int.tryParse(normalized);
      if (epoch != null) {
        return DateTime.fromMillisecondsSinceEpoch(epoch);
      }
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

Map<String, dynamic>? readNullableMap(
    Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map(
            (entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue),
          );
        }
      } catch (_) {}
    }
  }
  return null;
}

String? encodeNullableMap(Map<String, dynamic>? value) {
  if (value == null) return null;
  return jsonEncode(value);
}

T readRequiredEnum<T>(
  Map<String, dynamic> map,
  List<String> keys,
  T Function(Object value) parse,
) {
  final raw = _readEnumRawValue(map, keys);
  if (identical(raw, _missingEnumValue) || raw == null) {
    throw FormatException('Missing required enum: ${keys.join('/')}');
  }
  return parse(raw);
}

T? readNullableEnum<T>(
  Map<String, dynamic> map,
  List<String> keys,
  T Function(Object value) parse,
) {
  final raw = _readEnumRawValue(map, keys);
  if (identical(raw, _missingEnumValue) || raw == null) {
    return null;
  }
  return parse(raw);
}

Object? _readEnumRawValue(Map<String, dynamic> map, List<String> keys) {
  var sawNull = false;
  for (final key in keys) {
    if (map.containsKey(key)) {
      final value = map[key];
      if (value != null) return value;
      sawNull = true;
    }
  }
  return sawNull ? null : _missingEnumValue;
}
