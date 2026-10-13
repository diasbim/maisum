import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_attribution.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/affiliate_event.dart';
import 'package:maisum/features/affiliates/domain/affiliate_reward.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1720000000000);

  group('affiliate domain serialization', () {
    test('round trips canonical affiliate and attribution values', () {
      final affiliate = Affiliate.fromMap(
        Affiliate(
          id: 'affiliate-1',
          phone: '+258841111111',
          normalizedPhone: '258841111111',
          firstName: 'Ana',
          lastName: 'Silva',
          displayName: 'Ana Silva',
          status: AffiliateStatus.suspended,
          createdAt: now,
          updatedAt: now,
          synced: true,
        ).toMap(),
      );
      expect(affiliate.status, AffiliateStatus.suspended);

      final link = AffiliateMerchantLink.fromMap(
        AffiliateMerchantLink(
          id: 'link-1',
          merchantId: 'merchant-1',
          affiliateId: 'affiliate-1',
          status: AffiliateMerchantStatus.inactive,
          linkedAt: now,
          createdAt: now,
          updatedAt: now,
          synced: true,
        ).toMap(),
      );
      expect(link.status, AffiliateMerchantStatus.inactive);

      final code = AffiliateCode.fromMap(
        AffiliateCode(
          id: 'code-1',
          merchantId: 'merchant-1',
          affiliateId: 'affiliate-1',
          code: 'AFI-ANA-2345',
          normalizedCode: 'AFI-ANA-2345',
          benefitType: ReferralBenefitType.fixedAmount,
          benefitValue: 50,
          startsAt: now,
          expiresAt: now.add(const Duration(days: 30)),
          usageLimit: 10,
          usageCount: 1,
          firstVisitOnly: true,
          status: AffiliateCodeStatus.active,
          createdAt: now,
          updatedAt: now,
          synced: true,
        ).toMap(),
      );
      expect(code.benefitType, ReferralBenefitType.fixedAmount);

      final attribution = AffiliateAttribution.fromMap(
        AffiliateAttribution(
          id: 'attr-1',
          merchantId: 'merchant-1',
          affiliateId: 'affiliate-1',
          affiliateCodeId: 'code-1',
          customerId: 'customer-1',
          qualifyingSaleId: 'sale-1',
          status: AffiliateAttributionStatus.confirmed,
          attributedAt: now,
          firstSaleAt: now,
          createdAt: now,
          updatedAt: now,
          synced: true,
        ).toMap(),
      );
      expect(attribution.status, AffiliateAttributionStatus.confirmed);
      expect(attribution.rejectionCode, isNull);
    });

    test('round trips canonical reward, event, fraud signal and reason code',
        () {
      final reward = AffiliateReward.fromMap(
        AffiliateReward(
          id: 'reward-1',
          merchantId: 'merchant-1',
          affiliateId: 'affiliate-1',
          attributionId: 'attr-1',
          rewardType: AffiliateRewardType.customerReturn,
          valueType: AffiliateRewardValueType.fixedAmount,
          rewardValue: 75,
          status: AffiliateRewardStatus.paid,
          approvalRequired: false,
          sourceSaleId: 'sale-2',
          approvedAt: now,
          approvedByAppUserId: 'owner-1',
          cancelledAt: null,
          cancelledByAppUserId: null,
          cancellationReason: null,
          paidAt: now,
          paidByAppUserId: 'owner-1',
          createdAt: now,
          updatedAt: now,
          synced: true,
        ).toMap(),
      );
      expect(reward.rewardType, AffiliateRewardType.customerReturn);
      expect(reward.valueType, AffiliateRewardValueType.fixedAmount);
      expect(reward.status, AffiliateRewardStatus.paid);

      final event = AffiliateEvent.fromMap(
        AffiliateEvent(
          id: 'event-1',
          merchantId: 'merchant-1',
          affiliateId: 'affiliate-1',
          eventType: AffiliateEventType.referredCustomerReturned,
          attributionId: 'attr-1',
          rewardId: 'reward-1',
          saleId: 'sale-2',
          customerId: 'customer-1',
          payload: const {'status': 'APPROVED'},
          occurredAt: now,
          createdAt: now,
          schemaVersion: 1,
        ).toJson(),
      );
      expect(event.eventType, AffiliateEventType.referredCustomerReturned);

      final signal = AffiliateFraudSignal.fromMap(
        AffiliateFraudSignal(
          id: 'signal-1',
          merchantId: 'merchant-1',
          affiliateId: 'affiliate-1',
          signalType: AffiliateFraudSignalType.offlineCodeRejected,
          severity: AffiliateFraudSignalSeverity.medium,
          attributionId: 'attr-1',
          rewardId: 'reward-1',
          saleId: 'sale-2',
          customerId: 'customer-1',
          metadata: const {'reason': 'offline'},
          createdAt: now,
        ).toJson(),
      );
      expect(signal.signalType, AffiliateFraudSignalType.offlineCodeRejected);
      expect(signal.severity, AffiliateFraudSignalSeverity.medium);

      final validation = ReferralValidationResult.fromMap(
        ReferralValidationResult(
          isValid: false,
          validatedAt: now,
          normalizedCode: 'AFI-ANA-2345',
          affiliateCodeId: 'code-1',
          affiliateId: 'affiliate-1',
          saleStatus: ReferralSaleStatus.rejected,
          benefit: const ReferralBenefitPreview(
            benefitType: ReferralBenefitType.points,
            benefitValue: 50,
          ),
          errorCode: ReferralValidationErrorCode.customerAlreadyReferred,
          statusText: 'Código recusado.',
        ).toJson(),
      );
      expect(
        validation.errorCode,
        ReferralValidationErrorCode.customerAlreadyReferred,
      );
      expect(validation.saleStatus, ReferralSaleStatus.rejected);
    });

    test('throws FormatException for unknown or missing persisted enums', () {
      expect(
        () => Affiliate.fromMap({
          'id': 'affiliate-1',
          'phone': '+258841111111',
          'normalized_phone': '258841111111',
          'first_name': 'Ana',
          'display_name': 'Ana Silva',
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateMerchantLink.fromMap({
          'id': 'link-1',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'status': 'SUSPENDED',
          'linked_at': now.millisecondsSinceEpoch,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateCode.fromMap({
          'id': 'code-1',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'code': 'AFI-ANA-2345',
          'normalized_code': 'AFI-ANA-2345',
          'benefit_type': 'BONUS',
          'benefit_value': 50,
          'status': 'ACTIVE',
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateCodeLookupCache.fromMap({
          'normalized_code': 'AFI-ANA-2345',
          'code_id': 'code-1',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'code': 'AFI-ANA-2345',
          'status': 'INACTIVE',
          'benefit_type': 'POINTS',
          'benefit_value': 50,
          'cached_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateAttribution.fromMap({
          'id': 'attr-1',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'affiliate_code_id': 'code-1',
          'customer_id': 'customer-1',
          'status': 'ACTIVE',
          'attributed_at': now.millisecondsSinceEpoch,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateAttribution.fromMap({
          'id': 'attr-2',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'affiliate_code_id': 'code-1',
          'customer_id': 'customer-2',
          'status': 'REJECTED',
          'rejection_code': 'SOMETHING_ELSE',
          'attributed_at': now.millisecondsSinceEpoch,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateReward.fromMap({
          'id': 'reward-1',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'attribution_id': 'attr-1',
          'reward_type': 'FIRST_SALE',
          'value_type': 'AMOUNT',
          'reward_value': 50,
          'status': 'REJECTED',
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateEvent.fromMap({
          'id': 'event-1',
          'merchant_id': 'merchant-1',
          'affiliate_id': 'affiliate-1',
          'event_type': 'ATTRIBUTION_CREATED',
          'occurred_at': now.millisecondsSinceEpoch,
          'created_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AffiliateFraudSignal.fromMap({
          'id': 'signal-1',
          'merchant_id': 'merchant-1',
          'signal_type': 'SYNC_REJECTED',
          'severity': 'SEVERE',
          'created_at': now.millisecondsSinceEpoch,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ReferralValidationResult.fromMap({
          'is_valid': false,
          'validated_at': now.millisecondsSinceEpoch,
          'sale_status': 'DONE',
          'error_code': 'BAD_CODE',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
