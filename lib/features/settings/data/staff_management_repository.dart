import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/staff_member.dart';

class StaffManagementRepository {
  StaffManagementRepository(
    this._database,
    this._syncDao, {
    required this.merchantId,
    required this.currentAppUserId,
  });

  final AppDatabase _database;
  final SyncDao _syncDao;
  final String? merchantId;
  final String? currentAppUserId;

  static const _uuid = Uuid();

  Future<List<StaffMember>> listMembers() async {
    final scopedMerchantId = _requireMerchantId();
    final db = await _database.database;
    final rows = await db.query(
      'app_users',
      where: 'merchant_id = ?',
      whereArgs: [scopedMerchantId],
      orderBy:
          "CASE WHEN role = 'OWNER' THEN 0 ELSE 1 END, CASE WHEN status = 'ACTIVE' THEN 0 WHEN status = 'INVITED' THEN 1 ELSE 2 END, updated_at DESC",
    );
    return rows.map(StaffMember.fromMap).toList();
  }

  Future<StaffMember> inviteStaff({
    required String phone,
    String role = AppConstants.appUserRoleStaff,
  }) {
    return _upsertStaffByPhone(
      phone: phone,
      role: role,
      status: AppConstants.appUserStatusInvited,
      acceptedAt: null,
      invitedAt: DateTime.now(),
    );
  }

  Future<StaffMember> createManualStaff({
    required String phone,
    String role = AppConstants.appUserRoleStaff,
  }) {
    final now = DateTime.now();
    return _upsertStaffByPhone(
      phone: phone,
      role: role,
      status: AppConstants.appUserStatusActive,
      acceptedAt: now,
      invitedAt: null,
    );
  }

  Future<StaffMember> setStaffActive({
    required String staffId,
    required bool isActive,
  }) async {
    final scopedMerchantId = _requireMerchantId();
    final db = await _database.database;

    final existingRows = await db.query(
      'app_users',
      where: 'id = ? AND merchant_id = ?',
      whereArgs: [staffId, scopedMerchantId],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      throw StateError('Staff não encontrado.');
    }

    final existing = StaffMember.fromMap(existingRows.first);
    if (existing.isOwner) {
      throw StateError('Não é permitido desativar conta OWNER.');
    }

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final nextStatus = isActive
        ? AppConstants.appUserStatusActive
        : AppConstants.appUserStatusInactive;

    await db.update(
      'app_users',
      {
        'status': nextStatus,
        'updated_at': nowMs,
        'accepted_at': isActive
            ? (existing.acceptedAt?.millisecondsSinceEpoch ?? nowMs)
            : existing.acceptedAt?.millisecondsSinceEpoch,
        'deactivated_at': isActive ? null : nowMs,
      },
      where: 'id = ? AND merchant_id = ?',
      whereArgs: [staffId, scopedMerchantId],
    );

    final updatedRow = await _getMemberRowById(db, staffId, scopedMerchantId);
    await _enqueueStaffSync(
      operation: 'update',
      entityId: staffId,
      payload: updatedRow,
    );

    return StaffMember.fromMap(updatedRow);
  }

  Future<StaffMember> _upsertStaffByPhone({
    required String phone,
    required String role,
    required String status,
    required DateTime? acceptedAt,
    required DateTime? invitedAt,
  }) async {
    final scopedMerchantId = _requireMerchantId();
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) {
      throw ArgumentError.value(phone, 'phone');
    }

    final db = await _database.database;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final normalizedRole = _normalizeRole(role);
    final normalizedStatus = _normalizeStatus(status);

    final existingRows = await db.query(
      'app_users',
      where: 'merchant_id = ? AND phone = ?',
      whereArgs: [scopedMerchantId, normalizedPhone],
      limit: 1,
    );

    late final String entityId;
    late final String operation;

    if (existingRows.isEmpty) {
      entityId = _uuid.v4();
      operation = 'create';
      await db.insert('app_users', {
        'id': entityId,
        'merchant_id': scopedMerchantId,
        'phone': normalizedPhone,
        'role': normalizedRole,
        'status': normalizedStatus,
        'invited_at': invitedAt?.millisecondsSinceEpoch,
        'accepted_at': acceptedAt?.millisecondsSinceEpoch,
        'invited_by_app_user_id': currentAppUserId,
        'deactivated_at': normalizedStatus == AppConstants.appUserStatusInactive
            ? nowMs
            : null,
        'created_at': nowMs,
        'updated_at': nowMs,
        'last_login_at': null,
      });
    } else {
      final existing = StaffMember.fromMap(existingRows.first);
      if (existing.isOwner) {
        throw StateError('Conta OWNER não pode ser alterada por este fluxo.');
      }

      entityId = existing.id;
      operation = 'update';
      await db.update(
        'app_users',
        {
          'phone': normalizedPhone,
          'role': normalizedRole,
          'status': normalizedStatus,
          'invited_at': invitedAt?.millisecondsSinceEpoch,
          'accepted_at': acceptedAt?.millisecondsSinceEpoch,
          'invited_by_app_user_id': currentAppUserId,
          'deactivated_at':
              normalizedStatus == AppConstants.appUserStatusInactive
                  ? nowMs
                  : null,
          'updated_at': nowMs,
        },
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [entityId, scopedMerchantId],
      );
    }

    final row = await _getMemberRowById(db, entityId, scopedMerchantId);
    await _enqueueStaffSync(
      operation: operation,
      entityId: entityId,
      payload: row,
    );

    return StaffMember.fromMap(row);
  }

  Future<Map<String, dynamic>> _getMemberRowById(
    dynamic db,
    String id,
    String scopedMerchantId,
  ) async {
    final rows = await db.query(
      'app_users',
      where: 'id = ? AND merchant_id = ?',
      whereArgs: [id, scopedMerchantId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Staff não encontrado.');
    }
    return rows.first;
  }

  Future<void> _enqueueStaffSync({
    required String operation,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: operation,
        entityType: 'app_user',
        entityId: entityId,
        payload: jsonEncode(payload),
        createdAt: DateTime.now(),
      ),
    );
  }

  String _requireMerchantId() {
    final scopedMerchantId = merchantId?.trim();
    if (scopedMerchantId == null || scopedMerchantId.isEmpty) {
      throw StateError('Sessão inválida para gestão de staff.');
    }
    return scopedMerchantId;
  }

  String _normalizeRole(String role) {
    final normalized = role.trim().toUpperCase();
    if (normalized == AppConstants.appUserRoleOwner) {
      return AppConstants.appUserRoleOwner;
    }
    return AppConstants.appUserRoleStaff;
  }

  String _normalizeStatus(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized == AppConstants.appUserStatusInvited) {
      return AppConstants.appUserStatusInvited;
    }
    if (normalized == AppConstants.appUserStatusInactive) {
      return AppConstants.appUserStatusInactive;
    }
    return AppConstants.appUserStatusActive;
  }
}
