import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';

void main() {
  group('AuthSession.isValid', () {
    test('returns true when expiresAt is in the future', () {
      final session = AuthSession(
        userId: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(session.isValid, true);
    });

    test('returns false when expiresAt is in the past', () {
      final session = AuthSession(
        userId: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(session.isValid, false);
    });

    test('returns false when expiresAt is just expired', () {
      final session = AuthSession(
        userId: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().subtract(const Duration(milliseconds: 1)),
      );
      expect(session.isValid, false);
    });

    test('30-day session is valid', () {
      final session = AuthSession(
        userId: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(session.isValid, true);
    });
  });

  group('AuthSession.isFirebaseSession', () {
    test('returns true when firebaseUid is set', () {
      final session = AuthSession(
        userId: 'uid-abc',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        firebaseUid: 'uid-abc',
      );
      expect(session.isFirebaseSession, true);
    });

    test('returns false when firebaseUid is null', () {
      final session = AuthSession(
        userId: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(session.isFirebaseSession, false);
    });

    test('returns false when firebaseUid is empty string', () {
      final session = AuthSession(
        userId: 'u1',
        phone: '840000001',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        firebaseUid: '',
      );
      expect(session.isFirebaseSession, false);
    });
  });

  group('equality', () {
    final expiry = DateTime(2027, 1, 1);

    test('same data → equal sessions', () {
      final s1 = AuthSession(userId: 'u1', phone: '840000001', expiresAt: expiry);
      final s2 = AuthSession(userId: 'u1', phone: '840000001', expiresAt: expiry);
      expect(s1, equals(s2));
    });

    test('different firebaseUid → different session', () {
      final s1 = AuthSession(userId: 'u1', phone: '840000001', expiresAt: expiry, firebaseUid: 'uid1');
      final s2 = AuthSession(userId: 'u1', phone: '840000001', expiresAt: expiry, firebaseUid: 'uid2');
      expect(s1, isNot(equals(s2)));
    });

    test('token defaults to empty string', () {
      final s = AuthSession(userId: 'u1', phone: '840000001', expiresAt: expiry);
      expect(s.token, '');
    });
  });

  group('fromJson / toJson roundtrip', () {
    test('preserves all fields including firebaseUid', () {
      final original = AuthSession(
        userId: 'u1',
        phone: '+258840000001',
        expiresAt: DateTime(2027, 6, 15, 10, 30),
        token: 'firebase-id-token',
        firebaseUid: 'uid-firebase-123',
      );
      final restored = AuthSession.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('roundtrip without firebaseUid', () {
      final original = AuthSession(
        userId: 'u1',
        phone: '+258840000001',
        expiresAt: DateTime(2027, 6, 15, 10, 30),
      );
      final restored = AuthSession.fromJson(original.toJson());
      expect(restored, equals(original));
      expect(restored.firebaseUid, isNull);
    });
  });
}

