import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/offline_referral.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';

/// What a till is allowed to decide on its own.
///
/// Every expectation here is a parity check against
/// `functions/src/affiliate_engine.ts`. The offline path exists so a sale can
/// be completed during an outage, not so the phone can start pricing referrals
/// its own way: a discount that differs from the server's by one centavo is a
/// correction nobody can make to a customer who has already paid and left.
AffiliateCodeLookupCache _cache({
  ReferralBenefitType benefitType = ReferralBenefitType.fixedAmount,
  double benefitValue = 50,
  AffiliateCodeStatus status = AffiliateCodeStatus.active,
  DateTime? startsAt,
  DateTime? expiresAt,
  int? usageLimit,
  int usageCount = 0,
  bool firstVisitOnly = true,
  String affiliateStatus = 'ACTIVE',
  String linkStatus = 'ACTIVE',
}) {
  return AffiliateCodeLookupCache(
    normalizedCode: 'AFI-ANA-7K2P',
    codeId: 'code-1',
    merchantId: 'shop-1',
    affiliateId: 'aff-1',
    code: 'AFI-ANA-7K2P',
    status: status,
    benefitType: benefitType,
    benefitValue: benefitValue,
    startsAt: startsAt,
    expiresAt: expiresAt,
    usageLimit: usageLimit,
    usageCount: usageCount,
    firstVisitOnly: firstVisitOnly,
    cachedAt: DateTime(2025, 3, 1),
    updatedAt: DateTime(2025, 3, 1),
    affiliateDisplayName: 'Ana Silva',
    affiliateFirstName: 'Ana',
    affiliateStatus: affiliateStatus,
    linkStatus: linkStatus,
  );
}

void main() {
  group('deterministic identifiers', () {
    test('the sale id is the one the server will derive', () {
      // Pinned against the value `affiliateIds.sale` produces for the same
      // pair. If these ever diverge the offline sale and the canonical one
      // become two rows for one purchase.
      expect(
        referralSaleDocumentId(deviceId: 'till-1', localSaleId: 'local-sale-1'),
        'sale_1c5133e4333c65f0f11be495330238ce46f2d8ca',
      );
    });

    test('the keys use the spellings the plan fixes', () {
      expect(
        referralSaleIdempotencyKey(
          deviceId: 'till-1',
          localSaleId: 'local-sale-1',
        ),
        'sale:till-1:local-sale-1',
      );
      expect(
        referralAttributionIdempotencyKey(
          merchantId: 'shop-1',
          customerPhoneHash: 'abc123',
        ),
        'affiliate-attribution:shop-1:abc123',
      );
      expect(
        referralRewardIdempotencyKey(
          attributionId: 'aa_1',
          rewardType: 'FIRST_QUALIFYING_SALE',
        ),
        'affiliate-reward:aa_1:FIRST_QUALIFYING_SALE',
      );
    });

    test('a phone is hashed the same way both sides hash it', () {
      expect(
        referralPhoneHash('+258841234567'),
        'c4ccb3f280d713ca041749756ae940232662bf539b08c30f4143d0bf7e41c9cc',
      );
      // No phone is not the hash of nothing: two records with no number must
      // not come out equal.
      expect(referralPhoneHash(null), '');
      expect(referralPhoneHash('  '), '');
    });

    test('a key never contains the number it identifies', () {
      final key = referralAttributionIdempotencyKey(
        merchantId: 'shop-1',
        customerPhoneHash: referralPhoneHash('+258841234567'),
      );
      expect(key.contains('841234567'), isFalse);
      expect(key.contains('258'), isFalse);
    });
  });

  group('provisional codes', () {
    test('are outside the namespace the server owns', () {
      final code = buildProvisionalAffiliateCode(
        firstName: 'Ana',
        localId: 'local-1',
      );
      expect(code, startsWith('LOCAL-ANA-'));
      expect(code, isNot(startsWith('AFI-')));
      expect(isProvisionalAffiliateCode(code), isTrue);
      expect(isProvisionalAffiliateCode('AFI-ANA-7K2P'), isFalse);
    });

    test('two created in the same second do not collide', () {
      expect(
        buildProvisionalAffiliateCode(firstName: 'Ana', localId: 'a'),
        isNot(buildProvisionalAffiliateCode(firstName: 'Ana', localId: 'b')),
      );
    });

    test('a name that folds away still produces a usable code', () {
      final code = buildProvisionalAffiliateCode(
        firstName: '...',
        localId: 'local-1',
      );
      expect(code, startsWith('LOCAL-AFILIADO-'));
    });
  });

  group('benefit arithmetic', () {
    test('a fixed amount comes off the bill and nothing else', () {
      final benefit = calculateOfflineReferralBenefit(
        benefitType: ReferralBenefitType.fixedAmount,
        benefitValue: 50,
        grossAmount: 300,
      );
      expect(benefit.discountAmount, 50);
      expect(benefit.netAmount, 250);
      expect(benefit.pointsAwarded, 0);
      expect(benefit.storedBenefitAmount, 50);
    });

    test('a discount is never larger than the sale', () {
      final benefit = calculateOfflineReferralBenefit(
        benefitType: ReferralBenefitType.fixedAmount,
        benefitValue: 500,
        grossAmount: 300,
      );
      // Money owed to the customer is not a thing this product does.
      expect(benefit.discountAmount, 300);
      expect(benefit.netAmount, 0);
    });

    test('a percentage is floored in centavos', () {
      // 10% of 333.33 is 33.333, which must round down to 33.33 — a cent more
      // than the percentage allows is a cent the business did not agree to.
      final benefit = calculateOfflineReferralBenefit(
        benefitType: ReferralBenefitType.percentage,
        benefitValue: 10,
        grossAmount: 333.33,
      );
      expect(benefit.discountAmount, 33.33);
      expect(benefit.netAmount, 300.0);
    });

    test('a percentage on an odd amount never drifts above the rate', () {
      final benefit = calculateOfflineReferralBenefit(
        benefitType: ReferralBenefitType.percentage,
        benefitValue: 15,
        grossAmount: 99.99,
      );
      expect(benefit.discountAmount, 14.99);
      expect(benefit.netAmount, 85.0);
    });

    test('points change no money at all', () {
      final benefit = calculateOfflineReferralBenefit(
        benefitType: ReferralBenefitType.points,
        benefitValue: 120,
        grossAmount: 300,
      );
      expect(benefit.pointsAwarded, 120);
      expect(benefit.discountAmount, 0);
      expect(benefit.netAmount, 300);
      expect(benefit.storedBenefitAmount, 120);
    });
  });

  group('local validation', () {
    final now = DateTime(2025, 6, 1, 12);

    ReferralValidationErrorCode? check(
      AffiliateCodeLookupCache cache, {
      bool customerIsNew = true,
      double? saleAmount = 300,
      String? customerPhoneHash,
      String? affiliatePhoneHash,
    }) {
      return validateCachedReferralCode(
        cache: cache,
        merchantId: 'shop-1',
        now: now,
        customerIsNew: customerIsNew,
        saleAmount: saleAmount,
        affiliateStatus: cache.affiliateStatus,
        linkStatus: cache.linkStatus,
        customerPhoneHash: customerPhoneHash,
        affiliatePhoneHash: affiliatePhoneHash,
      );
    }

    test('a usable code passes', () {
      expect(check(_cache()), isNull);
    });

    test('a code of another business is simply not found', () {
      // Never "belongs to someone else": that would be a way to probe.
      expect(
        validateCachedReferralCode(
          cache: _cache(),
          merchantId: 'other-shop',
          now: now,
          customerIsNew: true,
          saleAmount: 300,
        ),
        ReferralValidationErrorCode.codeNotFound,
      );
    });

    test('a disabled code is refused before anything else', () {
      expect(
        check(
          _cache(
            status: AffiliateCodeStatus.disabled,
            expiresAt: DateTime(2020),
          ),
        ),
        // Expired as well, and still "desativado": that is the one the merchant
        // can act on.
        ReferralValidationErrorCode.codeDisabled,
      );
    });

    test('validity is a half-open window', () {
      expect(
        check(_cache(startsAt: now.add(const Duration(minutes: 1)))),
        ReferralValidationErrorCode.codeNotStarted,
      );
      expect(check(_cache(startsAt: now)), isNull);
      expect(
        check(_cache(expiresAt: now)),
        ReferralValidationErrorCode.codeExpired,
      );
      expect(
        check(_cache(expiresAt: now.add(const Duration(minutes: 1)))),
        isNull,
      );
    });

    test('the cached usage count is enough to refuse an exhausted code', () {
      expect(
        check(_cache(usageLimit: 3, usageCount: 3)),
        ReferralValidationErrorCode.codeUsageLimitReached,
      );
      expect(check(_cache(usageLimit: 3, usageCount: 2)), isNull);
      expect(check(_cache(usageLimit: null, usageCount: 999)), isNull);
    });

    test('a suspended affiliate or a dropped link stops the code', () {
      expect(
        check(_cache(affiliateStatus: 'SUSPENDED')),
        ReferralValidationErrorCode.affiliateInactive,
      );
      expect(
        check(_cache(linkStatus: 'INACTIVE')),
        ReferralValidationErrorCode.affiliateInactive,
      );
    });

    test('an affiliate cannot use their own code', () {
      final hash = referralPhoneHash('+258841234567');
      expect(
        check(
          _cache(),
          customerPhoneHash: hash,
          affiliatePhoneHash: hash,
        ),
        ReferralValidationErrorCode.selfReferralNotAllowed,
      );
    });

    test('first-visit-only is checked against what this device knows', () {
      expect(
        check(_cache(), customerIsNew: false),
        ReferralValidationErrorCode.customerNotEligible,
      );
      expect(
        check(_cache(firstVisitOnly: false), customerIsNew: false),
        isNull,
      );
    });

    test('a benefit larger than the sale is invalid, not capped', () {
      expect(
        check(_cache(benefitValue: 400), saleAmount: 300),
        ReferralValidationErrorCode.benefitInvalid,
      );
      expect(
        check(
          _cache(
            benefitType: ReferralBenefitType.percentage,
            benefitValue: 80,
          ),
        ),
        ReferralValidationErrorCode.benefitInvalid,
      );
      expect(
        check(
          _cache(benefitType: ReferralBenefitType.points, benefitValue: 1.5),
        ),
        ReferralValidationErrorCode.benefitInvalid,
      );
    });
  });

  test('PENDING_SYNC is its own status, not a spelling of PENDING', () {
    // PENDING is the server saying "valid code, nobody acquired". PENDING_SYNC
    // is this device saying "the server has not been asked". Collapsing them
    // would let a screen claim an affiliate was credited.
    expect(ReferralSaleStatus.pendingSync.storageValue, 'PENDING_SYNC');
    expect(
      ReferralSaleStatus.fromStorage('PENDING_SYNC'),
      ReferralSaleStatus.pendingSync,
    );
    expect(
      ReferralSaleStatus.fromStorage('PENDING'),
      ReferralSaleStatus.pending,
    );
  });
}
