"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.affiliateIds = exports.CODE_NAME_MAX = exports.CODE_SUFFIX_LENGTH = exports.CODE_ALPHABET = void 0;
exports.normalizeAffiliateCode = normalizeAffiliateCode;
exports.foldCodeName = foldCodeName;
exports.buildAffiliateCode = buildAffiliateCode;
exports.generateCodeSuffix = generateCodeSuffix;
exports.saleIdempotencyKey = saleIdempotencyKey;
exports.validateReferral = validateReferral;
exports.isBenefitValid = isBenefitValid;
exports.isNewCustomer = isNewCustomer;
exports.isQualifyingSale = isQualifyingSale;
exports.calculateBenefit = calculateBenefit;
exports.planFirstSaleReward = planFirstSaleReward;
exports.planReturnReward = planReturnReward;
exports.isWithinReturnWindow = isWithinReturnWindow;
exports.rewardsAffectedByCancellation = rewardsAffectedByCancellation;
exports.summarizeAffiliateMetrics = summarizeAffiliateMetrics;
const crypto_1 = require("crypto");
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
/**
 * The referral engine, as functions with no I/O.
 *
 * Every decision the feature makes lives here: whether a code may be used, what
 * it is worth, what the resulting ids are. Reading and writing happen in the
 * route and transaction layers, which call into this file and never re-decide
 * anything themselves.
 *
 * That split is what makes the commit path trustworthy. §5.5 of the prompt
 * requires the sale transaction to re-run every check against the real sale
 * rather than trust what the preview said — and it can only be the *same*
 * check if the check is a function both sides call.
 */
/* ------------------------------------------------------------------- codes */
/**
 * The suffix alphabet, missing 0, O, 1, I and L on purpose.
 *
 * Codes are read aloud across a counter and typed by someone in a hurry. The
 * pairs that get confused are left out rather than corrected afterwards.
 */
exports.CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
exports.CODE_SUFFIX_LENGTH = 4;
exports.CODE_NAME_MAX = 8;
/**
 * How a typed code is matched.
 *
 * Outer spaces only: a code is one token, so collapsing inner whitespace would
 * quietly accept something that is not the code. Upper-cased because the stored
 * form is upper-case, and lookup is by exact key on the normalised value.
 */
function normalizeAffiliateCode(raw) {
    return raw.trim().toUpperCase();
}
/**
 * The name segment: ASCII-folded, letters and digits only, capped.
 *
 * "João" becomes JOAO rather than JO?O — a code nobody can dictate over the
 * phone is a code nobody uses.
 */
function foldCodeName(rawName) {
    const first = rawName.trim().split(/\s+/)[0] ?? '';
    const folded = first
        .normalize('NFD')
        // Strip combining marks left behind by the decomposition.
        .replace(/[̀-ͯ]/g, '')
        .toUpperCase()
        .replace(/[^A-Z0-9]/g, '');
    return folded.slice(0, exports.CODE_NAME_MAX);
}
/**
 * Builds `AFI-{NAME}-{XXXX}`.
 *
 * A name that folds away to nothing — punctuation, or a script with no ASCII
 * equivalent — still has to produce a usable code, so it falls back to a fixed
 * segment rather than yielding `AFI--XXXX`.
 */
function buildAffiliateCode(rawName, suffix) {
    const name = foldCodeName(rawName) || 'AFILIADO';
    return `AFI-${name}-${suffix}`;
}
/**
 * Four characters from [CODE_ALPHABET].
 *
 * `randomByte` is injected so a test can pin the output; production passes a
 * CSPRNG. Bytes are rejected past the largest whole multiple of the alphabet
 * size rather than taken modulo, which would make the first few characters
 * measurably more likely.
 */
function generateCodeSuffix(randomByte, length = exports.CODE_SUFFIX_LENGTH) {
    const limit = Math.floor(256 / exports.CODE_ALPHABET.length) * exports.CODE_ALPHABET.length;
    let out = '';
    let guard = 0;
    while (out.length < length) {
        if (guard++ > 1000)
            throw new Error('Code suffix generation made no progress');
        const byte = randomByte() & 0xff;
        if (byte >= limit)
            continue;
        out += exports.CODE_ALPHABET[byte % exports.CODE_ALPHABET.length];
    }
    return out;
}
/* --------------------------------------------------------------------- ids */
function digest(parts) {
    return (0, crypto_1.createHash)('sha256').update(parts.join('')).digest('hex').slice(0, 40);
}
/**
 * Deterministic ids, which is how uniqueness is enforced.
 *
 * Firestore has no partial unique index, so "one active attribution per
 * customer" has to be a document that can only exist once. Deriving the id from
 * the pair turns a uniqueness constraint into a primary key, and a concurrent
 * duplicate becomes a lost create rather than a second row.
 *
 * None of these take a phone number. An id is stored, logged and read by people
 * who have no business learning a customer's number from it.
 */
exports.affiliateIds = {
    link: (affiliateId, merchantId) => `am_${digest([affiliateId, merchantId])}`,
    /** One code per affiliate–merchant pair in the MVP, so the same shape. */
    code: (affiliateId, merchantId) => `ac_${digest([affiliateId, merchantId])}`,
    /** One live attribution per customer per business. */
    attribution: (merchantId, customerId) => `aa_${digest([merchantId, customerId])}`,
    /** One reward per attribution per type. */
    reward: (attributionId, type) => `ar_${digest([attributionId, type])}`,
    /** The global lookup key, which is the normalised code itself. */
    lookup: (code) => normalizeAffiliateCode(code),
};
/**
 * The key that makes a sale commit replay-safe.
 *
 * Derived from the till and the sale's local id, so a retry after a dropped
 * response resolves to the work already done instead of a second sale.
 */
function saleIdempotencyKey(deviceId, localSaleId) {
    return `sale:${deviceId}:${localSaleId}`;
}
/**
 * §5.1, in order, returning the first failure.
 *
 * The order is not arbitrary and is not an implementation detail: a disabled
 * code that is also expired must say "desativado", because that is the one the
 * merchant can act on. Reordering these changes what a cashier is told.
 *
 * Called by both the preview and the commit. The preview is advisory — nothing
 * is reserved by it — so the commit runs this again inside the transaction
 * against the real sale.
 */
function validateReferral(code, context) {
    const fail = (reason) => ({ ok: false, reason });
    // A code belonging to another business is indistinguishable from one that
    // does not exist. Anything else lets a caller probe for other businesses.
    if (code === null || code.merchantId !== context.merchantId) {
        return fail('CODE_NOT_FOUND');
    }
    if (!code.enabled)
        return fail('CODE_DISABLED');
    if (context.now < code.validFrom)
        return fail('CODE_NOT_STARTED');
    if (context.now >= code.expiresAt)
        return fail('CODE_EXPIRED');
    if (code.usageLimit !== null && code.usageCount >= code.usageLimit) {
        return fail('CODE_USAGE_LIMIT_REACHED');
    }
    if (context.affiliateStatus !== 'ACTIVE' || context.linkStatus !== 'ACTIVE') {
        return fail('AFFILIATE_INACTIVE');
    }
    if (context.affiliatePhoneHash !== '' &&
        context.affiliatePhoneHash === context.customerPhoneHash) {
        return fail('SELF_REFERRAL_NOT_ALLOWED');
    }
    if (code.firstVisitOnly && !context.customerIsNew) {
        return fail('CUSTOMER_NOT_ELIGIBLE');
    }
    // A rejected attribution is not a claim on the customer; anything else is.
    if (context.existingAttributionStatus !== null &&
        context.existingAttributionStatus !== 'REJECTED') {
        return fail('CUSTOMER_ALREADY_REFERRED');
    }
    if (!isBenefitValid(code, context.saleAmount))
        return fail('BENEFIT_INVALID');
    return { ok: true };
}
/**
 * §5.4. At preview time the sale does not exist yet, so a null amount checks
 * only what can be checked without it — the code's own shape.
 */
function isBenefitValid(code, saleAmount) {
    if (!Number.isFinite(code.benefitValue) || code.benefitValue <= 0)
        return false;
    switch (code.benefitType) {
        case 'PERCENTAGE':
            return (code.benefitValue >= affiliate_contracts_js_1.PERCENTAGE_RANGE.min &&
                code.benefitValue <= affiliate_contracts_js_1.PERCENTAGE_RANGE.max);
        case 'FIXED_AMOUNT':
            if (saleAmount === null)
                return true;
            return saleAmount > 0 && code.benefitValue <= saleAmount;
        case 'POINTS':
            return Number.isInteger(code.benefitValue);
    }
}
/** §5.2. Every clause disqualifies; none of them is a warning. */
function isNewCustomer(input) {
    return (!input.hasPreviousCompletedSale &&
        !input.hasNonRejectedAttribution &&
        !input.phoneAlreadyKnown &&
        !input.isAffiliate &&
        !input.isTestAccount &&
        !input.isBlocked);
}
/** §5.3. */
function isQualifyingSale(input) {
    return (input.belongsToMerchant &&
        input.hasCustomer &&
        input.amount > 0 &&
        input.isCompleted &&
        !input.isCancelled &&
        !input.isRefunded &&
        !input.isReversed &&
        !input.isDuplicate &&
        input.meetsMinimumAmount);
}
/**
 * Computed on the server and never sent by the client, which posts only a code.
 *
 * Percentages are worked in centavos and rounded down, so a discount can never
 * come out a centavo larger than the percentage allows. The floor is also what
 * keeps `netAmount` from drifting below zero on a rounding edge.
 *
 * `amount` keeps meaning what it has always meant — what the customer actually
 * paid — so loyalty points are earned on `netAmount` and nothing about the
 * existing sale path changes for a sale with no code.
 */
function calculateBenefit(code, grossAmount) {
    const gross = Math.max(0, grossAmount);
    if (code.benefitType === 'POINTS') {
        const points = Math.floor(code.benefitValue);
        return {
            type: 'POINTS',
            value: points,
            discountAmount: 0,
            pointsAwarded: points,
            netAmount: gross,
            displayText: `${formatPoints(points)} pontos extra`,
        };
    }
    const grossCents = Math.round(gross * 100);
    const rawCents = code.benefitType === 'PERCENTAGE'
        ? Math.floor((grossCents * code.benefitValue) / 100)
        : Math.round(code.benefitValue * 100);
    // Never more than the sale: a discount larger than the bill would turn into
    // money owed to the customer, which this product does not do.
    const discountCents = Math.min(Math.max(0, rawCents), grossCents);
    const discountAmount = discountCents / 100;
    return {
        type: code.benefitType,
        value: code.benefitValue,
        discountAmount,
        pointsAwarded: 0,
        netAmount: (grossCents - discountCents) / 100,
        displayText: code.benefitType === 'PERCENTAGE'
            ? `${code.benefitValue}% de desconto (${formatMoney(discountAmount)})`
            : `${formatMoney(discountAmount)} de desconto`,
    };
}
function formatMoney(value) {
    const whole = Number.isInteger(value) ? value.toFixed(0) : value.toFixed(2);
    return `${whole} MT`;
}
function formatPoints(value) {
    return value.toLocaleString('pt-PT');
}
/**
 * The reward a confirmed acquisition earns.
 *
 * Returns null when the business has affiliates on but has left the reward at
 * zero — a reward of nothing is not a reward, and writing one would put a row
 * in the approvals queue that means nothing.
 */
function planFirstSaleReward(config) {
    if (config.firstSaleRewardPoints <= 0)
        return null;
    return {
        type: 'FIRST_QUALIFYING_SALE',
        value: Math.floor(config.firstSaleRewardPoints),
        valueType: 'POINTS',
        status: config.rewardApprovalRequired ? 'PENDING' : 'APPROVED',
    };
}
/**
 * §5.6. A return reward exists only inside the window, counted from the first
 * qualifying sale — not from the attribution, which can be written later.
 */
function planReturnReward(config, firstSaleAt, returnSaleAt) {
    if (!config.returnRewardEnabled)
        return null;
    if (config.returnRewardPoints <= 0)
        return null;
    if (!isWithinReturnWindow(config, firstSaleAt, returnSaleAt))
        return null;
    return {
        type: 'CUSTOMER_RETURN',
        value: Math.floor(config.returnRewardPoints),
        valueType: 'POINTS',
        status: config.rewardApprovalRequired ? 'PENDING' : 'APPROVED',
    };
}
const DAY_MS = 24 * 60 * 60 * 1000;
function isWithinReturnWindow(config, firstSaleAt, returnSaleAt) {
    if (returnSaleAt < firstSaleAt)
        return false;
    return returnSaleAt - firstSaleAt <= config.returnWindowDays * DAY_MS;
}
/**
 * Which rewards a cancellation may take back.
 *
 * `PAID` is deliberately excluded: money or points already handed over are not
 * undone by a status change, so those surface for a person to deal with. The
 * caller is expected to raise them rather than ignore the list.
 */
function rewardsAffectedByCancellation(rewards) {
    const cancellable = [];
    const needsManualReview = [];
    for (const reward of rewards) {
        const status = (reward.status ?? '').toUpperCase();
        if (status === 'PENDING' || status === 'APPROVED')
            cancellable.push(reward.id);
        else if (status === 'PAID')
            needsManualReview.push(reward.id);
    }
    return { cancellable, needsManualReview };
}
/** §D14. Carries no phone, name or customer id: this payload is analytics. */
function summarizeAffiliateMetrics(input) {
    const attempts = Math.max(0, input.uniqueValidationAttempts);
    return {
        ...input,
        conversionRate: attempts === 0 ? 0 : Math.max(0, input.confirmedAttributions) / attempts,
    };
}
