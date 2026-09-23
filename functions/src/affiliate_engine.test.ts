import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_AFFILIATE_CONFIG,
  PERCENTAGE_RANGE,
  REFERRAL_REASON,
  REFERRAL_REASON_MESSAGE,
  type AffiliateConfig,
} from './affiliate_contracts.js';
import {
  affiliateIds,
  buildAffiliateCode,
  calculateBenefit,
  CODE_ALPHABET,
  foldCodeName,
  generateCodeSuffix,
  isBenefitValid,
  isNewCustomer,
  isQualifyingSale,
  isWithinReturnWindow,
  normalizeAffiliateCode,
  planFirstSaleReward,
  planReturnReward,
  rewardsAffectedByCancellation,
  saleIdempotencyKey,
  summarizeAffiliateMetrics,
  validateReferral,
  type ReferralCodeSnapshot,
  type ReferralContext,
} from './affiliate_engine.js';

const NOW = 1_788_307_006_310;
const DAY = 24 * 60 * 60 * 1000;

function code(overrides: Partial<ReferralCodeSnapshot> = {}): ReferralCodeSnapshot {
  return {
    codeId: 'ac_1',
    merchantId: 'merchant-1',
    affiliateId: 'affiliate-1',
    status: 'ACTIVE',
    startsAt: NOW - DAY,
    expiresAt: NOW + 29 * DAY,
    usageLimit: null,
    usageCount: 0,
    firstVisitOnly: true,
    benefitType: 'PERCENTAGE',
    benefitValue: 10,
    ...overrides,
  };
}

function context(overrides: Partial<ReferralContext> = {}): ReferralContext {
  return {
    merchantId: 'merchant-1',
    now: NOW,
    affiliateStatus: 'ACTIVE',
    linkStatus: 'ACTIVE',
    affiliatePhoneHash: 'hash-affiliate',
    customerPhoneHash: 'hash-customer',
    customerIsNew: true,
    existingAttributionStatus: null,
    saleAmount: 1000,
    ...overrides,
  };
}

function config(overrides: Partial<AffiliateConfig> = {}): AffiliateConfig {
  return {
    ...DEFAULT_AFFILIATE_CONFIG,
    enabled: true,
    firstSaleRewardPoints: 100,
    ...overrides,
  };
}

/* --------------------------------------------------------------- the codes */

test('a typed code is matched ignoring case and outer spaces', () => {
  assert.equal(normalizeAffiliateCode('  afi-joao-k7m2 '), 'AFI-JOAO-K7M2');
});

test('inner spaces are not forgiven, because a code is one token', () => {
  // Collapsing them would accept something that is not the code.
  assert.equal(normalizeAffiliateCode('AFI JOAO K7M2'), 'AFI JOAO K7M2');
});

test('accents fold to ASCII so the code can be dictated', () => {
  assert.equal(foldCodeName('João'), 'JOAO');
  assert.equal(foldCodeName('Amélia Cossa'), 'AMELIA');
  assert.equal(foldCodeName('Ângela'), 'ANGELA');
});

test('only the first name is used, and it is capped', () => {
  assert.equal(foldCodeName('Guilhermina Nhamirre'), 'GUILHERM');
  assert.equal(foldCodeName('Guilhermina Nhamirre').length, 8);
});

test('punctuation and separators are dropped, not turned into gaps', () => {
  assert.equal(foldCodeName("O'Brien"), 'OBRIEN');
  assert.equal(foldCodeName('Ana-Maria'), 'ANAMARIA');
});

test('a name that folds away still yields a usable code', () => {
  // Otherwise this produces AFI--K7M2, which reads as a bug to the merchant.
  assert.equal(buildAffiliateCode('???', 'K7M2'), 'AFI-AFILIADO-K7M2');
  assert.equal(buildAffiliateCode('   ', 'K7M2'), 'AFI-AFILIADO-K7M2');
});

test('the code has the shape the whole product agrees on', () => {
  assert.equal(buildAffiliateCode('João Macamo', 'K7M2'), 'AFI-JOAO-K7M2');
  assert.match(buildAffiliateCode('João', 'K7M2'), /^AFI-[A-Z0-9]{1,8}-[A-Z0-9]{4}$/);
});

test('the suffix alphabet excludes every character that gets misread', () => {
  for (const confusable of ['0', 'O', '1', 'I', 'L']) {
    assert.ok(
      !CODE_ALPHABET.includes(confusable),
      `${confusable} is in the alphabet and will be misheard`,
    );
  }
});

test('a suffix is drawn only from that alphabet', () => {
  let n = 0;
  const suffix = generateCodeSuffix(() => (n++ * 7) % 256, 64);
  for (const character of suffix) {
    assert.ok(CODE_ALPHABET.includes(character), `${character} is off-alphabet`);
  }
});

test('bytes past the last whole multiple are rejected, not folded', () => {
  // Taking modulo instead would make the first few characters likelier, which
  // is invisible in output and halves the useful key space over time.
  const limit = Math.floor(256 / CODE_ALPHABET.length) * CODE_ALPHABET.length;
  const bytes = [limit, limit + 1, 255, 0];
  let i = 0;
  const suffix = generateCodeSuffix(() => bytes[i++ % bytes.length], 1);
  assert.equal(suffix, CODE_ALPHABET[0]);
});

test('suffix generation gives up rather than spinning forever', () => {
  const limit = Math.floor(256 / CODE_ALPHABET.length) * CODE_ALPHABET.length;
  assert.throws(() => generateCodeSuffix(() => limit, 1), /no progress/);
});

/* ----------------------------------------------------------------- the ids */

test('the same pair always resolves to the same id', () => {
  assert.equal(
    affiliateIds.attribution('merchant-1', 'customer-1'),
    affiliateIds.attribution('merchant-1', 'customer-1'),
  );
});

test('a different pair resolves to a different id', () => {
  assert.notEqual(
    affiliateIds.attribution('merchant-1', 'customer-1'),
    affiliateIds.attribution('merchant-2', 'customer-1'),
  );
  assert.notEqual(
    affiliateIds.reward('aa_1', 'FIRST_QUALIFYING_SALE'),
    affiliateIds.reward('aa_1', 'CUSTOMER_RETURN'),
  );
});

test('the parts cannot be smeared into each other', () => {
  // Joining on a plain separator would make ("ab","c") and ("a","bc") collide,
  // which is one customer's attribution landing on another's document.
  assert.notEqual(
    affiliateIds.attribution('ab', 'c'),
    affiliateIds.attribution('a', 'bc'),
  );
});

test('an id never carries a phone number', () => {
  const id = affiliateIds.attribution('merchant-1', '258840000001');
  assert.ok(!id.includes('840000001'));
  assert.ok(!id.includes('258'));
});

test('the sale key ties a replay to the till it came from', () => {
  assert.equal(saleIdempotencyKey('device-9', 'local-3'), 'sale:device-9:local-3');
});

/* ------------------------------------------------------------- validation */

test('a good code passes', () => {
  assert.deepEqual(validateReferral(code(), context()), { ok: true });
});

test('a missing code and another business are the same answer', () => {
  // Distinguishing them lets a caller enumerate other businesses' codes.
  assert.deepEqual(validateReferral(null, context()), {
    ok: false,
    reason: 'CODE_NOT_FOUND',
  });
  assert.deepEqual(
    validateReferral(code({ merchantId: 'merchant-2' }), context()),
    { ok: false, reason: 'CODE_NOT_FOUND' },
  );
});

test('each check has its own reason', () => {
  const cases: Array<[Partial<ReferralCodeSnapshot>, Partial<ReferralContext>, string]> = [
    [{ status: 'DISABLED' }, {}, 'CODE_DISABLED'],
    [{ startsAt: NOW + DAY }, {}, 'CODE_NOT_STARTED'],
    [{ expiresAt: NOW - 1 }, {}, 'CODE_EXPIRED'],
    [{ usageLimit: 5, usageCount: 5 }, {}, 'CODE_USAGE_LIMIT_REACHED'],
    [{}, { affiliateStatus: 'INACTIVE' }, 'AFFILIATE_INACTIVE'],
    [{}, { linkStatus: 'INACTIVE' }, 'AFFILIATE_INACTIVE'],
    [{}, { customerPhoneHash: 'hash-affiliate' }, 'SELF_REFERRAL_NOT_ALLOWED'],
    [{}, { customerIsNew: false }, 'CUSTOMER_NOT_ELIGIBLE'],
    [{}, { existingAttributionStatus: 'CONFIRMED' }, 'CUSTOMER_ALREADY_REFERRED'],
    [{ benefitValue: 0 }, {}, 'BENEFIT_INVALID'],
  ];

  for (const [codeOverride, contextOverride, reason] of cases) {
    assert.deepEqual(
      validateReferral(code(codeOverride), context(contextOverride)),
      { ok: false, reason },
      `expected ${reason}`,
    );
  }
});

test('the order is the contract, not an implementation detail', () => {
  // A code that is both disabled and expired must say "desativado": that is
  // the one the merchant can do something about. Reordering these silently
  // changes what a cashier is told to do.
  assert.deepEqual(
    validateReferral(code({ status: 'DISABLED', expiresAt: NOW - 1 }), context()),
    { ok: false, reason: 'CODE_DISABLED' },
  );
  assert.deepEqual(
    validateReferral(
      code({ expiresAt: NOW - 1, usageLimit: 1, usageCount: 9 }),
      context(),
    ),
    { ok: false, reason: 'CODE_EXPIRED' },
  );
  assert.deepEqual(
    validateReferral(code(), context({
      affiliateStatus: 'INACTIVE',
      customerPhoneHash: 'hash-affiliate',
    })),
    { ok: false, reason: 'AFFILIATE_INACTIVE' },
  );
});

test('a code expires at its instant, not after it', () => {
  assert.deepEqual(validateReferral(code({ expiresAt: NOW }), context()), {
    ok: false,
    reason: 'CODE_EXPIRED',
  });
  assert.deepEqual(validateReferral(code({ expiresAt: NOW + 1 }), context()), {
    ok: true,
  });
});

test('validity starts at its instant', () => {
  assert.deepEqual(validateReferral(code({ startsAt: NOW }), context()), { ok: true });
});

test('an unlimited code is not a code with a zero limit', () => {
  assert.deepEqual(
    validateReferral(code({ usageLimit: null, usageCount: 9999 }), context()),
    { ok: true },
  );
  assert.deepEqual(
    validateReferral(code({ usageLimit: 0, usageCount: 0 }), context()),
    { ok: false, reason: 'CODE_USAGE_LIMIT_REACHED' },
  );
});

test('a rejected attribution leaves the customer available', () => {
  // It is a record that somebody tried, not a claim on the customer.
  assert.deepEqual(
    validateReferral(code(), context({ existingAttributionStatus: 'REJECTED' })),
    { ok: true },
  );
  for (const status of ['CONFIRMED', 'CANCELLED'] as const) {
    assert.deepEqual(
      validateReferral(code(), context({ existingAttributionStatus: status })),
      { ok: false, reason: 'CUSTOMER_ALREADY_REFERRED' },
    );
  }
});

test('an existing customer passes when the code allows it', () => {
  // firstVisitOnly = false gives the benefit but earns no acquisition; that
  // second half is the transaction's job, not this function's.
  assert.deepEqual(
    validateReferral(
      code({ firstVisitOnly: false }),
      context({ customerIsNew: false }),
    ),
    { ok: true },
  );
});

test('an unknown phone on both sides is not a self-referral', () => {
  // Two empty hashes are two unknowns, not the same person.
  assert.deepEqual(
    validateReferral(
      code(),
      context({ affiliatePhoneHash: '', customerPhoneHash: '' }),
    ),
    { ok: true },
  );
});

test('every reason a merchant can hit has Portuguese words', () => {
  for (const reason of REFERRAL_REASON) {
    const message = REFERRAL_REASON_MESSAGE[reason];
    assert.ok(message && message.length > 0, `${reason} has no message`);
    assert.notEqual(message, reason, `${reason} reaches the till untranslated`);
  }
});

/* --------------------------------------------------------- the preview gap */

test('a preview with no sale yet still checks the code itself', () => {
  assert.deepEqual(
    validateReferral(code({ benefitType: 'FIXED_AMOUNT', benefitValue: 50 }),
      context({ saleAmount: null })),
    { ok: true },
  );
  assert.deepEqual(
    validateReferral(code({ benefitType: 'PERCENTAGE', benefitValue: 80 }),
      context({ saleAmount: null })),
    { ok: false, reason: 'BENEFIT_INVALID' },
  );
});

test('a fixed discount larger than the bill fails at commit, not at preview', () => {
  const big = code({ benefitType: 'FIXED_AMOUNT', benefitValue: 500 });
  assert.deepEqual(validateReferral(big, context({ saleAmount: null })), { ok: true });
  assert.deepEqual(validateReferral(big, context({ saleAmount: 100 })), {
    ok: false,
    reason: 'BENEFIT_INVALID',
  });
});

test('the percentage range is the configured one', () => {
  for (const value of [PERCENTAGE_RANGE.min, 25, PERCENTAGE_RANGE.max]) {
    assert.ok(isBenefitValid({ benefitType: 'PERCENTAGE', benefitValue: value }, 100));
  }
  for (const value of [0, PERCENTAGE_RANGE.min - 1, PERCENTAGE_RANGE.max + 1, 100]) {
    assert.ok(!isBenefitValid({ benefitType: 'PERCENTAGE', benefitValue: value }, 100));
  }
});

test('a points benefit must be a whole number of points', () => {
  assert.ok(isBenefitValid({ benefitType: 'POINTS', benefitValue: 50 }, 100));
  assert.ok(!isBenefitValid({ benefitType: 'POINTS', benefitValue: 2.5 }, 100));
  assert.ok(!isBenefitValid({ benefitType: 'POINTS', benefitValue: -5 }, 100));
});

/* ------------------------------------------------------------- eligibility */

test('a new customer is new on every clause at once', () => {
  const base = {
    hasPreviousCompletedSale: false,
    hasNonRejectedAttribution: false,
    phoneAlreadyKnown: false,
    isAffiliate: false,
    isTestAccount: false,
    isBlocked: false,
  };
  assert.equal(isNewCustomer(base), true);

  for (const key of Object.keys(base) as Array<keyof typeof base>) {
    assert.equal(
      isNewCustomer({ ...base, [key]: true }),
      false,
      `${key} should disqualify on its own`,
    );
  }
});

test('a sale qualifies only when nothing is wrong with it', () => {
  const base = {
    belongsToMerchant: true,
    hasCustomer: true,
    amount: 250,
    isCompleted: true,
    isCancelled: false,
    isRefunded: false,
    isReversed: false,
    isDuplicate: false,
    meetsMinimumAmount: true,
  };
  assert.equal(isQualifyingSale(base), true);

  assert.equal(isQualifyingSale({ ...base, amount: 0 }), false);
  assert.equal(isQualifyingSale({ ...base, amount: -1 }), false);
  for (const key of [
    'belongsToMerchant',
    'hasCustomer',
    'isCompleted',
    'meetsMinimumAmount',
  ] as const) {
    assert.equal(isQualifyingSale({ ...base, [key]: false }), false, key);
  }
  for (const key of ['isCancelled', 'isRefunded', 'isReversed', 'isDuplicate'] as const) {
    assert.equal(isQualifyingSale({ ...base, [key]: true }), false, key);
  }
});

/* ---------------------------------------------------------------- benefit */

test('a percentage is taken in centavos and rounded down', () => {
  // 10% of 99.99 is 9.999. Rounding up would hand over a centavo the code does
  // not authorise, every time, on every such sale.
  const result = calculateBenefit({ benefitType: 'PERCENTAGE', benefitValue: 10 }, 99.99);
  assert.equal(result.discountAmount, 9.99);
  assert.equal(result.netAmount, 90);
});

test('the net and the discount always add back to the gross', () => {
  for (const gross of [0.01, 1, 33.33, 99.99, 1234.56, 7.77]) {
    for (const percent of [1, 7, 13, 33, 50]) {
      const result = calculateBenefit(
        { benefitType: 'PERCENTAGE', benefitValue: percent },
        gross,
      );
      assert.equal(
        Math.round((result.netAmount + result.discountAmount) * 100),
        Math.round(gross * 100),
        `${percent}% of ${gross} does not add back`,
      );
    }
  }
});

test('a discount never exceeds the bill', () => {
  const result = calculateBenefit({ benefitType: 'FIXED_AMOUNT', benefitValue: 500 }, 100);
  assert.equal(result.discountAmount, 100);
  assert.equal(result.netAmount, 0);
});

test('a points benefit leaves the amount alone', () => {
  const result = calculateBenefit({ benefitType: 'POINTS', benefitValue: 150 }, 250);
  assert.equal(result.netAmount, 250);
  assert.equal(result.discountAmount, 0);
  assert.equal(result.pointsAwarded, 150);
});

test('the benefit says what it is in words the customer can be told', () => {
  assert.equal(
    calculateBenefit({ benefitType: 'FIXED_AMOUNT', benefitValue: 50 }, 250).displayText,
    '50 MT de desconto',
  );
  assert.equal(
    calculateBenefit({ benefitType: 'POINTS', benefitValue: 150 }, 250).displayText,
    '150 pontos extra',
  );
  assert.match(
    calculateBenefit({ benefitType: 'PERCENTAGE', benefitValue: 10 }, 250).displayText,
    /^10% de desconto \(25 MT\)$/,
  );
});

test('a zero sale produces a zero benefit rather than a negative one', () => {
  const result = calculateBenefit({ benefitType: 'PERCENTAGE', benefitValue: 50 }, 0);
  assert.equal(result.discountAmount, 0);
  assert.equal(result.netAmount, 0);
});

/* ---------------------------------------------------------------- rewards */

test('the approval setting decides where a new reward lands', () => {
  assert.equal(planFirstSaleReward(config())?.status, 'PENDING');
  assert.equal(
    planFirstSaleReward(config({ rewardApprovalRequired: false }))?.status,
    'APPROVED',
  );
});

test('a reward of zero points is not written at all', () => {
  // It would sit in the approvals queue meaning nothing.
  assert.equal(planFirstSaleReward(config({ firstSaleRewardPoints: 0 })), null);
});

test('the return reward is off unless the business turned it on', () => {
  assert.equal(planReturnReward(config(), NOW, NOW + DAY), null);
  assert.equal(
    planReturnReward(
      config({ returnRewardEnabled: true, returnRewardPoints: 50 }),
      NOW,
      NOW + DAY,
    )?.value,
    50,
  );
});

test('the return window is counted from the first sale', () => {
  const settings = config({ returnRewardEnabled: true, returnRewardPoints: 50 });
  assert.ok(planReturnReward(settings, NOW, NOW + 30 * DAY));
  assert.equal(planReturnReward(settings, NOW, NOW + 30 * DAY + 1), null);
});

test('a return that predates the first sale is not a return', () => {
  assert.equal(isWithinReturnWindow(config(), NOW, NOW - DAY), false);
});

test('a cancellation takes back what it can and flags what it cannot', () => {
  const { cancellable, needsManualReview } = rewardsAffectedByCancellation([
    { id: 'r1', status: 'PENDING' },
    { id: 'r2', status: 'APPROVED' },
    { id: 'r3', status: 'PAID' },
    { id: 'r4', status: 'CANCELLED' },
  ]);

  assert.deepEqual(cancellable, ['r1', 'r2']);
  // Points already handed over are not undone by a status change.
  assert.deepEqual(needsManualReview, ['r3']);
});

/* ---------------------------------------------------------------- metrics */

test('conversion is confirmed acquisitions over attempts', () => {
  const metrics = summarizeAffiliateMetrics({
    uniqueValidationAttempts: 8,
    confirmedAttributions: 2,
    rejectedAttributions: 1,
    returnedCustomers: 1,
    pendingRewardCount: 1,
    pendingRewardPoints: 100,
    approvedRewardCount: 1,
    approvedRewardPoints: 100,
    lastEventAt: NOW,
  });
  assert.equal(metrics.conversionRate, 0.25);
});

test('no attempts is zero, not NaN', () => {
  // A division by zero reaching a screen prints "NaN%" to a business owner.
  const metrics = summarizeAffiliateMetrics({
    uniqueValidationAttempts: 0,
    confirmedAttributions: 0,
    rejectedAttributions: 0,
    returnedCustomers: 0,
    pendingRewardCount: 0,
    pendingRewardPoints: 0,
    approvedRewardCount: 0,
    approvedRewardPoints: 0,
    lastEventAt: null,
  });
  assert.equal(metrics.conversionRate, 0);
  assert.ok(Number.isFinite(metrics.conversionRate));
});

test('metrics carry no way to identify a person', () => {
  const metrics = summarizeAffiliateMetrics({
    uniqueValidationAttempts: 1,
    confirmedAttributions: 1,
    rejectedAttributions: 0,
    returnedCustomers: 0,
    pendingRewardCount: 0,
    pendingRewardPoints: 0,
    approvedRewardCount: 0,
    approvedRewardPoints: 0,
    lastEventAt: NOW,
  });
  for (const value of Object.values(metrics)) {
    assert.ok(
      typeof value === 'number' || value === null,
      'a metrics field became something other than a count',
    );
  }
});
