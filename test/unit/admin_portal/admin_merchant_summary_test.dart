import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/admin_portal/domain/admin_merchant_summary.dart';

void main() {
  group('AdminMerchantSummary.fromJson', () {
    test('parses merchant directory fields from backend rows', () {
      final summary = AdminMerchantSummary.fromJson({
        'id': ' merchant-1 ',
        'name': ' Barbearia Norte ',
        'phone': '+258840000001',
        'created_at': 1710000000000,
        'updated_at': '1710000005000',
        'plan_code': 'pro',
        'plan_name': 'Pro',
        'subscription_status': 'ACTIVE',
        'staff_count': '4',
        'active_staff_count': 3.2,
        'usage_balance_count': null,
        'last_operational_update_at': '2026-07-03T12:00:00.000Z',
      });

      expect(summary.id, 'merchant-1');
      expect(summary.name, 'Barbearia Norte');
      expect(summary.phone, '+258840000001');
      expect(summary.createdAt.millisecondsSinceEpoch, 1710000000000);
      expect(summary.updatedAt.millisecondsSinceEpoch, 1710000005000);
      expect(summary.planCode, 'pro');
      expect(summary.planName, 'Pro');
      expect(summary.subscriptionStatus, 'ACTIVE');
      expect(summary.staffCount, 4);
      expect(summary.activeStaffCount, 3);
      expect(summary.usageBalanceCount, 0);
      expect(
        summary.lastOperationalUpdateAt,
        DateTime.parse('2026-07-03T12:00:00.000Z'),
      );
    });

    test('uses safe defaults for absent optional backend fields', () {
      final summary = AdminMerchantSummary.fromJson({});

      expect(summary.id, isEmpty);
      expect(summary.name, 'Merchant');
      expect(summary.phone, isEmpty);
      expect(summary.planCode, isNull);
      expect(summary.staffCount, 0);
      expect(summary.activeStaffCount, 0);
      expect(summary.usageBalanceCount, 0);
      expect(summary.lastOperationalUpdateAt, isNull);
    });
  });

  group('AdminMerchantDetail.fromJson', () {
    test('parses subscription, usage, and configuration detail fields', () {
      final detail = AdminMerchantDetail.fromJson({
        'id': 'merchant-2',
        'name': 'Padaria Sul',
        'phone': '+258840000002',
        'created_at': 1710000000000,
        'updated_at': 1710001000000,
        'plan_code': 'starter',
        'plan_name': 'Starter',
        'subscription_status': 'TRIAL',
        'staff_count': 2,
        'active_staff_count': 1,
        'usage_balance_count': 3,
        'plan_version': '4',
        'pricing_version': 2.0,
        'trial_ends_at': 1711000000000,
        'grace_ends_at': null,
        'period_start': '1710000000000',
        'period_end': '2026-07-03T00:00:00.000Z',
        'subscription_updated_at': 1710002000000,
        'last_staff_login_at': 1710003000000,
        'usage_updated_at': 1710004000000,
        'last_usage_event_at': 1710005000000,
        'entitlement_count': '6',
        'feature_flag_count': 2,
        'remote_config_count': 1,
        'usage_event_count': 8,
        'usage_used_total': '34',
      });

      expect(detail.summary.id, 'merchant-2');
      expect(detail.planVersion, 4);
      expect(detail.pricingVersion, 2);
      expect(detail.trialEndsAt?.millisecondsSinceEpoch, 1711000000000);
      expect(detail.graceEndsAt, isNull);
      expect(detail.periodStart?.millisecondsSinceEpoch, 1710000000000);
      expect(detail.periodEnd, DateTime.parse('2026-07-03T00:00:00.000Z'));
      expect(
          detail.subscriptionUpdatedAt?.millisecondsSinceEpoch, 1710002000000);
      expect(detail.lastStaffLoginAt?.millisecondsSinceEpoch, 1710003000000);
      expect(detail.usageUpdatedAt?.millisecondsSinceEpoch, 1710004000000);
      expect(detail.lastUsageEventAt?.millisecondsSinceEpoch, 1710005000000);
      expect(detail.entitlementCount, 6);
      expect(detail.featureFlagCount, 2);
      expect(detail.remoteConfigCount, 1);
      expect(detail.usageEventCount, 8);
      expect(detail.usageUsedTotal, 34);
    });
  });
}
