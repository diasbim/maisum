"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_api_contracts_js_1 = require("./affiliate_api_contracts.js");
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
/**
 * The boundary between a request and the referral domain.
 *
 * Everything asserted here is a refusal or a shape — no Firestore, no Express.
 * That is deliberate: these are the rules that decide whether a merchant's
 * typo becomes a stored discount, and they should be provable without standing
 * anything up.
 */
const NOW = 1800000000000;
const DAY = 24 * 60 * 60 * 1000;
function refusal(run) {
    try {
        run();
    }
    catch (error) {
        strict_1.default.ok(error instanceof affiliate_api_contracts_js_1.AffiliateApiError, `not an API error: ${error}`);
        return error;
    }
    throw new Error('expected a refusal, got a value');
}
/* -------------------------------------------------------------------- names */
(0, node_test_1.default)('a name yields the first word the code will be built from', () => {
    const parsed = (0, affiliate_api_contracts_js_1.parseAffiliateName)('  João   Alberto  Cossa ');
    strict_1.default.equal(parsed.firstName, 'João');
    strict_1.default.equal(parsed.lastName, 'Alberto Cossa');
    strict_1.default.equal(parsed.displayName, 'João Alberto Cossa');
});
(0, node_test_1.default)('a single name is a name, with no surname invented', () => {
    const parsed = (0, affiliate_api_contracts_js_1.parseAffiliateName)('Ana');
    strict_1.default.equal(parsed.firstName, 'Ana');
    strict_1.default.equal(parsed.lastName, null);
});
(0, node_test_1.default)('a name that cannot be typed is refused rather than stored', () => {
    for (const value of ['', ' ', 'A', '123', '<script>', '  !!  ', null, 42, {}]) {
        strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseAffiliateName)(value)).code, 'invalid_name');
    }
});
(0, node_test_1.default)('a name longer than a form field is refused', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseAffiliateName)('a'.repeat(61))).code, 'invalid_name');
});
/* ------------------------------------------------------------------- phones */
(0, node_test_1.default)('a phone is whatever the product\u2019s own normaliser says it is', () => {
    const normalize = (raw) => raw === '841234567' ? '+258841234567' : null;
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parsePhone)('841234567', normalize), '+258841234567');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parsePhone)('123', normalize)).code, 'invalid_phone');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parsePhone)(undefined, normalize)).code, 'invalid_phone');
});
/* ----------------------------------------------------------------- benefits */
(0, node_test_1.default)('each benefit type accepts what it is for', () => {
    strict_1.default.deepEqual((0, affiliate_api_contracts_js_1.parseBenefit)('PERCENTAGE', 10), { type: 'PERCENTAGE', value: 10 });
    strict_1.default.deepEqual((0, affiliate_api_contracts_js_1.parseBenefit)('fixed_amount', 50), {
        type: 'FIXED_AMOUNT',
        value: 50,
    });
    strict_1.default.deepEqual((0, affiliate_api_contracts_js_1.parseBenefit)(' POINTS ', 200), { type: 'POINTS', value: 200 });
});
(0, node_test_1.default)('a percentage outside the configured range is refused at both ends', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('PERCENTAGE', affiliate_contracts_js_1.PERCENTAGE_RANGE.min - 0.5)).code, 'invalid_percentage');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('PERCENTAGE', affiliate_contracts_js_1.PERCENTAGE_RANGE.max + 1)).code, 'invalid_percentage');
    // The edges themselves are inside.
    strict_1.default.ok((0, affiliate_api_contracts_js_1.parseBenefit)('PERCENTAGE', affiliate_contracts_js_1.PERCENTAGE_RANGE.min));
    strict_1.default.ok((0, affiliate_api_contracts_js_1.parseBenefit)('PERCENTAGE', affiliate_contracts_js_1.PERCENTAGE_RANGE.max));
});
(0, node_test_1.default)('a benefit value that is not a positive number never reaches storage', () => {
    for (const value of [0, -1, Number.NaN, Number.POSITIVE_INFINITY, '50', null]) {
        strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('FIXED_AMOUNT', value)).code, 'invalid_benefit_value');
    }
});
(0, node_test_1.default)('an unbounded money benefit is refused, so a typo cannot pay out', () => {
    strict_1.default.ok((0, affiliate_api_contracts_js_1.parseBenefit)('FIXED_AMOUNT', 1000000));
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('FIXED_AMOUNT', 1000001)).code, 'invalid_benefit_value');
    // Sub-centavo amounts are not money in this product.
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('FIXED_AMOUNT', 10.005)).code, 'invalid_benefit_value');
});
(0, node_test_1.default)('points are whole, and bounded', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('POINTS', 10.5)).code, 'invalid_benefit_value');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)('POINTS', 100001)).code, 'invalid_benefit_value');
});
(0, node_test_1.default)('an unknown benefit type does not fall back to a known one', () => {
    for (const value of ['DISCOUNT', '', 'percentage%', 7, undefined]) {
        strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBenefit)(value, 10)).code, 'invalid_benefit_type');
    }
});
/* -------------------------------------------------------------- usage limit */
(0, node_test_1.default)('an absent usage limit is unlimited, and says so as null', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseUsageLimit)(undefined), null);
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseUsageLimit)(null), null);
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseUsageLimit)(5), 5);
});
(0, node_test_1.default)('a usage limit that is not a positive whole number is refused', () => {
    for (const value of [0, -3, 1.5, '5', 100001]) {
        strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseUsageLimit)(value)).code, 'invalid_usage_limit');
    }
});
/* ------------------------------------------------------------------ validity */
(0, node_test_1.default)('validity defaults to the plan\u2019s thirty days from now', () => {
    const validity = (0, affiliate_api_contracts_js_1.parseValidity)(undefined, undefined, NOW, 30);
    strict_1.default.equal(validity.startsAt, NOW);
    strict_1.default.equal(validity.expiresAt, NOW + 30 * DAY);
});
(0, node_test_1.default)('a window that has already closed is refused rather than stored', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidity)(NOW - 10 * DAY, NOW - DAY, NOW, 30)).code, 'invalid_dates');
});
(0, node_test_1.default)('an end before its start is refused, and so is a zero-length window', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidity)(NOW + DAY, NOW, NOW, 30)).code, 'invalid_dates');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidity)(NOW + DAY, NOW + DAY, NOW, 30)).code, 'invalid_dates');
});
(0, node_test_1.default)('a window longer than two years is refused', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidity)(NOW, NOW + 731 * DAY, NOW, 30)).code, 'invalid_dates');
});
(0, node_test_1.default)('a date that is not an epoch is refused, not coerced', () => {
    for (const value of ['2026-01-01', 0, -1, 1.5, true]) {
        strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidity)(value, undefined, NOW, 30)).code, 'invalid_dates');
    }
});
(0, node_test_1.default)('an edit that moves one end of the window must state the other', () => {
    // Defaulting the start to "now" on a PATCH would quietly bring a code that
    // has not begun yet forward to today.
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidityPair)(undefined, NOW + 10 * DAY, NOW)).code, 'invalid_dates');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseValidityPair)(NOW, undefined, NOW)).code, 'invalid_dates');
    strict_1.default.deepEqual((0, affiliate_api_contracts_js_1.parseValidityPair)(NOW, NOW + 10 * DAY, NOW), {
        startsAt: NOW,
        expiresAt: NOW + 10 * DAY,
    });
});
/* ------------------------------------------------------------- odds and ends */
(0, node_test_1.default)('first-visit-only is a boolean or nothing, never a truthy string', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseFirstVisitOnly)(undefined, true), true);
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseFirstVisitOnly)(false, true), false);
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseFirstVisitOnly)('false', true)).code, 'invalid_first_visit_only');
});
(0, node_test_1.default)('a code is text of a plausible length', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseCodeText)('  afi-joao-7k2p '), 'afi-joao-7k2p');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseCodeText)('ab')).code, 'invalid_code');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseCodeText)('x'.repeat(41))).code, 'invalid_code');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseCodeText)(null)).code, 'invalid_code');
});
(0, node_test_1.default)('a sale amount is optional, but never zero or negative when sent', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseOptionalSaleAmount)(undefined), null);
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseOptionalSaleAmount)(500), 500);
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseOptionalSaleAmount)(0)).code, 'invalid_body');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseOptionalSaleAmount)('500')).code, 'invalid_body');
});
(0, node_test_1.default)('a missing path id answers not found, not bad request', () => {
    const error = refusal(() => (0, affiliate_api_contracts_js_1.parseIdParam)('  ', 'affiliate_not_found'));
    strict_1.default.equal(error.status, 404);
    strict_1.default.equal(error.code, 'affiliate_not_found');
});
(0, node_test_1.default)('a body that is not an object is refused before any field is read', () => {
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBodyObject)(null)).code, 'invalid_body');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBodyObject)([])).code, 'invalid_body');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseBodyObject)('{}')).code, 'invalid_body');
    strict_1.default.deepEqual((0, affiliate_api_contracts_js_1.parseBodyObject)({ a: 1 }), { a: 1 });
});
(0, node_test_1.default)('an affiliate status must be one of the stored three', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.parseAffiliateStatus)('suspended'), 'SUSPENDED');
    strict_1.default.equal(refusal(() => (0, affiliate_api_contracts_js_1.parseAffiliateStatus)('DELETED')).code, 'invalid_status');
});
/* -------------------------------------------------------- reward transitions */
(0, node_test_1.default)('a reward moves only the ways the approval flow allows', () => {
    strict_1.default.ok((0, affiliate_api_contracts_js_1.canTransitionReward)('PENDING', 'APPROVED'));
    strict_1.default.ok((0, affiliate_api_contracts_js_1.canTransitionReward)('PENDING', 'CANCELLED'));
    strict_1.default.ok((0, affiliate_api_contracts_js_1.canTransitionReward)('APPROVED', 'CANCELLED'));
    strict_1.default.ok((0, affiliate_api_contracts_js_1.canTransitionReward)('APPROVED', 'PAID'));
    strict_1.default.equal((0, affiliate_api_contracts_js_1.canTransitionReward)('APPROVED', 'APPROVED'), false);
    strict_1.default.equal((0, affiliate_api_contracts_js_1.canTransitionReward)('CANCELLED', 'APPROVED'), false);
    strict_1.default.equal((0, affiliate_api_contracts_js_1.canTransitionReward)('PENDING', 'PAID'), false);
});
(0, node_test_1.default)('paid is terminal, because points already given are not un-given', () => {
    strict_1.default.deepEqual([...affiliate_api_contracts_js_1.REWARD_TRANSITIONS.PAID], []);
    const error = (0, affiliate_api_contracts_js_1.rewardTransitionError)('PAID', 'CANCELLED');
    strict_1.default.equal(error.status, 409);
    strict_1.default.equal(error.code, 'reward_paid');
});
(0, node_test_1.default)('every stored reward status has a transition rule', () => {
    for (const status of affiliate_contracts_js_1.REWARD_STATUS) {
        strict_1.default.ok(Array.isArray(affiliate_api_contracts_js_1.REWARD_TRANSITIONS[status]), `${status} has no transition rule`);
    }
});
(0, node_test_1.default)('a refused decision says which of the three things went wrong', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.rewardTransitionError)('APPROVED', 'APPROVED').code, 'reward_not_pending');
    strict_1.default.equal((0, affiliate_api_contracts_js_1.rewardTransitionError)('CANCELLED', 'CANCELLED').code, 'reward_already_closed');
});
/* ------------------------------------------------------- validation response */
const VALID_SOURCE = {
    validation: { ok: true },
    affiliateId: 'af_1',
    affiliateName: 'João',
    codeId: 'ac_1',
    normalizedCode: 'AFI-JOAO-7K2P',
    firstVisitOnly: true,
    benefit: { type: 'FIXED_AMOUNT', value: 50, displayText: '50 MT de desconto' },
};
(0, node_test_1.default)('a passing validation answers with the code\u2019s own benefit', () => {
    const body = (0, affiliate_api_contracts_js_1.referralValidationResponse)(VALID_SOURCE, NOW);
    strict_1.default.equal(body.valid, true);
    if (!body.valid)
        throw new Error('unreachable');
    strict_1.default.equal(body.affiliate_name, 'João');
    strict_1.default.equal(body.normalized_code, 'AFI-JOAO-7K2P');
    strict_1.default.equal(body.first_visit_only, true);
    strict_1.default.deepEqual(body.benefit, {
        type: 'FIXED_AMOUNT',
        value: 50,
        display_text: '50 MT de desconto',
    });
    strict_1.default.equal(body.validated_at, NOW);
});
(0, node_test_1.default)('a failing validation answers the reason and its Portuguese', () => {
    for (const reason of affiliate_contracts_js_1.REFERRAL_REASON) {
        const body = (0, affiliate_api_contracts_js_1.referralValidationResponse)({ ...VALID_SOURCE, validation: { ok: false, reason } }, NOW);
        strict_1.default.equal(body.valid, false);
        if (body.valid)
            throw new Error('unreachable');
        strict_1.default.equal(body.reason, reason);
        strict_1.default.equal(body.message, affiliate_contracts_js_1.REFERRAL_REASON_MESSAGE[reason]);
        // A rejection carries no affiliate, no code and no benefit: that is what
        // stops it from being a way to read another business's code.
        strict_1.default.equal(Object.keys(body).sort().join(','), 'message,reason,valid,validated_at');
    }
});
(0, node_test_1.default)('a rejection never names a business, a phone or an id', () => {
    for (const reason of affiliate_contracts_js_1.REFERRAL_REASON) {
        const rejection = (0, affiliate_api_contracts_js_1.referralRejection)(reason, NOW);
        if (rejection.valid)
            throw new Error('unreachable');
        strict_1.default.ok(rejection.message.length <= 60, `${reason} message is too long`);
        strict_1.default.ok(!/\d{6,}/.test(rejection.message), `${reason} message carries digits`);
    }
});
(0, node_test_1.default)('a pass with no benefit degrades to a refusal rather than a free discount', () => {
    const body = (0, affiliate_api_contracts_js_1.referralValidationResponse)({ ...VALID_SOURCE, benefit: null }, NOW);
    strict_1.default.equal(body.valid, false);
    if (body.valid)
        throw new Error('unreachable');
    strict_1.default.equal(body.reason, 'BENEFIT_INVALID');
});
/* ------------------------------------------------------------- rate limiting */
(0, node_test_1.default)('a refused caller is told nothing except when to come back', () => {
    const refused = (0, affiliate_api_contracts_js_1.rateLimitedResponse)(12400);
    strict_1.default.equal(refused.status, 429);
    strict_1.default.equal(refused.headers['Retry-After'], '13');
    strict_1.default.deepEqual(refused.body, {
        success: false,
        code: 'rate_limited',
        message: affiliate_api_contracts_js_1.AFFILIATE_API_MESSAGE.rate_limited,
    });
    // No reason code, so a 429 cannot be read as "that code exists".
    strict_1.default.equal('reason' in refused.body, false);
});
(0, node_test_1.default)('retry-after is never zero seconds, which would mean "now"', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.rateLimitedResponse)(0).headers['Retry-After'], '1');
    strict_1.default.equal((0, affiliate_api_contracts_js_1.rateLimitedResponse)(1).headers['Retry-After'], '1');
});
/* ------------------------------------------------------------------ mappers */
(0, node_test_1.default)('an affiliate row maps without inventing a status', () => {
    const dto = (0, affiliate_api_contracts_js_1.toAffiliateDto)('af_1', {
        display_name: 'Ana Cossa',
        first_name: 'Ana',
        last_name: 'Cossa',
        phone_e164: '+258841234567',
        status: 'ACTIVE',
        created_at: NOW,
        updated_at: NOW,
    });
    strict_1.default.equal(dto.name, 'Ana Cossa');
    strict_1.default.equal(dto.phone_last4, '4567');
    strict_1.default.equal(dto.status, 'ACTIVE');
});
(0, node_test_1.default)('an unreadable affiliate status reads as inactive, not active', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.toAffiliateDto)('af_1', { status: 'GONE' }).status, 'INACTIVE');
    strict_1.default.equal((0, affiliate_api_contracts_js_1.toAffiliateDto)('af_1', {}).status, 'INACTIVE');
});
(0, node_test_1.default)('the console never receives a reachable phone number', () => {
    const dto = (0, affiliate_api_contracts_js_1.toAdminAffiliateDto)('af_1', {
        display_name: 'Ana',
        phone_e164: '+258841234567',
        status: 'ACTIVE',
        merchant_ids: ['m1', 'm2', 7],
    });
    strict_1.default.equal(dto.phone_masked, '***4567');
    strict_1.default.equal(dto.merchant_count, 2);
    strict_1.default.equal('phone' in dto, false);
});
(0, node_test_1.default)('a code row keeps its limit as null rather than as zero', () => {
    const dto = (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)('ac_1', {
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
    strict_1.default.equal(dto.usage_limit, null);
    strict_1.default.equal(dto.usage_count, 3);
    strict_1.default.equal(dto.first_visit_only, true);
});
(0, node_test_1.default)('a code with an unreadable status reads as disabled', () => {
    strict_1.default.equal((0, affiliate_api_contracts_js_1.toAffiliateCodeDto)('ac_1', { status: 'ON' }).status, 'DISABLED');
});
(0, node_test_1.default)('a reward with an unreadable status reads as cancelled, never pending', () => {
    // Defaulting to pending would put points nobody earned in the approvals
    // queue, where approving them is one click.
    strict_1.default.equal((0, affiliate_api_contracts_js_1.toAffiliateRewardDto)('ar_1', { status: 'WAT' }).status, 'CANCELLED');
    strict_1.default.equal((0, affiliate_api_contracts_js_1.toAffiliateRewardDto)('ar_1', {}).status, 'CANCELLED');
});
(0, node_test_1.default)('every message the API can raise is written in Portuguese and is short', () => {
    for (const [key, message] of Object.entries(affiliate_api_contracts_js_1.AFFILIATE_API_MESSAGE)) {
        strict_1.default.ok(message.trim().length > 0, `${key} is empty`);
        strict_1.default.ok(message.length <= 70, `${key} is too long for a toast`);
        strict_1.default.ok(/[.!?]$/.test(message), `${key} is not a sentence`);
    }
});
