import '../../../core/constants/app_constants.dart';

class StaffMember {
  const StaffMember({
    required this.id,
    required this.merchantId,
    required this.phone,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.invitedAt,
    this.acceptedAt,
    this.invitedByAppUserId,
    this.deactivatedAt,
    this.lastLoginAt,
  });

  final String id;
  final String merchantId;
  final String phone;
  final String role;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? invitedAt;
  final DateTime? acceptedAt;
  final String? invitedByAppUserId;
  final DateTime? deactivatedAt;
  final DateTime? lastLoginAt;

  bool get isOwner => role == AppConstants.appUserRoleOwner;
  bool get isStaff => role == AppConstants.appUserRoleStaff;
  bool get isActive => status == AppConstants.appUserStatusActive;

  factory StaffMember.fromMap(Map<String, dynamic> map) {
    return StaffMember(
      id: (map['id'] as String?) ?? '',
      merchantId: (map['merchant_id'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      role: _normalizeRole(
          (map['role'] as String?) ?? AppConstants.appUserRoleStaff),
      status: _normalizeStatus(
          (map['status'] as String?) ?? AppConstants.appUserStatusActive),
      createdAt:
          _toDate((map['created_at'] as num?)?.toInt()) ?? DateTime.now(),
      updatedAt:
          _toDate((map['updated_at'] as num?)?.toInt()) ?? DateTime.now(),
      invitedAt: _toDate((map['invited_at'] as num?)?.toInt()),
      acceptedAt: _toDate((map['accepted_at'] as num?)?.toInt()),
      invitedByAppUserId: map['invited_by_app_user_id'] as String?,
      deactivatedAt: _toDate((map['deactivated_at'] as num?)?.toInt()),
      lastLoginAt: _toDate((map['last_login_at'] as num?)?.toInt()),
    );
  }

  static String _normalizeRole(String role) {
    final normalized = role.trim().toUpperCase();
    if (normalized == AppConstants.appUserRoleOwner) {
      return AppConstants.appUserRoleOwner;
    }
    return AppConstants.appUserRoleStaff;
  }

  static String _normalizeStatus(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized == AppConstants.appUserStatusInvited) {
      return AppConstants.appUserStatusInvited;
    }
    if (normalized == AppConstants.appUserStatusInactive) {
      return AppConstants.appUserStatusInactive;
    }
    return AppConstants.appUserStatusActive;
  }

  static DateTime? _toDate(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
