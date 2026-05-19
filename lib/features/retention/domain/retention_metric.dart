class RetentionRiskLevel {
  static const String active = 'active';
  static const String attention = 'attention';
  static const String risk = 'risk';
  static const String lost = 'lost';

  static const Set<String> values = {
    active,
    attention,
    risk,
    lost,
  };
}

class RetentionMetric {
  const RetentionMetric({
    required this.id,
    required this.customerId,
    required this.lastVisitAt,
    required this.daysInactive,
    required this.riskLevel,
    required this.totalVisits,
    required this.averageVisitInterval,
    required this.totalSpent,
    required this.isRecurring,
    required this.recovered,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final DateTime? lastVisitAt;
  final int daysInactive;
  final String riskLevel;
  final int totalVisits;
  final int averageVisitInterval;
  final double totalSpent;
  final bool isRecurring;
  final bool recovered;
  final DateTime updatedAt;
  final bool synced;

  RetentionMetric copyWith({
    String? id,
    String? customerId,
    DateTime? lastVisitAt,
    bool setLastVisitAtNull = false,
    int? daysInactive,
    String? riskLevel,
    int? totalVisits,
    int? averageVisitInterval,
    double? totalSpent,
    bool? isRecurring,
    bool? recovered,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return RetentionMetric(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      lastVisitAt:
          setLastVisitAtNull ? null : (lastVisitAt ?? this.lastVisitAt),
      daysInactive: daysInactive ?? this.daysInactive,
      riskLevel: riskLevel ?? this.riskLevel,
      totalVisits: totalVisits ?? this.totalVisits,
      averageVisitInterval: averageVisitInterval ?? this.averageVisitInterval,
      totalSpent: totalSpent ?? this.totalSpent,
      isRecurring: isRecurring ?? this.isRecurring,
      recovered: recovered ?? this.recovered,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'last_visit_at': lastVisitAt?.millisecondsSinceEpoch,
        'days_inactive': daysInactive,
        'risk_level': riskLevel,
        'total_visits': totalVisits,
        'average_visit_interval': averageVisitInterval,
        'total_spent': totalSpent,
        'is_recurring': isRecurring ? 1 : 0,
        'recovered': recovered ? 1 : 0,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  factory RetentionMetric.fromJson(Map<String, dynamic> json) {
    return RetentionMetric(
      id: _readString(json, ['id']),
      customerId: _readString(json, ['customer_id', 'customerId']),
      lastVisitAt:
          _readNullableDateTime(json, ['last_visit_at', 'lastVisitAt']),
      daysInactive: _readInt(json, ['days_inactive', 'daysInactive']),
      riskLevel: _readString(json, ['risk_level', 'riskLevel']),
      totalVisits: _readInt(json, ['total_visits', 'totalVisits']),
      averageVisitInterval:
          _readInt(json, ['average_visit_interval', 'averageVisitInterval']),
      totalSpent: _readDouble(json, ['total_spent', 'totalSpent']),
      isRecurring: _readBool(json, ['is_recurring', 'isRecurring']),
      recovered: _readBool(json, ['recovered']),
      updatedAt: _readDateTime(json, ['updated_at', 'updatedAt']),
      synced: _readBool(json, ['synced']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RetentionMetric &&
        other.id == id &&
        other.customerId == customerId &&
        other.lastVisitAt == lastVisitAt &&
        other.daysInactive == daysInactive &&
        other.riskLevel == riskLevel &&
        other.totalVisits == totalVisits &&
        other.averageVisitInterval == averageVisitInterval &&
        other.totalSpent == totalSpent &&
        other.isRecurring == isRecurring &&
        other.recovered == recovered &&
        other.updatedAt == updatedAt &&
        other.synced == synced;
  }

  @override
  int get hashCode => Object.hash(
        id,
        customerId,
        lastVisitAt,
        daysInactive,
        riskLevel,
        totalVisits,
        averageVisitInterval,
        totalSpent,
        isRecurring,
        recovered,
        updatedAt,
        synced,
      );
}

class RecurringCustomerSummary {
  const RecurringCustomerSummary({
    required this.customerId,
    required this.name,
    required this.totalVisits,
    required this.lastVisitAt,
    required this.averageVisitInterval,
    required this.totalSpent,
  });

  final String customerId;
  final String name;
  final int totalVisits;
  final DateTime? lastVisitAt;
  final int averageVisitInterval;
  final double totalSpent;

  String get badge {
    if (totalSpent >= 5000) return 'VIP';
    if (totalVisits >= 10) return 'Campeao';
    return 'Frequente';
  }
}

class InactiveCustomerSummary {
  const InactiveCustomerSummary({
    required this.customerId,
    required this.name,
    required this.daysInactive,
    required this.lastVisitAt,
    required this.averageTicket,
    required this.riskLevel,
  });

  final String customerId;
  final String name;
  final int daysInactive;
  final DateTime? lastVisitAt;
  final double averageTicket;
  final String riskLevel;
}

String _readString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  throw ArgumentError('Missing required string: ${keys.join('/')}');
}

int _readInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

double _readDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

DateTime _readDateTime(Map<String, dynamic> json, List<String> keys) {
  final value = _readNullableDateTime(json, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required date: ${keys.join('/')}');
}

DateTime? _readNullableDateTime(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String && value.isNotEmpty) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is DateTime) return value;
  }
  return null;
}

bool _readBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is num) return value.toInt() == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
  }
  return false;
}
