import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';

void main() {
  group('AuthSession tenant resolution', () {
    test('resolvedMerchantId falls back to firebase uid', () {
      final session = AuthSession(
        userId: 'user-1',
        phone: '+258840000000',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        firebaseUid: 'firebase-merchant',
      );

      expect(session.resolvedMerchantId, 'firebase-merchant');
    });

    test('resolvedAppUserId falls back to user id', () {
      final session = AuthSession(
        userId: 'user-1',
        phone: '+258840000000',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );

      expect(session.resolvedAppUserId, 'user-1');
    });
  });
}

