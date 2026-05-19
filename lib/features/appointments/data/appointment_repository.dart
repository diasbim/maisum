import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/appointment.dart';
import 'appointment_dao.dart';

class AppointmentRepository {
  AppointmentRepository(this._dao, this._syncDao);

  final AppointmentDao _dao;
  final SyncDao _syncDao;
  static const _uuid = Uuid();

  Future<Appointment> createAppointment({
    required String customerId,
    required DateTime scheduledDate,
    String source = 'post_sale_flow',
  }) async {
    final appointment = await _dao.create(
      customerId: customerId,
      scheduledDate: scheduledDate,
      source: source,
    );

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'appointment',
        entityId: appointment.id,
        payload: jsonEncode(_payload(appointment)),
        createdAt: DateTime.now(),
      ),
    );

    return appointment;
  }

  Future<Appointment?> updateAppointment(
    String id, {
    DateTime? scheduledDate,
    String? status,
    bool? reminderSent,
  }) async {
    await _dao.update(
      id,
      scheduledDate: scheduledDate,
      status: status,
      reminderSent: reminderSent,
    );

    final updated = await _dao.getById(id);
    if (updated == null) {
      return null;
    }

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'appointment',
        entityId: id,
        payload: jsonEncode(_payload(updated)),
        createdAt: DateTime.now(),
      ),
    );

    return updated;
  }

  Future<Appointment?> cancelAppointment(String id) {
    return updateAppointment(id, status: AppointmentStatus.cancelled);
  }

  Future<List<Appointment>> getUpcomingAppointments({
    DateTime? from,
    int limit = 50,
  }) {
    return _dao.getUpcoming(from: from, limit: limit);
  }

  Future<Appointment?> markAppointmentAsMissed(String id) {
    return updateAppointment(id, status: AppointmentStatus.missed);
  }

  Map<String, dynamic> _payload(Appointment appointment) => {
        ...appointment.toJson(),
        'merchant_id': _dao.merchantId,
      };
}
