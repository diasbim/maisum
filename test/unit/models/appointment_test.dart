import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/appointments/domain/appointment.dart';

void main() {
  test('reads legacy appointments without general detail fields', () {
    final appointment = Appointment.fromJson({
      'id': 'a1',
      'customer_id': 'c1',
      'scheduled_date': 1000,
      'status': AppointmentStatus.scheduled,
      'source': 'legacy',
      'reminder_sent': 0,
      'created_at': 1000,
      'updated_at': 1000,
    });

    expect(appointment.merchantItemId, isNull);
    expect(appointment.staffAppUserId, isNull);
    expect(appointment.durationMinutes, isNull);
    expect(appointment.notes, isNull);
  });

  test('round-trips service, staff, duration, and notes', () {
    final appointment = Appointment(
      id: 'a1',
      customerId: 'c1',
      scheduledDate: DateTime.fromMillisecondsSinceEpoch(1000),
      status: AppointmentStatus.scheduled,
      source: 'app',
      reminderSent: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      merchantItemId: 'service-1',
      staffAppUserId: 'staff-1',
      durationMinutes: 45,
      notes: 'Bring previous receipt',
    );

    final decoded = Appointment.fromJson(appointment.toJson());

    expect(decoded, appointment);
  });
}
