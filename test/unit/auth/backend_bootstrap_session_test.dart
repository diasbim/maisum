import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/auth/domain/backend_bootstrap_session.dart';

void main() {
  group('BackendBootstrapSession', () {
    test('maps snake_case payload into AuthSession', () {
      final bootstrapSession = BackendBootstrapSession.fromJson({
        'user_id': 'user-1',
        'app_user_id': 'app-user-1',
        'merchant_id': 'merchant-1',
        'merchant_name': 'Loja Central',
        'phone': '+258840000000',
        'subscription_status': 'ACTIVE_PAID',
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
        'expires_at': '2026-05-06T10:00:00Z',
      });

      final authSession = bootstrapSession.toAuthSession(
        fallbackFirebaseUid: 'firebase-1',
        fallbackDeviceId: 'device-1',
      );

      expect(authSession.userId, 'user-1');
      expect(authSession.resolvedAppUserId, 'app-user-1');
      expect(authSession.resolvedMerchantId, 'merchant-1');
      expect(authSession.merchantName, 'Loja Central');
      expect(authSession.subscriptionStatus, 'ACTIVE_PAID');
      expect(authSession.token, 'access-token');
      expect(authSession.refreshToken, 'refresh-token');
      expect(authSession.firebaseUid, 'firebase-1');
      expect(authSession.deviceId, 'device-1');
    });
  });
}

