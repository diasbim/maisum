import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/admin_portal/domain/admin_operations_summary.dart';

void main() {
  group('AdminOperationsSummary.fromJson', () {
    test('parses aggregate operations fields', () {
      final summary = AdminOperationsSummary.fromJson({
        'merchant_count': '12',
        'active_subscription_count': 8,
        'trial_subscription_count': 3.0,
        'attention_subscription_count': null,
        'active_staff_count': '21',
        'usage_events_24h': 42,
        'open_recovery_task_count': '5',
        'visit_reports_24h': 7,
        'survey_responses_24h': 9,
        'admin_audit_events_24h': 4,
        'last_admin_audit_at': '2026-07-03T12:00:00.000Z',
        'last_usage_event_at': 1710000000000,
      });

      expect(summary.merchantCount, 12);
      expect(summary.activeSubscriptionCount, 8);
      expect(summary.trialSubscriptionCount, 3);
      expect(summary.attentionSubscriptionCount, 0);
      expect(summary.activeStaffCount, 21);
      expect(summary.usageEvents24h, 42);
      expect(summary.openRecoveryTaskCount, 5);
      expect(summary.visitReports24h, 7);
      expect(summary.surveyResponses24h, 9);
      expect(summary.adminAuditEvents24h, 4);
      expect(
        summary.lastAdminAuditAt,
        DateTime.parse('2026-07-03T12:00:00.000Z'),
      );
      expect(summary.lastUsageEventAt?.millisecondsSinceEpoch, 1710000000000);
    });

    test('uses zero defaults for missing aggregate fields', () {
      final summary = AdminOperationsSummary.fromJson({});

      expect(summary.merchantCount, 0);
      expect(summary.activeSubscriptionCount, 0);
      expect(summary.usageEvents24h, 0);
      expect(summary.lastAdminAuditAt, isNull);
    });
  });
}
