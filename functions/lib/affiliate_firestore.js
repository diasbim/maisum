"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.CODE_ALLOCATION_ATTEMPTS = exports.AffiliateCodeExhaustedError = exports.affiliateRefs = void 0;
exports.allocateAffiliateCode = allocateAffiliateCode;
exports.claimAffiliateCode = claimAffiliateCode;
exports.resolveCodeLookup = resolveCodeLookup;
const admin = __importStar(require("firebase-admin"));
const affiliate_engine_js_1 = require("./affiliate_engine.js");
/**
 * Where affiliate data lives, and the one write that cannot be expressed as a
 * plain set: claiming a code.
 *
 * Everything else the feature stores is keyed by a deterministic id, so
 * uniqueness is a property of the key and a concurrent duplicate is a lost
 * create. A code is the exception — it has to be unique across every business
 * and it is partly random, so it cannot be derived from what it belongs to.
 * That is what `allocateAffiliateCode` is for.
 */
const db = () => admin.firestore();
exports.affiliateRefs = {
    /** Global identity, one per normalised phone. */
    affiliate: (affiliateId) => db().collection('affiliates').doc(affiliateId),
    /**
     * The document that makes a code unique everywhere.
     *
     * Keyed by the normalised code itself, so "is this taken?" is a `get` on a
     * known id rather than a query — which means it can be read inside a
     * transaction, and a query cannot.
     */
    codeLookup: (code) => db().collection('affiliate_code_lookup').doc((0, affiliate_engine_js_1.normalizeAffiliateCode)(code)),
    business: (merchantId) => db().collection('businesses').doc(merchantId),
    link: (merchantId, linkId) => db()
        .collection('businesses')
        .doc(merchantId)
        .collection('affiliate_merchants')
        .doc(linkId),
    code: (merchantId, codeId) => db()
        .collection('businesses')
        .doc(merchantId)
        .collection('affiliate_codes')
        .doc(codeId),
    attribution: (merchantId, attributionId) => db()
        .collection('businesses')
        .doc(merchantId)
        .collection('affiliate_attributions')
        .doc(attributionId),
    reward: (merchantId, rewardId) => db()
        .collection('businesses')
        .doc(merchantId)
        .collection('affiliate_rewards')
        .doc(rewardId),
    events: (merchantId) => db().collection('businesses').doc(merchantId).collection('affiliate_events'),
    fraudSignals: (merchantId) => db()
        .collection('businesses')
        .doc(merchantId)
        .collection('affiliate_fraud_signals'),
    rateLimit: (merchantId, bucketId) => db()
        .collection('businesses')
        .doc(merchantId)
        .collection('affiliate_rate_limits')
        .doc(bucketId),
};
/* ------------------------------------------------------- claiming a code */
class AffiliateCodeExhaustedError extends Error {
    constructor(attempts) {
        super(`Could not find a free affiliate code in ${attempts} attempts`);
        this.name = 'AffiliateCodeExhaustedError';
    }
}
exports.AffiliateCodeExhaustedError = AffiliateCodeExhaustedError;
/**
 * How many suffixes to try before giving up.
 *
 * Four characters over a 31-character alphabet is about 923 000 codes per name,
 * so a collision is already unlikely and two in a row vanishingly so. The cap
 * exists for the case this number does not cover: a name so common that its
 * space really is filling up. Failing loudly then is right — silently widening
 * the code would produce a format the rest of the product does not expect.
 */
exports.CODE_ALLOCATION_ATTEMPTS = 8;
/**
 * Finds a code nobody holds.
 *
 * `isTaken` is injected rather than reaching for Firestore directly, because
 * the caller decides what "taken" means in its context: inside a transaction it
 * is a transactional read, and a transactional read is the only kind that makes
 * the claim safe against a second request picking the same suffix at the same
 * moment. A version of this that did its own `get` would look identical and be
 * wrong under concurrency.
 */
async function allocateAffiliateCode(input) {
    const attempts = input.attempts ?? exports.CODE_ALLOCATION_ATTEMPTS;
    const randomByte = input.randomByte ?? (() => admin.firestore.Timestamp.now().nanoseconds & 0xff);
    for (let attempt = 1; attempt <= attempts; attempt++) {
        const candidate = (0, affiliate_engine_js_1.buildAffiliateCode)(input.name, (0, affiliate_engine_js_1.generateCodeSuffix)(randomByte));
        if (!(await input.isTaken(candidate))) {
            return { code: candidate, attempts: attempt };
        }
    }
    throw new AffiliateCodeExhaustedError(attempts);
}
/**
 * Claims a code for an affiliate at a business, in one transaction.
 *
 * The lookup document is the lock. Creating it and the code row together means
 * two requests that pick the same suffix cannot both succeed: the second one's
 * read sees the first one's write and the transaction retries, which is exactly
 * what the retry loop above is there to absorb.
 */
async function claimAffiliateCode(input) {
    return db().runTransaction(async (transaction) => {
        const allocation = await allocateAffiliateCode({
            name: input.name,
            randomByte: input.randomByte,
            isTaken: async (candidate) => {
                const snapshot = await transaction.get(exports.affiliateRefs.codeLookup(candidate));
                return snapshot.exists;
            },
        });
        const now = Date.now();
        transaction.set(exports.affiliateRefs.codeLookup(allocation.code), {
            code: (0, affiliate_engine_js_1.normalizeAffiliateCode)(allocation.code),
            merchant_id: input.merchantId,
            affiliate_id: input.affiliateId,
            code_id: input.codeId,
            created_at: now,
        });
        transaction.set(exports.affiliateRefs.code(input.merchantId, input.codeId), { ...input.codeFields, code: allocation.code, updated_at: now }, { merge: true });
        return allocation;
    });
}
/**
 * Resolves a typed code to the business that owns it.
 *
 * Returns null for both "no such code" and a malformed one, so the caller has
 * a single not-found path and cannot accidentally answer differently for a
 * code that exists at another business.
 */
async function resolveCodeLookup(rawCode) {
    const normalized = (0, affiliate_engine_js_1.normalizeAffiliateCode)(rawCode);
    if (normalized === '')
        return null;
    const snapshot = await exports.affiliateRefs.codeLookup(normalized).get();
    if (!snapshot.exists)
        return null;
    const data = (snapshot.data() ?? {});
    const merchantId = typeof data.merchant_id === 'string' ? data.merchant_id : '';
    const affiliateId = typeof data.affiliate_id === 'string' ? data.affiliate_id : '';
    const codeId = typeof data.code_id === 'string' ? data.code_id : '';
    if (merchantId === '' || affiliateId === '' || codeId === '')
        return null;
    return { merchantId, affiliateId, codeId };
}
