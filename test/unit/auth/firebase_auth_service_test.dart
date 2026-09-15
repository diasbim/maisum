import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/services/firebase_auth_service.dart';
import 'package:maisum/core/utils/app_logger.dart';

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
      final events = <AppLogEvent>[];
      Log.bindSink(events.add);
      addTearDown(() => Log.bindSink(null));
      expect(svc.isSignedIn, false);

      final result = await svc.verifyOtp(
        verificationId: 'fake-verification-id',
        smsCode: '123456',
      );
      expect(result.user?.uid, 'uid-789');
      expect(svc.isSignedIn, true);
      expect(
        events.map((event) => event.message),
        containsAll([
          'phone_auth:otp_verification_started',
          'phone_auth:otp_verification_succeeded',
        ]),
      );
      expect(
        events.map((event) => event.message).join(' '),
        isNot(contains('fake-verification-id')),
      );
      expect(
        events.map((event) => event.message).join(' '),
        isNot(contains('123456')),
      );
      expect(
        events.map((event) => event.message).join(' '),
        isNot(contains('+258840000001')),
      );
    });

    group('waitForCurrentUser', () {
      test('returns immediately when currentUser is already available',
          () async {
        final user = MockUser(uid: 'uid-immediate');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final svc = FirebaseAuthService(auth);

        final result = await svc.waitForCurrentUser(
          timeout: const Duration(seconds: 1),
        );

        expect(result?.uid, 'uid-immediate');
      });

      test(
        'waits for the SDK to finish restoring the persisted user instead '
        'of concluding "logged out" the instant currentUser is still null',
        () async {
          // Mirrors the real cold-start race: the native SDK has a signed-in
          // user, but the Dart-side currentUser getter hasn't caught up yet
          // when session restore first asks — it arrives a beat later via
          // authStateChanges().
          final auth = MockFirebaseAuth();
          final svc = FirebaseAuthService(auth);
          expect(svc.currentUser, isNull);

          final user = MockUser(uid: 'uid-delayed');
          Future<void>.delayed(const Duration(milliseconds: 30), () {
            auth.mockUser = user;
            auth.signInWithCredential(null);
          });

          final result = await svc.waitForCurrentUser(
            timeout: const Duration(seconds: 2),
          );

          expect(
            result?.uid,
            'uid-delayed',
            reason: 'a session restore that only checked currentUser once '
                'would have wrongly treated this as "not signed in"',
          );
        },
      );

      test('gives up and returns null once the timeout elapses', () async {
        final auth = MockFirebaseAuth();
        final svc = FirebaseAuthService(auth);

        final result = await svc.waitForCurrentUser(
          timeout: const Duration(milliseconds: 50),
        );

        expect(result, isNull);
      });
    });
  });
}
