class AppointmentStatus {
  static const String scheduled = 'scheduled';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';
  static const String missed = 'missed';

  static const Set<String> values = {
    scheduled,
    completed,
    cancelled,
    missed,
  };
}

class Appointment {
  const Appointment({
    required this.id,
    required this.customerId,
    required this.scheduledDate,
    required this.status,
    required this.source,
    required this.reminderSent,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final DateTime scheduledDate;
  final String status;
  final String source;
  final bool reminderSent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  Appointment copyWith({
    String? id,
    String? customerId,
    DateTime? scheduledDate,
    String? status,
    String? source,
    bool? reminderSent,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return Appointment(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      status: status ?? this.status,
      source: source ?? this.source,
      reminderSent: reminderSent ?? this.reminderSent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'scheduled_date': scheduledDate.millisecondsSinceEpoch,
        'status': status,
        'source': source,
        'reminder_sent': reminderSent ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: _readString(json, ['id']),
      customerId: _readString(json, ['customer_id', 'customerId']),
      scheduledDate: _readDateTime(
        json,
        ['scheduled_date', 'scheduledDate'],
      ),
      status: _readString(json, ['status']),
      source: _readString(json, ['source']),
      reminderSent: _readBool(json, ['reminder_sent', 'reminderSent']),
      createdAt: _readDateTime(json, ['created_at', 'createdAt']),
      updatedAt: _readDateTime(json, ['updated_at', 'updatedAt']),
      synced: _readBool(json, ['synced']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Appointment &&
        other.id == id &&
        other.customerId == customerId &&
        other.scheduledDate == scheduledDate &&
        other.status == status &&
        other.source == source &&
        other.reminderSent == reminderSent &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.synced == synced;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      customerId,
      scheduledDate,
      status,
      source,
      reminderSent,
      createdAt,
      updatedAt,
      synced,
    );
  }
}

Appointment appointmentFromMap(Map<String, dynamic> map) =>
    Appointment.fromJson(map);

String _readString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  throw ArgumentError('Missing required string: ${keys.join('/')}');
}

DateTime _readDateTime(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String && value.isNotEmpty) {
      final asInt = int.tryParse(value);
      if (asInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    if (value is DateTime) {
      return value;
    }
  }
  throw ArgumentError('Missing required date: ${keys.join('/')}');
}

bool _readBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value == 1;
    }
    if (value is num) {
      return value.toInt() == 1;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true') {
        return true;
      }
      if (normalized == '0' || normalized == 'false') {
        return false;
      }
    }
  }
  return false;
}
