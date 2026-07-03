import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/app/router.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';

void main() {
  group('hasInternalAdminClaim', () {
    test('accepts supported admin claim shapes', () {
      expect(hasInternalAdminClaim({'admin': true}), isTrue);
      expect(hasInternalAdminClaim({'is_admin': true}), isTrue);
      expect(hasInternalAdminClaim({'internal_admin': true}), isTrue);
      expect(hasInternalAdminClaim({'role': 'admin'}), isTrue);
      expect(hasInternalAdminClaim({'role': ' INTERNAL_ADMIN '}), isTrue);
    });

    test('rejects non-admin claims', () {
      expect(hasInternalAdminClaim({}), isFalse);
      expect(hasInternalAdminClaim({'admin': false}), isFalse);
      expect(hasInternalAdminClaim({'role': 'OWNER'}), isFalse);
      expect(hasInternalAdminClaim({'role': 'staff'}), isFalse);
    });
  });

  group('resolveAdminPortalRedirect', () {
    test('blocks all admin portal routes outside web', () {
      expect(
        resolveAdminPortalRedirect(
          isWeb: false,
          isSelfServiceRoute: false,
          isInternalAdmin: true,
          isOwner: true,
        ),
        '/dashboard',
      );
    });

    test('allows internal admins into internal portal sections on web', () {
      expect(
        resolveAdminPortalRedirect(
          isWeb: true,
          isSelfServiceRoute: false,
          isInternalAdmin: true,
          isOwner: false,
        ),
        isNull,
      );
    });

    test('sends merchant owners without admin claims to self-service', () {
      expect(
        resolveAdminPortalRedirect(
          isWeb: true,
          isSelfServiceRoute: false,
          isInternalAdmin: false,
          isOwner: true,
        ),
        '/admin/self-service',
      );
    });

    test('allows owners into self-service and blocks staff', () {
      expect(
        resolveAdminPortalRedirect(
          isWeb: true,
          isSelfServiceRoute: true,
          isInternalAdmin: false,
          isOwner: true,
        ),
        isNull,
      );
      expect(
        resolveAdminPortalRedirect(
          isWeb: true,
          isSelfServiceRoute: true,
          isInternalAdmin: false,
          isOwner: false,
        ),
        '/dashboard',
      );
    });

    test('blocks non-admin non-owner users from internal portal sections', () {
      expect(
        resolveAdminPortalRedirect(
          isWeb: true,
          isSelfServiceRoute: false,
          isInternalAdmin: false,
          isOwner: false,
        ),
        '/dashboard',
      );
    });
  });
}