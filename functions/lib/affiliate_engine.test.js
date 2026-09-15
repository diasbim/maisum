"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_engine_js_1 = require("./affiliate_engine.js");
const NOW = 1788307006310;
const DAY = 24 * 60 * 60 * 1000;
function code(overrides = {}) {
    return {
        codeId: 'ac_1',
        merchantId: 'merchant-1',
        affiliateId: 'affiliate-1',
        enabled: true,
        validFrom: NOW - DAY,
        expiresAt: NOW + 29 * DAY,
        usageLimit: null,
        usageCount: 0,
        firstVisitOnly: true,
        benefitType: 'PERCENTAGE',
        benefitValue: 10,
        ...overrides,
    };
}
function context(overrides = {}) {
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
function config(overrides = {}) {
    return {
        ...affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG,
        enabled: true,
        firstSaleRewardPoints: 100,
        ...overrides,
    };
}
/* --------------------------------------------------------------- the codes */
(0, node_test_1.default)('a typed code is matched ignoring case and outer spaces', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.normalizeAffiliateCode)('  afi-joao-k7m2 '), 'AFI-JOAO-K7M2');
});
(0, node_test_1.default)('inner spaces are not forgiven, because a code is one token', () => {
    // Collapsing them would accept something that is not the code.
    strict_1.default.equal((0, affiliate_engine_js_1.normalizeAffiliateCode)('AFI JOAO K7M2'), 'AFI JOAO K7M2');
});
(0, node_test_1.default)('accents fold to ASCII so the code can be dictated', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)('João'), 'JOAO');
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)('Amélia Cossa'), 'AMELIA');
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)('Ângela'), 'ANGELA');
});
(0, node_test_1.default)('only the first name is used, and it is capped', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)('Guilhermina Nhamirre'), 'GUILHERM');
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)('Guilhermina Nhamirre').length, 8);
});
(0, node_test_1.default)('punctuation and separators are dropped, not turned into gaps', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)("O'Brien"), 'OBRIEN');
    strict_1.default.equal((0, affiliate_engine_js_1.foldCodeName)('Ana-Maria'), 'ANAMARIA');
});
(0, node_test_1.default)('a name that folds away still yields a usable code', () => {
    // Otherwise this produces AFI--K7M2, which reads as a bug to the merchant.
    strict_1.default.equal((0, affiliate_engine_js_1.buildAffiliateCode)('???', 'K7M2'), 'AFI-AFILIADO-K7M2');
    strict_1.default.equal((0, affiliate_engine_js_1.buildAffiliateCode)('   ', 'K7M2'), 'AFI-AFILIADO-K7M2');
});
(0, node_test_1.default)('the code has the shape the whole product agrees on', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.buildAffiliateCode)('João Macamo', 'K7M2'), 'AFI-JOAO-K7M2');
    strict_1.default.match((0, affiliate_engine_js_1.buildAffiliateCode)('João', 'K7M2'), /^AFI-[A-Z0-9]{1,8}-[A-Z0-9]{4}$/);
});
(0, node_test_1.default)('the suffix alphabet excludes every character that gets misread', () => {
    for (const confusable of ['0', 'O', '1', 'I', 'L']) {
        strict_1.default.ok(!affiliate_engine_js_1.CODE_ALPHABET.includes(confusable), `${confusable} is in the alphabet and will be misheard`);
    }
});
(0, node_test_1.default)('a suffix is drawn only from that alphabet', () => {
    let n = 0;
    const suffix = (0, affiliate_engine_js_1.generateCodeSuffix)(() => (n++ * 7) % 256, 64);
    for (const character of suffix) {
        strict_1.default.ok(affiliate_engine_js_1.CODE_ALPHABET.includes(character), `${character} is off-alphabet`);
    }
});
(0, node_test_1.default)('bytes past the last whole multiple are rejected, not folded', () => {
    // Taking modulo instead would make the first few characters likelier, which
    // is invisible in output and halves the useful key space over time.
    const limit = Math.floor(256 / affiliate_engine_js_1.CODE_ALPHABET.length) * affiliate_engine_js_1.CODE_ALPHABET.length;
    const bytes = [limit, limit + 1, 255, 0];
    let i = 0;
    const suffix = (0, affiliate_engine_js_1.generateCodeSuffix)(() => bytes[i++ % bytes.length], 1);
    strict_1.default.equal(suffix, affiliate_engine_js_1.CODE_ALPHABET[0]);
});
(0, node_test_1.default)('suffix generation gives up rather than spinning forever', () => {
    const limit = Math.floor(256 / affiliate_engine_js_1.CODE_ALPHABET.length) * affiliate_engine_js_1.CODE_ALPHABET.length;
    strict_1.default.throws(() => (0, affiliate_engine_js_1.generateCodeSuffix)(() => limit, 1), /no progress/);
});
/* ----------------------------------------------------------------- the ids */
(0, node_test_1.default)('the same pair always resolves to the same id', () => {
    strict_1.default.equal(affiliate_engine_js_1.affiliateIds.attribution('merchant-1', 'customer-1'), affiliate_engine_js_1.affiliateIds.attribution('merchant-1', 'customer-1'));
});
(0, node_test_1.default)('a different pair resolves to a different id', () => {
    strict_1.default.notEqual(affiliate_engine_js_1.affiliateIds.attribution('merchant-1', 'customer-1'), affiliate_engine_js_1.affiliateIds.attribution('merchant-2', 'customer-1'));
    strict_1.default.notEqual(affiliate_engine_js_1.affiliateIds.reward('aa_1', 'FIRST_QUALIFYING_SALE'), affiliate_engine_js_1.affiliateIds.reward('aa_1', 'CUSTOMER_RETURN'));
});
(0, node_test_1.default)('the parts cannot be smeared into each other', () => {
    // Joining on a plain separator would make ("ab","c") and ("a","bc") collide,
    // which is one customer's attribution landing on another's document.
    strict_1.default.notEqual(affiliate_engine_js_1.affiliateIds.attribution('ab', 'c'), affiliate_engine_js_1.affiliateIds.attribution('a', 'bc'));
});
(0, node_test_1.default)('an id never carries a phone number', () => {
    const id = affiliate_engine_js_1.affiliateIds.attribution('merchant-1', '258840000001');
    strict_1.default.ok(!id.includes('840000001'));
    strict_1.default.ok(!id.includes('258'));
});
(0, node_test_1.default)('the sale key ties a replay to the till it came from', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.saleIdempotencyKey)('device-9', 'local-3'), 'sale:device-9:local-3');
});
/* ------------------------------------------------------------- validation */
(0, node_test_1.default)('a good code passes', () => {
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code(), context()), { ok: true });
});
(0, node_test_1.default)('a missing code and another business are the same answer', () => {
    // Distinguishing them lets a caller enumerate other businesses' codes.
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(null, context()), {
        ok: false,
        reason: 'CODE_NOT_FOUND',
    });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ merchantId: 'merchant-2' }), context()), { ok: false, reason: 'CODE_NOT_FOUND' });
});
(0, node_test_1.default)('each check has its own reason', () => {
    const cases = [
        [{ enabled: false }, {}, 'CODE_DISABLED'],
        [{ validFrom: NOW + DAY }, {}, 'CODE_NOT_STARTED'],
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
        strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code(codeOverride), context(contextOverride)), { ok: false, reason }, `expected ${reason}`);
    }
});
(0, node_test_1.default)('the order is the contract, not an implementation detail', () => {
    // A code that is both disabled and expired must say "desativado": that is
    // the one the merchant can do something about. Reordering these silently
    // changes what a cashier is told to do.
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ enabled: false, expiresAt: NOW - 1 }), context()), { ok: false, reason: 'CODE_DISABLED' });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ expiresAt: NOW - 1, usageLimit: 1, usageCount: 9 }), context()), { ok: false, reason: 'CODE_EXPIRED' });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code(), context({
        affiliateStatus: 'INACTIVE',
        customerPhoneHash: 'hash-affiliate',
    })), { ok: false, reason: 'AFFILIATE_INACTIVE' });
});
(0, node_test_1.default)('a code expires at its instant, not after it', () => {
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ expiresAt: NOW }), context()), {
        ok: false,
        reason: 'CODE_EXPIRED',
    });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ expiresAt: NOW + 1 }), context()), {
        ok: true,
    });
});
(0, node_test_1.default)('validity starts at its instant', () => {
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ validFrom: NOW }), context()), { ok: true });
});
(0, node_test_1.default)('an unlimited code is not a code with a zero limit', () => {
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ usageLimit: null, usageCount: 9999 }), context()), { ok: true });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ usageLimit: 0, usageCount: 0 }), context()), { ok: false, reason: 'CODE_USAGE_LIMIT_REACHED' });
});
(0, node_test_1.default)('a rejected attribution leaves the customer available', () => {
    // It is a record that somebody tried, not a claim on the customer.
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code(), context({ existingAttributionStatus: 'REJECTED' })), { ok: true });
    for (const status of ['CONFIRMED', 'CANCELLED']) {
        strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code(), context({ existingAttributionStatus: status })), { ok: false, reason: 'CUSTOMER_ALREADY_REFERRED' });
    }
});
(0, node_test_1.default)('an existing customer passes when the code allows it', () => {
    // firstVisitOnly = false gives the benefit but earns no acquisition; that
    // second half is the transaction's job, not this function's.
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ firstVisitOnly: false }), context({ customerIsNew: false })), { ok: true });
});
(0, node_test_1.default)('an unknown phone on both sides is not a self-referral', () => {
    // Two empty hashes are two unknowns, not the same person.
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code(), context({ affiliatePhoneHash: '', customerPhoneHash: '' })), { ok: true });
});
(0, node_test_1.default)('every reason a merchant can hit has Portuguese words', () => {
    for (const reason of affiliate_contracts_js_1.REFERRAL_REASON) {
        const message = affiliate_contracts_js_1.REFERRAL_REASON_MESSAGE[reason];
        strict_1.default.ok(message && message.length > 0, `${reason} has no message`);
        strict_1.default.notEqual(message, reason, `${reason} reaches the till untranslated`);
    }
});
/* --------------------------------------------------------- the preview gap */
(0, node_test_1.default)('a preview with no sale yet still checks the code itself', () => {
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ benefitType: 'FIXED_AMOUNT', benefitValue: 50 }), context({ saleAmount: null })), { ok: true });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(code({ benefitType: 'PERCENTAGE', benefitValue: 80 }), context({ saleAmount: null })), { ok: false, reason: 'BENEFIT_INVALID' });
});
(0, node_test_1.default)('a fixed discount larger than the bill fails at commit, not at preview', () => {
    const big = code({ benefitType: 'FIXED_AMOUNT', benefitValue: 500 });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(big, context({ saleAmount: null })), { ok: true });
    strict_1.default.deepEqual((0, affiliate_engine_js_1.validateReferral)(big, context({ saleAmount: 100 })), {
        ok: false,
        reason: 'BENEFIT_INVALID',
    });
});
(0, node_test_1.default)('the percentage range is the configured one', () => {
    for (const value of [affiliate_contracts_js_1.PERCENTAGE_RANGE.min, 25, affiliate_contracts_js_1.PERCENTAGE_RANGE.max]) {
        strict_1.default.ok((0, affiliate_engine_js_1.isBenefitValid)({ benefitType: 'PERCENTAGE', benefitValue: value }, 100));
    }
    for (const value of [0, affiliate_contracts_js_1.PERCENTAGE_RANGE.min - 1, affiliate_contracts_js_1.PERCENTAGE_RANGE.max + 1, 100]) {
        strict_1.default.ok(!(0, affiliate_engine_js_1.isBenefitValid)({ benefitType: 'PERCENTAGE', benefitValue: value }, 100));
    }
});
(0, node_test_1.default)('a points benefit must be a whole number of points', () => {
    strict_1.default.ok((0, affiliate_engine_js_1.isBenefitValid)({ benefitType: 'POINTS', benefitValue: 50 }, 100));
    strict_1.default.ok(!(0, affiliate_engine_js_1.isBenefitValid)({ benefitType: 'POINTS', benefitValue: 2.5 }, 100));
    strict_1.default.ok(!(0, affiliate_engine_js_1.isBenefitValid)({ benefitType: 'POINTS', benefitValue: -5 }, 100));
});
/* ------------------------------------------------------------- eligibility */
(0, node_test_1.default)('a new customer is new on every clause at once', () => {
    const base = {
        hasPreviousCompletedSale: false,
        hasNonRejectedAttribution: false,
        phoneAlreadyKnown: false,
        isAffiliate: false,
        isTestAccount: false,
        isBlocked: false,
    };
    strict_1.default.equal((0, affiliate_engine_js_1.isNewCustomer)(base), true);
    for (const key of Object.keys(base)) {
        strict_1.default.equal((0, affiliate_engine_js_1.isNewCustomer)({ ...base, [key]: true }), false, `${key} should disqualify on its own`);
    }
});
(0, node_test_1.default)('a sale qualifies only when nothing is wrong with it', () => {
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
    strict_1.default.equal((0, affiliate_engine_js_1.isQualifyingSale)(base), true);
    strict_1.default.equal((0, affiliate_engine_js_1.isQualifyingSale)({ ...base, amount: 0 }), false);
    strict_1.default.equal((0, affiliate_engine_js_1.isQualifyingSale)({ ...base, amount: -1 }), false);
    for (const key of [
        'belongsToMerchant',
        'hasCustomer',
        'isCompleted',
        'meetsMinimumAmount',
    ]) {
        strict_1.default.equal((0, affiliate_engine_js_1.isQualifyingSale)({ ...base, [key]: false }), false, key);
    }
    for (const key of ['isCancelled', 'isRefunded', 'isReversed', 'isDuplicate']) {
        strict_1.default.equal((0, affiliate_engine_js_1.isQualifyingSale)({ ...base, [key]: true }), false, key);
    }
});
/* ---------------------------------------------------------------- benefit */
(0, node_test_1.default)('a percentage is taken in centavos and rounded down', () => {
    // 10% of 99.99 is 9.999. Rounding up would hand over a centavo the code does
    // not authorise, every time, on every such sale.
    const result = (0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'PERCENTAGE', benefitValue: 10 }, 99.99);
    strict_1.default.equal(result.discountAmount, 9.99);
    strict_1.default.equal(result.netAmount, 90);
});
(0, node_test_1.default)('the net and the discount always add back to the gross', () => {
    for (const gross of [0.01, 1, 33.33, 99.99, 1234.56, 7.77]) {
        for (const percent of [1, 7, 13, 33, 50]) {
            const result = (0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'PERCENTAGE', benefitValue: percent }, gross);
            strict_1.default.equal(Math.round((result.netAmount + result.discountAmount) * 100), Math.round(gross * 100), `${percent}% of ${gross} does not add back`);
        }
    }
});
(0, node_test_1.default)('a discount never exceeds the bill', () => {
    const result = (0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'FIXED_AMOUNT', benefitValue: 500 }, 100);
    strict_1.default.equal(result.discountAmount, 100);
    strict_1.default.equal(result.netAmount, 0);
});
(0, node_test_1.default)('a points benefit leaves the amount alone', () => {
    const result = (0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'POINTS', benefitValue: 150 }, 250);
    strict_1.default.equal(result.netAmount, 250);
    strict_1.default.equal(result.discountAmount, 0);
    strict_1.default.equal(result.pointsAwarded, 150);
});
(0, node_test_1.default)('the benefit says what it is in words the customer can be told', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'FIXED_AMOUNT', benefitValue: 50 }, 250).displayText, '50 MT de desconto');
    strict_1.default.equal((0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'POINTS', benefitValue: 150 }, 250).displayText, '150 pontos extra');
    strict_1.default.match((0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'PERCENTAGE', benefitValue: 10 }, 250).displayText, /^10% de desconto \(25 MT\)$/);
});
(0, node_test_1.default)('a zero sale produces a zero benefit rather than a negative one', () => {
    const result = (0, affiliate_engine_js_1.calculateBenefit)({ benefitType: 'PERCENTAGE', benefitValue: 50 }, 0);
    strict_1.default.equal(result.discountAmount, 0);
    strict_1.default.equal(result.netAmount, 0);
});
/* ---------------------------------------------------------------- rewards */
(0, node_test_1.default)('the approval setting decides where a new reward lands', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.planFirstSaleReward)(config())?.status, 'PENDING');
    strict_1.default.equal((0, affiliate_engine_js_1.planFirstSaleReward)(config({ rewardApprovalRequired: false }))?.status, 'APPROVED');
});
(0, node_test_1.default)('a reward of zero points is not written at all', () => {
    // It would sit in the approvals queue meaning nothing.
    strict_1.default.equal((0, affiliate_engine_js_1.planFirstSaleReward)(config({ firstSaleRewardPoints: 0 })), null);
});
(0, node_test_1.default)('the return reward is off unless the business turned it on', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.planReturnReward)(config(), NOW, NOW + DAY), null);
    strict_1.default.equal((0, affiliate_engine_js_1.planReturnReward)(config({ returnRewardEnabled: true, returnRewardPoints: 50 }), NOW, NOW + DAY)?.value, 50);
});
(0, node_test_1.default)('the return window is counted from the first sale', () => {
    const settings = config({ returnRewardEnabled: true, returnRewardPoints: 50 });
    strict_1.default.ok((0, affiliate_engine_js_1.planReturnReward)(settings, NOW, NOW + 30 * DAY));
    strict_1.default.equal((0, affiliate_engine_js_1.planReturnReward)(settings, NOW, NOW + 30 * DAY + 1), null);
});
(0, node_test_1.default)('a return that predates the first sale is not a return', () => {
    strict_1.default.equal((0, affiliate_engine_js_1.isWithinReturnWindow)(config(), NOW, NOW - DAY), false);
});
(0, node_test_1.default)('a cancellation takes back what it can and flags what it cannot', () => {
    const { cancellable, needsManualReview } = (0, affiliate_engine_js_1.rewardsAffectedByCancellation)([
        { id: 'r1', status: 'PENDING' },
        { id: 'r2', status: 'APPROVED' },
        { id: 'r3', status: 'PAID' },
        { id: 'r4', status: 'CANCELLED' },
    ]);
    strict_1.default.deepEqual(cancellable, ['r1', 'r2']);
    // Points already handed over are not undone by a status change.
    strict_1.default.deepEqual(needsManualReview, ['r3']);
});
/* ---------------------------------------------------------------- metrics */
(0, node_test_1.default)('conversion is confirmed acquisitions over attempts', () => {
    const metrics = (0, affiliate_engine_js_1.summarizeAffiliateMetrics)({
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
    strict_1.default.equal(metrics.conversionRate, 0.25);
});
(0, node_test_1.default)('no attempts is zero, not NaN', () => {
    // A division by zero reaching a screen prints "NaN%" to a business owner.
    const metrics = (0, affiliate_engine_js_1.summarizeAffiliateMetrics)({
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
    strict_1.default.equal(metrics.conversionRate, 0);
    strict_1.default.ok(Number.isFinite(metrics.conversionRate));
});
(0, node_test_1.default)('metrics carry no way to identify a person', () => {
    const metrics = (0, affiliate_engine_js_1.summarizeAffiliateMetrics)({
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
        strict_1.default.ok(typeof value === 'number' || value === null, 'a metrics field became something other than a count');
    }
});
