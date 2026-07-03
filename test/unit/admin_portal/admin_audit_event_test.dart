import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/admin_portal/domain/admin_audit_event.dart';

void main() {
  group('AdminAuditEvent.fromJson', () {
    test('parses admin audit event rows from the backend', () {
      final event = AdminAuditEvent.fromJson({
        'id': ' event-1 ',
        'action': ' plan.upsert ',
        'target_type': ' plan ',
        'target_id': 'starter@4',
        'merchant_id': 'merchant-1',
        'actor_app_user_id': 'admin-user-1',
        'actor_firebase_uid': 'firebase-1',
        'actor_role': 'ADMIN',
        'details': {'plan_code': 'starter', 'version': 4},
        'created_at': '1710000000000',
      });

      expect(event.id, 'event-1');
      expect(event.action, 'plan.upsert');
      expect(event.targetType, 'plan');
      expect(event.targetId, 'starter@4');
      expect(event.merchantId, 'merchant-1');
      expect(event.actorAppUserId, 'admin-user-1');
      expect(event.actorFirebaseUid, 'firebase-1');
      expect(event.actorRole, 'ADMIN');
      expect(event.details, {'plan_code': 'starter', 'version': 4});
      expect(event.createdAt.millisecondsSinceEpoch, 1710000000000);
    });

    test('uses safe defaults for sparse rows', () {
      final event = AdminAuditEvent.fromJson({});

      expect(event.id, isEmpty);
      expect(event.action, 'admin.event');
      expect(event.targetType, 'unknown');
      expect(event.targetId, isNull);
      expect(event.details, isEmpty);
    });
  });
}
