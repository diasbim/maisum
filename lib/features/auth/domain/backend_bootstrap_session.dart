import 'auth_session.dart';

class BackendBootstrapSession {
  const BackendBootstrapSession({
    required this.userId,
    required this.appUserId,
    required this.merchantId,
    required this.merchantName,
    required this.phone,
    required this.accessToken,
    required this.expiresAt,
    this.subscriptionStatus = 'TRIAL',
    this.refreshToken,
    this.deviceId,
    this.firebaseUid,
  });

  final String userId;
  final String appUserId;
  final String merchantId;
  final String merchantName;
  final String phone;
  final String accessToken;
  final DateTime expiresAt;
  final String subscriptionStatus;
  final String? refreshToken;
  final String? deviceId;
  final String? firebaseUid;

  factory BackendBootstrapSession.fromJson(Map<String, dynamic> json) {
    return BackendBootstrapSession(
      userId: json['userId'] as String? ?? json['user_id'] as String? ?? '',
      appUserId:
          json['appUserId'] as String? ?? json['app_user_id'] as String? ?? '',
      merchantId:
          json['merchantId'] as String? ?? json['merchant_id'] as String? ?? '',
      merchantName:
          json['merchantName'] as String? ??
          json['merchant_name'] as String? ??
          'Minha Loja',
      phone: json['phone'] as String? ?? '',
      accessToken:
          json['accessToken'] as String? ??
          json['access_token'] as String? ??
          '',
      expiresAt: DateTime.parse(
        json['expiresAt'] as String? ?? json['expires_at'] as String,
      ),
      subscriptionStatus:
          json['subscriptionStatus'] as String? ??
          json['subscription_status'] as String? ??
          'TRIAL',
      refreshToken:
          json['refreshToken'] as String? ?? json['refresh_token'] as String?,
      deviceId: json['deviceId'] as String? ?? json['device_id'] as String?,
      firebaseUid:
          json['firebaseUid'] as String? ?? json['firebase_uid'] as String?,
    );
  }

  AuthSession toAuthSession({
    String? fallbackFirebaseUid,
    String? fallbackDeviceId,
  }) {
    return AuthSession(
      userId: userId,
      appUserId: appUserId,
      merchantId: merchantId,
      merchantName: merchantName,
      subscriptionStatus: subscriptionStatus,
      refreshToken: refreshToken,
      deviceId: deviceId ?? fallbackDeviceId,
      firebaseUid: firebaseUid ?? fallbackFirebaseUid,
      phone: phone,
      token: accessToken,
      expiresAt: expiresAt,
    );
  }
}
