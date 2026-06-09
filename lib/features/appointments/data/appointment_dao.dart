import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/appointment.dart';

class AppointmentDao {
  AppointmentDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<Appointment> create({
    required String customerId,
    required DateTime scheduledDate,
    required String source,
    String? appUserId,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final appointment = Appointment(
      id: _uuid.v4(),
      customerId: customerId,
      scheduledDate: scheduledDate,
      status: AppointmentStatus.scheduled,
      source: source,
      reminderSent: false,
      createdAt: now,
      updatedAt: now,
      synced: false,
    );

    await db.insert('appointments', {
      ...appointment.toJson(),
      'merchant_id': merchantId,
      'created_by_app_user_id': appUserId,
      'updated_by_app_user_id': appUserId,
    });

    return appointment;
  }

  Future<Appointment?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'appointments',
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return appointmentFromMap(rows.first);
  }

  Future<void> update(
    String id, {
    DateTime? scheduledDate,
    String? status,
    bool? reminderSent,
    String? appUserId,
  }) async {
    final db = await _db.database;
    final payload = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    };
    if (scheduledDate != null) {
      payload['scheduled_date'] = scheduledDate.millisecondsSinceEpoch;
    }
    if (status != null && status.isNotEmpty) {
      payload['status'] = status;
    }
    if (reminderSent != null) {
      payload['reminder_sent'] = reminderSent ? 1 : 0;
    }
    if (appUserId != null && appUserId.trim().isNotEmpty) {
      payload['updated_by_app_user_id'] = appUserId.trim();
    }

    await db.update(
      'appointments',
      payload,
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<void> cancel(String id) {
    return update(id, status: AppointmentStatus.cancelled);
  }

  Future<void> markAsMissed(String id) {
    return update(id, status: AppointmentStatus.missed);
  }

  Future<List<Appointment>> getUpcoming({
    DateTime? from,
    int limit = 50,
  }) async {
    final db = await _db.database;
    final threshold = (from ?? DateTime.now()).millisecondsSinceEpoch;
    final rows = await db.query(
      'appointments',
      where: _withMerchantScope('status = ? AND scheduled_date >= ?'),
      whereArgs: _withMerchantArgs([
        AppointmentStatus.scheduled,
        threshold,
      ]),
      orderBy: 'scheduled_date ASC',
      limit: limit,
    );
    return rows.map(appointmentFromMap).toList();
  }

  String _withMerchantScope(String clause) {
    if (merchantId == null) {
      return clause;
    }
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _withMerchantArgs(List<Object?> args) {
    if (merchantId == null) {
      return args;
    }
    return [merchantId, ...args];
  }
}
