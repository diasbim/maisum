import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AFFILIATE_API_MESSAGE,
  AffiliateApiError,
  canTransitionReward,
  parseAffiliateName,
  parseAffiliateStatus,
  parseBenefit,
  parseBodyObject,
  parseCodeText,
  parseFirstVisitOnly,
  parseIdParam,
  parseOptionalSaleAmount,
  parsePhone,
  parseUsageLimit,
  parseValidity,
  parseValidityPair,
  rateLimitedResponse,
  referralRejection,
  referralValidationResponse,
  rewardTransitionError,
  toAdminAffiliateDto,
  toAffiliateCodeDto,
  toAffiliateDto,
  toAffiliateRewardDto,
  REWARD_TRANSITIONS,
} from './affiliate_api_contracts.js';
import {
  PERCENTAGE_RANGE,
  REFERRAL_REASON,
  REFERRAL_REASON_MESSAGE,
  REWARD_STATUS,
  type ReferralReason,
} from './affiliate_contracts.js';

/**
 * The boundary between a request and the referral domain.
 *
 * Everything asserted here is a refusal or a shape — no Firestore, no Express.
 * That is deliberate: these are the rules that decide whether a merchant's
 * typo becomes a stored discount, and they should be provable without standing
 * anything up.
 */

const NOW = 1_800_000_000_000;
const DAY = 24 * 60 * 60 * 1000;

function refusal(run: () => unknown): AffiliateApiError {
  try {
    run();
  } catch (error) {
    assert.ok(error instanceof AffiliateApiError, `not an API error: ${error}`);
    return error as AffiliateApiError;
  }
  throw new Error('expected a refusal, got a value');
}

/* -------------------------------------------------------------------- names */

test('a name yields the first word the code will be built from', () => {
  const parsed = parseAffiliateName('  João   Alberto  Cossa ');
  assert.equal(parsed.firstName, 'João');
  assert.equal(parsed.lastName, 'Alberto Cossa');
  assert.equal(parsed.displayName, 'João Alberto Cossa');
});

test('a single name is a name, with no surname invented', () => {
  const parsed = parseAffiliateName('Ana');
  assert.equal(parsed.firstName, 'Ana');
  assert.equal(parsed.lastName, null);
});

test('a name that cannot be typed is refused rather than stored', () => {
  for (const value of ['', ' ', 'A', '123', '<script>', '  !!  ', null, 42, {}]) {
    assert.equal(refusal(() => parseAffiliateName(value)).code, 'invalid_name');
  }
});

test('a name longer than a form field is refused', () => {
  assert.equal(
    refusal(() => parseAffiliateName('a'.repeat(61))).code,
    'invalid_name',
  );
});

/* ------------------------------------------------------------------- phones */

test('a phone is whatever the product\u2019s own normaliser says it is', () => {
  const normalize = (raw: unknown) =>
    raw === '841234567' ? '+258841234567' : null;
  assert.equal(parsePhone('841234567', normalize), '+258841234567');
  assert.equal(refusal(() => parsePhone('123', normalize)).code, 'invalid_phone');
  assert.equal(refusal(() => parsePhone(undefined, normalize)).code, 'invalid_phone');
});

/* ----------------------------------------------------------------- benefits */

test('each benefit type accepts what it is for', () => {
  assert.deepEqual(parseBenefit('PERCENTAGE', 10), { type: 'PERCENTAGE', value: 10 });
  assert.deepEqual(parseBenefit('fixed_amount', 50), {
    type: 'FIXED_AMOUNT',
    value: 50,
  });
  assert.deepEqual(parseBenefit(' POINTS ', 200), { type: 'POINTS', value: 200 });
});

test('a percentage outside the configured range is refused at both ends', () => {
  assert.equal(
    refusal(() => parseBenefit('PERCENTAGE', PERCENTAGE_RANGE.min - 0.5)).code,
    'invalid_percentage',
  );
  assert.equal(
    refusal(() => parseBenefit('PERCENTAGE', PERCENTAGE_RANGE.max + 1)).code,
    'invalid_percentage',
  );
  // The edges themselves are inside.
  assert.ok(parseBenefit('PERCENTAGE', PERCENTAGE_RANGE.min));
  assert.ok(parseBenefit('PERCENTAGE', PERCENTAGE_RANGE.max));
});

test('a benefit value that is not a positive number never reaches storage', () => {
  for (const value of [0, -1, Number.NaN, Number.POSITIVE_INFINITY, '50', null]) {
    assert.equal(
      refusal(() => parseBenefit('FIXED_AMOUNT', value)).code,
      'invalid_benefit_value',
    );
  }
});

test('an unbounded money benefit is refused, so a typo cannot pay out', () => {
  assert.ok(parseBenefit('FIXED_AMOUNT', 1_000_000));
  assert.equal(
    refusal(() => parseBenefit('FIXED_AMOUNT', 1_000_001)).code,
    'invalid_benefit_value',
  );
  // Sub-centavo amounts are not money in this product.
  assert.equal(
    refusal(() => parseBenefit('FIXED_AMOUNT', 10.005)).code,
    'invalid_benefit_value',
  );
});

test('points are whole, and bounded', () => {
  assert.equal(
    refusal(() => parseBenefit('POINTS', 10.5)).code,
    'invalid_benefit_value',
  );
  assert.equal(
    refusal(() => parseBenefit('POINTS', 100_001)).code,
    'invalid_benefit_value',
  );
});

test('an unknown benefit type does not fall back to a known one', () => {
  for (const value of ['DISCOUNT', '', 'percentage%', 7, undefined]) {
    assert.equal(
      refusal(() => parseBenefit(value, 10)).code,
      'invalid_benefit_type',
    );
  }
});

/* -------------------------------------------------------------- usage limit */

test('an absent usage limit is unlimited, and says so as null', () => {
  assert.equal(parseUsageLimit(undefined), null);
  assert.equal(parseUsageLimit(null), null);
  assert.equal(parseUsageLimit(5), 5);
});

test('a usage limit that is not a positive whole number is refused', () => {
  for (const value of [0, -3, 1.5, '5', 100_001]) {
    assert.equal(
      refusal(() => parseUsageLimit(value)).code,
      'invalid_usage_limit',
    );
  }
});

/* ------------------------------------------------------------------ validity */

test('validity defaults to the plan\u2019s thirty days from now', () => {
  const validity = parseValidity(undefined, undefined, NOW, 30);
  assert.equal(validity.startsAt, NOW);
  assert.equal(validity.expiresAt, NOW + 30 * DAY);
});

test('a window that has already closed is refused rather than stored', () => {
  assert.equal(
    refusal(() => parseValidity(NOW - 10 * DAY, NOW - DAY, NOW, 30)).code,
    'invalid_dates',
  );
});

test('an end before its start is refused, and so is a zero-length window', () => {
  assert.equal(
    refusal(() => parseValidity(NOW + DAY, NOW, NOW, 30)).code,
    'invalid_dates',
  );
  assert.equal(
    refusal(() => parseValidity(NOW + DAY, NOW + DAY, NOW, 30)).code,
    'invalid_dates',
  );
});

test('a window longer than two years is refused', () => {
  assert.equal(
    refusal(() => parseValidity(NOW, NOW + 731 * DAY, NOW, 30)).code,
    'invalid_dates',
  );
});

test('a date that is not an epoch is refused, not coerced', () => {
  for (const value of ['2026-01-01', 0, -1, 1.5, true]) {
    assert.equal(
      refusal(() => parseValidity(value, undefined, NOW, 30)).code,
      'invalid_dates',
    );
  }
});

test('an edit that moves one end of the window must state the other', () => {
  // Defaulting the start to "now" on a PATCH would quietly bring a code that
  // has not begun yet forward to today.
  assert.equal(
    refusal(() => parseValidityPair(undefined, NOW + 10 * DAY, NOW)).code,
    'invalid_dates',
  );
  assert.equal(
    refusal(() => parseValidityPair(NOW, undefined, NOW)).code,
    'invalid_dates',
  );
  assert.deepEqual(parseValidityPair(NOW, NOW + 10 * DAY, NOW), {
    startsAt: NOW,
    expiresAt: NOW + 10 * DAY,
  });
});

/* ------------------------------------------------------------- odds and ends */

test('first-visit-only is a boolean or nothing, never a truthy string', () => {
  assert.equal(parseFirstVisitOnly(undefined, true), true);
  assert.equal(parseFirstVisitOnly(false, true), false);
  assert.equal(
    refusal(() => parseFirstVisitOnly('false', true)).code,
    'invalid_first_visit_only',
  );
});

test('a code is text of a plausible length', () => {
  assert.equal(parseCodeText('  afi-joao-7k2p '), 'afi-joao-7k2p');
  assert.equal(refusal(() => parseCodeText('ab')).code, 'invalid_code');
  assert.equal(refusal(() => parseCodeText('x'.repeat(41))).code, 'invalid_code');
  assert.equal(refusal(() => parseCodeText(null)).code, 'invalid_code');
});

test('a sale amount is optional, but never zero or negative when sent', () => {
  assert.equal(parseOptionalSaleAmount(undefined), null);
  assert.equal(parseOptionalSaleAmount(500), 500);
  assert.equal(refusal(() => parseOptionalSaleAmount(0)).code, 'invalid_body');
  assert.equal(refusal(() => parseOptionalSaleAmount('500')).code, 'invalid_body');
});

test('a missing path id answers not found, not bad request', () => {
  const error = refusal(() => parseIdParam('  ', 'affiliate_not_found'));
  assert.equal(error.status, 404);
  assert.equal(error.code, 'affiliate_not_found');
});

test('a body that is not an object is refused before any field is read', () => {
  assert.equal(refusal(() => parseBodyObject(null)).code, 'invalid_body');
  assert.equal(refusal(() => parseBodyObject([])).code, 'invalid_body');
  assert.equal(refusal(() => parseBodyObject('{}')).code, 'invalid_body');
  assert.deepEqual(parseBodyObject({ a: 1 }), { a: 1 });
});

test('an affiliate status must be one of the stored three', () => {
  assert.equal(parseAffiliateStatus('suspended'), 'SUSPENDED');
  assert.equal(refusal(() => parseAffiliateStatus('DELETED')).code, 'invalid_status');
});

/* -------------------------------------------------------- reward transitions */

test('a reward moves only the ways the approval flow allows', () => {
  assert.ok(canTransitionReward('PENDING', 'APPROVED'));
  assert.ok(canTransitionReward('PENDING', 'CANCELLED'));
  assert.ok(canTransitionReward('APPROVED', 'CANCELLED'));
  assert.ok(canTransitionReward('APPROVED', 'PAID'));

  assert.equal(canTransitionReward('APPROVED', 'APPROVED'), false);
  assert.equal(canTransitionReward('CANCELLED', 'APPROVED'), false);
  assert.equal(canTransitionReward('PENDING', 'PAID'), false);
});

test('paid is terminal, because points already given are not un-given', () => {
  assert.deepEqual([...REWARD_TRANSITIONS.PAID], []);
  const error = rewardTransitionError('PAID', 'CANCELLED');
  assert.equal(error.status, 409);
  assert.equal(error.code, 'reward_paid');
});

test('every stored reward status has a transition rule', () => {
  for (const status of REWARD_STATUS) {
    assert.ok(
      Array.isArray(REWARD_TRANSITIONS[status]),
      `${status} has no transition rule`,
    );
  }
});

test('a refused decision says which of the three things went wrong', () => {
  assert.equal(rewardTransitionError('APPROVED', 'APPROVED').code, 'reward_not_pending');
  assert.equal(
    rewardTransitionError('CANCELLED', 'CANCELLED').code,
    'reward_already_closed',
  );
});

/* ------------------------------------------------------- validation response */

const VALID_SOURCE = {
  validation: { ok: true } as const,
  affiliateId: 'af_1',
  affiliateName: 'João',
  codeId: 'ac_1',
  normalizedCode: 'AFI-JOAO-7K2P',
  firstVisitOnly: true,
  benefit: { type: 'FIXED_AMOUNT' as const, value: 50, displayText: '50 MT de desconto' },
};

test('a passing validation answers with the code\u2019s own benefit', () => {
  const body = referralValidationResponse(VALID_SOURCE, NOW);
  assert.equal(body.valid, true);
  if (!body.valid) throw new Error('unreachable');
  assert.equal(body.affiliate_name, 'João');
  assert.equal(body.normalized_code, 'AFI-JOAO-7K2P');
  assert.equal(body.first_visit_only, true);
  assert.deepEqual(body.benefit, {
    type: 'FIXED_AMOUNT',
    value: 50,
    display_text: '50 MT de desconto',
  });
  assert.equal(body.validated_at, NOW);
});

test('a failing validation answers the reason and its Portuguese', () => {
  for (const reason of REFERRAL_REASON) {
    const body = referralValidationResponse(
      { ...VALID_SOURCE, validation: { ok: false, reason } },
      NOW,
    );
    assert.equal(body.valid, false);
    if (body.valid) throw new Error('unreachable');
    assert.equal(body.reason, reason);
    assert.equal(body.message, REFERRAL_REASON_MESSAGE[reason]);
    // A rejection carries no affiliate, no code and no benefit: that is what
    // stops it from being a way to read another business's code.
    assert.equal(Object.keys(body).sort().join(','), 'message,reason,valid,validated_at');
  }
});

test('a rejection never names a business, a phone or an id', () => {
  for (const reason of REFERRAL_REASON) {
    const rejection = referralRejection(reason as ReferralReason, NOW);
    if (rejection.valid) throw new Error('unreachable');
    assert.ok(rejection.message.length <= 60, `${reason} message is too long`);
    assert.ok(!/\d{6,}/.test(rejection.message), `${reason} message carries digits`);
  }
});

test('a pass with no benefit degrades to a refusal rather than a free discount', () => {
  const body = referralValidationResponse({ ...VALID_SOURCE, benefit: null }, NOW);
  assert.equal(body.valid, false);
  if (body.valid) throw new Error('unreachable');
  assert.equal(body.reason, 'BENEFIT_INVALID');
});

/* ------------------------------------------------------------- rate limiting */

test('a refused caller is told nothing except when to come back', () => {
  const refused = rateLimitedResponse(12_400);
  assert.equal(refused.status, 429);
  assert.equal(refused.headers['Retry-After'], '13');
  assert.deepEqual(refused.body, {
    success: false,
    code: 'rate_limited',
    message: AFFILIATE_API_MESSAGE.rate_limited,
  });
  // No reason code, so a 429 cannot be read as "that code exists".
  assert.equal('reason' in refused.body, false);
});

test('retry-after is never zero seconds, which would mean "now"', () => {
  assert.equal(rateLimitedResponse(0).headers['Retry-After'], '1');
  assert.equal(rateLimitedResponse(1).headers['Retry-After'], '1');
});

/* ------------------------------------------------------------------ mappers */

test('an affiliate row maps without inventing a status', () => {
  const dto = toAffiliateDto('af_1', {
    display_name: 'Ana Cossa',
    first_name: 'Ana',
    last_name: 'Cossa',
    phone_e164: '+258841234567',
    status: 'ACTIVE',
    created_at: NOW,
    updated_at: NOW,
  });
  assert.equal(dto.name, 'Ana Cossa');
  assert.equal(dto.phone_last4, '4567');
  assert.equal(dto.status, 'ACTIVE');
});

test('an unreadable affiliate status reads as inactive, not active', () => {
  assert.equal(toAffiliateDto('af_1', { status: 'GONE' }).status, 'INACTIVE');
  assert.equal(toAffiliateDto('af_1', {}).status, 'INACTIVE');
});

test('the console never receives a reachable phone number', () => {
  const dto = toAdminAffiliateDto('af_1', {
    display_name: 'Ana',
    phone_e164: '+258841234567',
    status: 'ACTIVE',
    merchant_ids: ['m1', 'm2', 7],
  });
  assert.equal(dto.phone_masked, '***4567');
  assert.equal(dto.merchant_count, 2);
  assert.equal('phone' in dto, false);
});

test('a code row keeps its limit as null rather than as zero', () => {
  const dto = toAffiliateCodeDto('ac_1', {
    merchant_id: 'm1',
    affiliate_id: 'af_1',
    code: 'AFI-ANA-7K2P',
    normalized_code: 'AFI-ANA-7K2P',
    benefit_type: 'PERCENTAGE',
    benefit_value: 10,
    usage_limit: null,
    usage_count: 3,
    status: 'ACTIVE',
  });
  assert.equal(dto.usage_limit, null);
  assert.equal(dto.usage_count, 3);
  assert.equal(dto.first_visit_only, true);
});

test('a code with an unreadable status reads as disabled', () => {
  assert.equal(toAffiliateCodeDto('ac_1', { status: 'ON' }).status, 'DISABLED');
});

test('a reward with an unreadable status reads as cancelled, never pending', () => {
  // Defaulting to pending would put points nobody earned in the approvals
  // queue, where approving them is one click.
  assert.equal(toAffiliateRewardDto('ar_1', { status: 'WAT' }).status, 'CANCELLED');
  assert.equal(toAffiliateRewardDto('ar_1', {}).status, 'CANCELLED');
});

test('every message the API can raise is written in Portuguese and is short', () => {
  for (const [key, message] of Object.entries(AFFILIATE_API_MESSAGE)) {
    assert.ok(message.trim().length > 0, `${key} is empty`);
    assert.ok(message.length <= 70, `${key} is too long for a toast`);
    assert.ok(/[.!?]$/.test(message), `${key} is not a sentence`);
  }
});
