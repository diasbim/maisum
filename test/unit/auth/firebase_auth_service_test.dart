import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/services/firebase_auth_service.dart';

void main() {
  group('FirebaseAuthService', () {
    late MockFirebaseAuth mockAuth;
    late FirebaseAuthService service;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      service = FirebaseAuthService(mockAuth);
    });

    test('currentUser is null when not signed in', () {
      expect(service.currentUser, isNull);
    });

    test('isSignedIn is false when not signed in', () {
      expect(service.isSignedIn, false);
    });

    test('uid is null when not signed in', () {
      expect(service.uid, isNull);
    });

    test('currentUser is not null after sign in', () async {
      final user = MockUser(uid: 'uid-123', phoneNumber: '+258840000000');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final svc = FirebaseAuthService(auth);
      expect(svc.isSignedIn, true);
      expect(svc.uid, 'uid-123');
      expect(svc.currentUser, isNotNull);
    });

    test('signOut clears current user', () async {
      final user = MockUser(uid: 'uid-456');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final svc = FirebaseAuthService(auth);
      expect(svc.isSignedIn, true);
      await svc.signOut();
      expect(svc.isSignedIn, false);
      expect(svc.currentUser, isNull);
    });

    test('verifyOtp signs in with valid credential', () async {
      final user = MockUser(uid: 'uid-789', phoneNumber: '+258840000001');
      final auth = MockFirebaseAuth(mockUser: user);
      final svc = FirebaseAuthService(auth);
      expect(svc.isSignedIn, false);

      final result = await svc.verifyOtp(
        verificationId: 'fake-verification-id',
        smsCode: '123456',
      );
      expect(result.user?.uid, 'uid-789');
      expect(svc.isSignedIn, true);
    });
  });
}
