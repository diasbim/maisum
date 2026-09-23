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
exports.AFFILIATE_SCAN_CAP = void 0;
exports.affiliateConfigFrom = affiliateConfigFrom;
exports.loadAffiliateConfig = loadAffiliateConfig;
exports.merchantExists = merchantExists;
exports.appendAffiliateEvent = appendAffiliateEvent;
exports.consumeRateLimit = consumeRateLimit;
exports.createAffiliateForMerchant = createAffiliateForMerchant;
exports.createCodeForLinkedAffiliate = createCodeForLinkedAffiliate;
exports.getMerchantAffiliate = getMerchantAffiliate;
exports.listMerchantAffiliates = listMerchantAffiliates;
exports.listMerchantCodes = listMerchantCodes;
exports.getMerchantCode = getMerchantCode;
exports.listAttributions = listAttributions;
exports.getAttribution = getAttribution;
exports.listRewards = listRewards;
exports.updateCode = updateCode;
exports.setCodeStatus = setCodeStatus;
exports.setLinkStatus = setLinkStatus;
exports.updateAffiliateName = updateAffiliateName;
exports.updateMerchantAffiliateName = updateMerchantAffiliateName;
exports.setAffiliateStatus = setAffiliateStatus;
exports.transitionReward = transitionReward;
exports.validateReferralCode = validateReferralCode;
exports.loadCustomerHistory = loadCustomerHistory;
exports.affiliateMetrics = affiliateMetrics;
exports.listAllAffiliates = listAllAffiliates;
exports.getAffiliate = getAffiliate;
exports.createGlobalAffiliate = createGlobalAffiliate;
exports.linkAffiliateToMerchant = linkAffiliateToMerchant;
exports.unlinkAffiliateFromMerchant = unlinkAffiliateFromMerchant;
const crypto_1 = require("crypto");
const admin = __importStar(require("firebase-admin"));
const affiliate_api_contracts_js_1 = require("./affiliate_api_contracts.js");
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_engine_js_1 = require("./affiliate_engine.js");
const affiliate_firestore_js_1 = require("./affiliate_firestore.js");
const affiliate_rate_limit_js_1 = require("./affiliate_rate_limit.js");
const merchant_records_js_1 = require("./merchant_records.js");
/**
 * Everything the referral API stores and reads, in one module.
 *
 * The routes above this file authenticate, validate and translate; they do not
 * know a collection name. That separation is what keeps merchant isolation
 * checkable: every read here is either a document at a path that already
 * contains the merchant id, or a query whose first filter is
 * `merchant_id == merchantId`. There is no function in this file that can be
 * called without saying which business is asking.
 *
 * Three things are transactional, and only three, because only three can be
 * raced into an inconsistent state: claiming an identity and its link,
 * claiming a code, and moving a reward between statuses. Everything else is a
 * single document write whose id already encodes its uniqueness.
 *
 * `affiliate_events` is append-only. Nothing here updates or deletes one, and
 * every write goes through `appendAffiliateEvent`, which uses `create` so that
 * an accidental id collision fails rather than overwrites history.
 */
const db = () => admin.firestore();
/**
 * How many documents one list read will pull.
 *
 * Lower than `MERCHANT_SCAN_CAP` because these collections are small by
 * nature — a business has tens of affiliates, not thousands — and because
 * metrics read three of them at once.
 */
exports.AFFILIATE_SCAN_CAP = 500;
function rowString(row, ...keys) {
    for (const key of keys) {
        const value = row[key];
        if (typeof value === 'string' && value.trim() !== '')
            return value.trim();
    }
    return null;
}
/* ------------------------------------------------------------------ config */
/** Per-business affiliate settings, defaulted the way the plan fixes them. */
function affiliateConfigFrom(businessData) {
    const raw = businessData.affiliate_config != null &&
        typeof businessData.affiliate_config === 'object'
        ? businessData.affiliate_config
        : {};
    const number = (key, fallback) => {
        const value = raw[key];
        return typeof value === 'number' && Number.isFinite(value) && value >= 0
            ? Math.floor(value)
            : fallback;
    };
    const flag = (key, fallback) => typeof raw[key] === 'boolean' ? raw[key] : fallback;
    return {
        enabled: flag('enabled', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.enabled),
        firstSaleRewardPoints: number('first_sale_reward_points', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.firstSaleRewardPoints),
        returnRewardEnabled: flag('return_reward_enabled', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.returnRewardEnabled),
        returnRewardPoints: number('return_reward_points', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.returnRewardPoints),
        returnWindowDays: number('return_window_days', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.returnWindowDays),
        rewardApprovalRequired: flag('reward_approval_required', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.rewardApprovalRequired),
        notificationsEnabled: flag('notifications_enabled', affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG.notificationsEnabled),
    };
}
async function loadAffiliateConfig(merchantId) {
    const snapshot = await affiliate_firestore_js_1.affiliateRefs.business(merchantId).get();
    return affiliateConfigFrom((snapshot.data() ?? {}));
}
async function merchantExists(merchantId) {
    const snapshot = await affiliate_firestore_js_1.affiliateRefs.business(merchantId).get();
    return snapshot.exists;
}
async function appendAffiliateEvent(merchantId, event) {
    const ref = affiliate_firestore_js_1.affiliateRefs.events(merchantId).doc();
    const now = Date.now();
    await ref.create({
        id: ref.id,
        merchant_id: merchantId,
        affiliate_id: event.affiliateId,
        customer_id: event.customerId ?? null,
        sale_id: event.saleId ?? null,
        event_type: event.eventType,
        dedupe_key: event.dedupeKey ?? null,
        metadata: event.metadata ?? {},
        created_at: now,
    });
    return ref.id;
}
/* -------------------------------------------------------------- rate limits */
/**
 * Spends one unit of a caller's budget, or refuses.
 *
 * The transaction is what makes this hold across instances: two concurrent
 * requests read the same count, and the second one's commit is retried against
 * the first one's write rather than overwriting it.
 */
async function consumeRateLimit(input) {
    const windowStart = (0, affiliate_rate_limit_js_1.windowStartFor)(input.now, input.policy);
    const ref = affiliate_firestore_js_1.affiliateRefs.rateLimit(input.merchantId, (0, affiliate_rate_limit_js_1.rateLimitBucketId)({
        merchantId: input.merchantId,
        actorId: input.actorId,
        action: input.action,
        windowStart,
    }));
    return db().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const data = (snapshot.data() ?? {});
        const existing = snapshot.exists
            ? {
                windowStart: typeof data.window_start === 'number' ? data.window_start : windowStart,
                count: typeof data.count === 'number' ? data.count : 0,
            }
            : null;
        const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(existing, input.policy, input.now);
        transaction.set(ref, {
            window_start: decision.bucket.windowStart,
            count: decision.bucket.count,
            action: input.action,
            // A bucket is never read again once its window passes; the field exists
            // so a TTL policy can sweep them instead of a cleanup job.
            expires_at: decision.bucket.windowStart + input.policy.windowMs * 2,
            updated_at: input.now,
        });
        return decision;
    });
}
/**
 * Creates or reuses the global identity, links it, and gives it its code.
 *
 * The identity id is derived from the normalised phone by the caller, using
 * the same HMAC the canonical customer identity uses. That is what makes
 * "one affiliate per phone" a property of the key rather than of a query: two
 * businesses adding the same person at the same moment both resolve to the
 * same document, and the transaction decides which of them created it.
 *
 * The phone itself is stored once, on the global identity, because a WhatsApp
 * message has to reach somebody. It is never part of an id, an event, a log
 * line or an audit detail.
 */
async function createAffiliateForMerchant(input) {
    const linkId = affiliate_engine_js_1.affiliateIds.link(input.affiliateId, input.merchantId);
    const codeId = affiliate_engine_js_1.affiliateIds.code(input.affiliateId, input.merchantId);
    const claimed = await db().runTransaction(async (transaction) => {
        const [affiliateSnapshot, linkSnapshot] = await Promise.all([
            transaction.get(affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId)),
            transaction.get(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId)),
        ]);
        if (linkSnapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'affiliate_already_linked');
        const existing = (affiliateSnapshot.data() ?? {});
        if (affiliateSnapshot.exists &&
            String(existing.status ?? '').toUpperCase() === 'SUSPENDED') {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'affiliate_suspended');
        }
        const identityCreated = !affiliateSnapshot.exists;
        const affiliateFields = identityCreated
            ? {
                id: input.affiliateId,
                phone_e164: input.phoneE164,
                phone_last4: input.phoneE164.slice(-4),
                first_name: input.name.firstName,
                last_name: input.name.lastName,
                display_name: input.name.displayName,
                status: 'ACTIVE',
                merchant_ids: admin.firestore.FieldValue.arrayUnion(input.merchantId),
                created_at: input.now,
                updated_at: input.now,
            }
            : {
                merchant_ids: admin.firestore.FieldValue.arrayUnion(input.merchantId),
                updated_at: input.now,
            };
        transaction.set(affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId), affiliateFields, {
            merge: true,
        });
        transaction.set(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId), {
            id: linkId,
            merchant_id: input.merchantId,
            affiliate_id: input.affiliateId,
            first_name: input.name.firstName,
            last_name: input.name.lastName,
            display_name: input.name.displayName,
            status: 'ACTIVE',
            linked_at: input.now,
            created_at: input.now,
            updated_at: input.now,
        });
        return {
            identityCreated,
            // A reused identity keeps the name it was created with: two businesses
            // disagreeing about someone's spelling must not rewrite each other.
            stored: identityCreated
                ? {
                    id: input.affiliateId,
                    phone_e164: input.phoneE164,
                    phone_last4: input.phoneE164.slice(-4),
                    first_name: input.name.firstName,
                    last_name: input.name.lastName,
                    display_name: input.name.displayName,
                    status: 'ACTIVE',
                    created_at: input.now,
                    updated_at: input.now,
                }
                : { ...existing, updated_at: input.now },
        };
    });
    const stored = claimed.stored;
    let code;
    try {
        code = await writeAffiliateCode({
            merchantId: input.merchantId,
            affiliateId: input.affiliateId,
            codeId,
            firstName: input.name.firstName,
            defaults: input.defaults,
            now: input.now,
        });
    }
    catch (error) {
        await undoAffiliateClaim({
            merchantId: input.merchantId,
            affiliateId: input.affiliateId,
            linkId,
            identityCreated: claimed.identityCreated,
        });
        throw error;
    }
    return {
        affiliate: affiliateWithLinkName((0, affiliate_api_contracts_js_1.toAffiliateDto)(input.affiliateId, stored), {
            first_name: input.name.firstName,
            last_name: input.name.lastName,
            display_name: input.name.displayName,
        }),
        link: { status: 'ACTIVE', linkedAt: input.now },
        code,
        identityCreated: claimed.identityCreated,
    };
}
/**
 * Puts back what a failed code allocation left behind.
 *
 * A link with no code is worse than no link at all: it appears in the list,
 * cannot be shared, and the merchant's only way out would be to add the person
 * again — which the link itself now refuses. Best effort, and loud when it
 * fails, because there is nothing else to be done from here.
 */
async function undoAffiliateClaim(input) {
    try {
        await db().runTransaction(async (transaction) => {
            const identityRef = affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId);
            const identitySnapshot = await transaction.get(identityRef);
            transaction.delete(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, input.linkId));
            if (!identitySnapshot.exists)
                return;
            const identity = (identitySnapshot.data() ?? {});
            const merchantIds = Array.isArray(identity.merchant_ids)
                ? identity.merchant_ids.filter((value) => typeof value === 'string' && value !== input.merchantId)
                : [];
            if (input.identityCreated && merchantIds.length === 0) {
                transaction.delete(identityRef);
                return;
            }
            transaction.set(identityRef, {
                merchant_ids: admin.firestore.FieldValue.arrayRemove(input.merchantId),
                updated_at: Date.now(),
            }, { merge: true });
        });
    }
    catch (error) {
        console.error('affiliate_claim_rollback_failed', {
            event: 'affiliate_claim_rollback_failed',
            merchant_id: input.merchantId,
            affiliate_id: input.affiliateId,
            message: error instanceof Error ? error.message : String(error),
        });
    }
}
async function writeAffiliateCode(input) {
    const fields = {
        id: input.codeId,
        merchant_id: input.merchantId,
        affiliate_id: input.affiliateId,
        benefit_type: input.defaults.benefit.type,
        benefit_value: input.defaults.benefit.value,
        starts_at: input.defaults.validity.startsAt,
        expires_at: input.defaults.validity.expiresAt,
        usage_limit: input.defaults.usageLimit,
        usage_count: 0,
        first_visit_only: input.defaults.firstVisitOnly,
        status: 'ACTIVE',
        created_at: input.now,
    };
    const allocation = await (0, affiliate_firestore_js_1.claimAffiliateCode)({
        merchantId: input.merchantId,
        affiliateId: input.affiliateId,
        codeId: input.codeId,
        name: input.firstName,
        codeFields: fields,
    });
    return (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(input.codeId, {
        ...fields,
        code: allocation.code,
        normalized_code: (0, affiliate_engine_js_1.normalizeAffiliateCode)(allocation.code),
        updated_at: input.now,
    });
}
/**
 * A code for an affiliate who is already linked but has none.
 *
 * One code per affiliate–merchant pair is a decision, not a limitation of the
 * store, so a second request is refused rather than allocating a code that
 * nothing would ever look up.
 */
async function createCodeForLinkedAffiliate(input) {
    const link = await readLink(input.merchantId, input.affiliateId);
    if (link === null)
        throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
    const codeId = affiliate_engine_js_1.affiliateIds.code(input.affiliateId, input.merchantId);
    const existing = await affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, codeId).get();
    if (existing.exists)
        throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'code_already_exists');
    const affiliate = await affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId).get();
    const data = (affiliate.data() ?? {});
    const firstName = typeof link.first_name === 'string' && link.first_name !== ''
        ? link.first_name
        : typeof data.first_name === 'string' && data.first_name !== ''
            ? data.first_name
            : 'AFILIADO';
    return writeAffiliateCode({
        merchantId: input.merchantId,
        affiliateId: input.affiliateId,
        codeId,
        firstName,
        defaults: input.defaults,
        now: input.now,
    });
}
/* --------------------------------------------------------------- reading */
async function readLink(merchantId, affiliateId) {
    const linkId = affiliate_engine_js_1.affiliateIds.link(affiliateId, merchantId);
    const snapshot = await affiliate_firestore_js_1.affiliateRefs.link(merchantId, linkId).get();
    if (!snapshot.exists)
        return null;
    return (snapshot.data() ?? {});
}
function linkStatusOf(link) {
    return String(link.status ?? '').toUpperCase() === 'INACTIVE'
        ? 'INACTIVE'
        : 'ACTIVE';
}
function affiliateWithLinkName(affiliate, link) {
    const firstName = typeof link.first_name === 'string' && link.first_name.trim() !== ''
        ? link.first_name.trim()
        : affiliate.first_name;
    const displayName = typeof link.display_name === 'string' && link.display_name.trim() !== ''
        ? link.display_name.trim()
        : affiliate.name;
    const lastName = Object.prototype.hasOwnProperty.call(link, 'last_name')
        ? typeof link.last_name === 'string' && link.last_name.trim() !== ''
            ? link.last_name.trim()
            : null
        : affiliate.last_name;
    return {
        ...affiliate,
        name: displayName,
        first_name: firstName,
        last_name: lastName,
    };
}
/**
 * One affiliate, as this business sees them.
 *
 * Null for "no such affiliate" and for "someone else's affiliate" alike: the
 * link document is the only way in, so an id guessed from another business
 * answers exactly as a made-up one does.
 */
async function getMerchantAffiliate(merchantId, affiliateId) {
    const link = await readLink(merchantId, affiliateId);
    if (link === null)
        return null;
    const codeId = affiliate_engine_js_1.affiliateIds.code(affiliateId, merchantId);
    const [affiliateSnapshot, codeSnapshot] = await Promise.all([
        affiliate_firestore_js_1.affiliateRefs.affiliate(affiliateId).get(),
        affiliate_firestore_js_1.affiliateRefs.code(merchantId, codeId).get(),
    ]);
    if (!affiliateSnapshot.exists)
        return null;
    return {
        ...affiliateWithLinkName((0, affiliate_api_contracts_js_1.toAffiliateDto)(affiliateId, (affiliateSnapshot.data() ?? {})), link),
        merchant_id: merchantId,
        link_status: linkStatusOf(link),
        linked_at: typeof link.linked_at === 'number' ? link.linked_at : null,
        code: codeSnapshot.exists
            ? (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(codeSnapshot.id, (codeSnapshot.data() ?? {}))
            : null,
    };
}
async function readScoped(merchantId, collectionId, extra) {
    let query = db()
        .collection('businesses')
        .doc(merchantId)
        .collection(collectionId)
        // Redundant with the path, and kept anyway: it is the filter every
        // composite index starts with, and it makes a stray collection-group
        // query written later fail loudly instead of reading everyone's rows.
        .where('merchant_id', '==', merchantId);
    if (extra)
        query = query.where(extra.field, '==', extra.value);
    const snapshot = await query.limit(exports.AFFILIATE_SCAN_CAP + 1).get();
    const capped = (0, merchant_records_js_1.capDocuments)(snapshot.docs, exports.AFFILIATE_SCAN_CAP);
    return {
        docs: capped.docs.map((doc) => ({
            id: doc.id,
            data: (doc.data() ?? {}),
        })),
        truncated: capped.truncated,
    };
}
async function listMerchantAffiliates(merchantId, query) {
    const [links, codes] = await Promise.all([
        readScoped(merchantId, 'affiliate_merchants'),
        readScoped(merchantId, 'affiliate_codes'),
    ]);
    const codeByAffiliate = new Map();
    for (const doc of codes.docs) {
        const dto = (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(doc.id, doc.data);
        if (dto.affiliate_id !== '')
            codeByAffiliate.set(dto.affiliate_id, dto);
    }
    const affiliateIdList = links.docs
        .map((doc) => (typeof doc.data.affiliate_id === 'string' ? doc.data.affiliate_id : ''))
        .filter((value) => value !== '');
    const identities = await readAffiliates(affiliateIdList);
    const rows = [];
    for (const doc of links.docs) {
        const affiliateId = typeof doc.data.affiliate_id === 'string' ? doc.data.affiliate_id : '';
        const identity = identities.get(affiliateId);
        if (!identity)
            continue;
        rows.push({
            ...affiliateWithLinkName((0, affiliate_api_contracts_js_1.toAffiliateDto)(affiliateId, identity), doc.data),
            merchant_id: merchantId,
            link_status: linkStatusOf(doc.data),
            linked_at: typeof doc.data.linked_at === 'number' ? doc.data.linked_at : null,
            code: codeByAffiliate.get(affiliateId) ?? null,
        });
    }
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows
        .filter((row) => {
        if (search !== '' &&
            !(0, merchant_records_js_1.matchesSearch)([row.name, row.phone_last4, row.code?.code ?? null], search)) {
            return false;
        }
        if (status !== '' && row.link_status !== status)
            return false;
        return true;
    })
        .sort(byRecency);
    return {
        ...(0, merchant_records_js_1.paginate)(filtered, query),
        truncated: links.truncated || codes.truncated,
    };
}
function byRecency(left, right) {
    const a = left.linked_at ?? left.created_at ?? 0;
    const b = right.linked_at ?? right.created_at ?? 0;
    return b - a;
}
/** Identities, in chunks Firestore will accept in one `getAll`. */
async function readAffiliates(ids) {
    const unique = [...new Set(ids)];
    const found = new Map();
    const CHUNK = 100;
    for (let index = 0; index < unique.length; index += CHUNK) {
        const chunk = unique.slice(index, index + CHUNK);
        if (chunk.length === 0)
            continue;
        const snapshots = await db().getAll(...chunk.map((id) => affiliate_firestore_js_1.affiliateRefs.affiliate(id)));
        for (const snapshot of snapshots) {
            if (snapshot.exists)
                found.set(snapshot.id, (snapshot.data() ?? {}));
        }
    }
    return found;
}
async function listMerchantCodes(merchantId, query) {
    const { docs, truncated } = await readScoped(merchantId, 'affiliate_codes', query.affiliateId ? { field: 'affiliate_id', value: query.affiliateId } : undefined);
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const rows = docs
        .map((doc) => (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(doc.id, doc.data))
        .filter((row) => {
        if (search !== '' && !(0, merchant_records_js_1.matchesSearch)([row.code, row.affiliate_id], search)) {
            return false;
        }
        if (status !== '' && row.status !== status)
            return false;
        return true;
    })
        .sort((left, right) => (right.created_at ?? 0) - (left.created_at ?? 0));
    return { ...(0, merchant_records_js_1.paginate)(rows, query), truncated };
}
async function getMerchantCode(merchantId, codeId) {
    const snapshot = await affiliate_firestore_js_1.affiliateRefs.code(merchantId, codeId).get();
    if (!snapshot.exists)
        return null;
    const dto = (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(snapshot.id, (snapshot.data() ?? {}));
    // The path already scopes this, and a row whose own field disagrees with the
    // path is not served rather than trusted.
    return dto.merchant_id === merchantId ? dto : null;
}
async function listAttributions(merchantId, query) {
    const { docs, truncated } = await readScoped(merchantId, 'affiliate_attributions', query.affiliateId ? { field: 'affiliate_id', value: query.affiliateId } : undefined);
    const status = (query.status ?? '').trim().toUpperCase();
    const search = (query.search ?? '').trim();
    const rows = docs
        .map((doc) => (0, affiliate_api_contracts_js_1.toReferralAttributionDto)(doc.id, doc.data))
        .filter((row) => {
        if (status !== '' && row.status !== status)
            return false;
        if (search !== '' &&
            !(0, merchant_records_js_1.matchesSearch)([row.customer_id, row.affiliate_id, row.id], search)) {
            return false;
        }
        return true;
    })
        .sort((left, right) => (right.attributed_at ?? right.created_at ?? 0) -
        (left.attributed_at ?? left.created_at ?? 0));
    return { ...(0, merchant_records_js_1.paginate)(rows, query), truncated };
}
async function getAttribution(merchantId, attributionId) {
    const snapshot = await affiliate_firestore_js_1.affiliateRefs.attribution(merchantId, attributionId).get();
    if (!snapshot.exists)
        return null;
    const dto = (0, affiliate_api_contracts_js_1.toReferralAttributionDto)(snapshot.id, (snapshot.data() ?? {}));
    return dto.merchant_id === merchantId ? dto : null;
}
async function listRewards(merchantId, query) {
    const { docs, truncated } = await readScoped(merchantId, 'affiliate_rewards', query.affiliateId ? { field: 'affiliate_id', value: query.affiliateId } : undefined);
    const status = (query.status ?? '').trim().toUpperCase();
    const rows = docs
        .map((doc) => (0, affiliate_api_contracts_js_1.toAffiliateRewardDto)(doc.id, doc.data))
        .filter((row) => status === '' || row.status === status)
        .sort((left, right) => (right.created_at ?? 0) - (left.created_at ?? 0));
    return { ...(0, merchant_records_js_1.paginate)(rows, query), truncated };
}
/**
 * Edits a code, without touching what it is or how often it has been used.
 *
 * `code`, `usage_count`, `affiliate_id` and `merchant_id` are not in the patch
 * type at all. A merchant lowering `usage_count` would hand out a benefit the
 * limit already refused, and a changed `code` would orphan the lookup document
 * that makes it unique.
 */
async function updateCode(input) {
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, input.codeId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'code_not_found');
        const data = (snapshot.data() ?? {});
        const before = (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(snapshot.id, data);
        if (before.merchant_id !== input.merchantId) {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'code_not_found');
        }
        const changes = { updated_at: input.now };
        if (input.patch.benefit) {
            changes.benefit_type = input.patch.benefit.type;
            changes.benefit_value = input.patch.benefit.value;
        }
        if (input.patch.validity) {
            changes.starts_at = input.patch.validity.startsAt;
            changes.expires_at = input.patch.validity.expiresAt;
        }
        if (input.patch.usageLimit !== undefined) {
            changes.usage_limit = input.patch.usageLimit;
        }
        if (input.patch.firstVisitOnly !== undefined) {
            changes.first_visit_only = input.patch.firstVisitOnly;
        }
        transaction.set(ref, changes, { merge: true });
        return { before, after: (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(snapshot.id, { ...data, ...changes }) };
    });
}
async function setCodeStatus(input) {
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, input.codeId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'code_not_found');
        const data = (snapshot.data() ?? {});
        const before = (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(snapshot.id, data);
        if (before.merchant_id !== input.merchantId) {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'code_not_found');
        }
        const changes = { status: input.status, updated_at: input.now };
        transaction.set(ref, changes, { merge: true });
        return { before, after: (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(snapshot.id, { ...data, ...changes }) };
    });
}
/**
 * Turns a business's relationship with an affiliate on or off.
 *
 * The merchant-facing "deactivate" moves the *link*, never the global
 * identity: one business cannot decide that somebody stops being an affiliate
 * everywhere. Only the console can do that, through `setAffiliateStatus`.
 */
async function setLinkStatus(input) {
    const linkId = affiliate_engine_js_1.affiliateIds.link(input.affiliateId, input.merchantId);
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        const before = linkStatusOf((snapshot.data() ?? {}));
        transaction.set(ref, { status: input.status, updated_at: input.now }, { merge: true });
        return { before, after: input.status };
    });
}
async function updateAffiliateName(input) {
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        const data = (snapshot.data() ?? {});
        const changes = {
            first_name: input.name.firstName,
            last_name: input.name.lastName,
            display_name: input.name.displayName,
            updated_at: input.now,
        };
        transaction.set(ref, changes, { merge: true });
        return {
            before: (0, affiliate_api_contracts_js_1.toAffiliateDto)(input.affiliateId, data),
            after: (0, affiliate_api_contracts_js_1.toAffiliateDto)(input.affiliateId, { ...data, ...changes }),
        };
    });
}
async function updateMerchantAffiliateName(input) {
    return db().runTransaction(async (transaction) => {
        const linkId = affiliate_engine_js_1.affiliateIds.link(input.affiliateId, input.merchantId);
        const linkRef = affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId);
        const identityRef = affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId);
        const [linkSnapshot, identitySnapshot] = await Promise.all([
            transaction.get(linkRef),
            transaction.get(identityRef),
        ]);
        if (!linkSnapshot.exists || !identitySnapshot.exists) {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        }
        const link = (linkSnapshot.data() ?? {});
        if (String(link.merchant_id ?? '') !== input.merchantId) {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        }
        const identity = (0, affiliate_api_contracts_js_1.toAffiliateDto)(input.affiliateId, (identitySnapshot.data() ?? {}));
        const beforeView = affiliateWithLinkName(identity, link);
        const before = {
            firstName: beforeView.first_name,
            lastName: beforeView.last_name,
            displayName: beforeView.name,
        };
        transaction.set(linkRef, {
            first_name: input.name.firstName,
            last_name: input.name.lastName,
            display_name: input.name.displayName,
            updated_at: input.now,
        }, { merge: true });
        return { before, after: input.name };
    });
}
async function setAffiliateStatus(input) {
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        const data = (snapshot.data() ?? {});
        const changes = { status: input.status, updated_at: input.now };
        transaction.set(ref, changes, { merge: true });
        return {
            before: (0, affiliate_api_contracts_js_1.toAffiliateDto)(input.affiliateId, data),
            after: (0, affiliate_api_contracts_js_1.toAffiliateDto)(input.affiliateId, { ...data, ...changes }),
        };
    });
}
/**
 * Moves a reward, or refuses.
 *
 * The decision carries no value: what a reward is worth was decided when it
 * was created, from the business's own settings, and an approval request that
 * sent an amount would be asking the approver's browser what to pay. The
 * transaction re-reads the status inside itself so that two approvers pressing
 * at once produce one approval and one refusal.
 */
async function transitionReward(input) {
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.reward(input.merchantId, input.rewardId);
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'reward_not_found');
        const data = (snapshot.data() ?? {});
        const before = (0, affiliate_api_contracts_js_1.toAffiliateRewardDto)(snapshot.id, data);
        if (before.merchant_id !== input.merchantId) {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'reward_not_found');
        }
        if (!(0, affiliate_api_contracts_js_1.canTransitionReward)(before.status, input.to)) {
            throw (0, affiliate_api_contracts_js_1.rewardTransitionError)(before.status, input.to);
        }
        const changes = { status: input.to, updated_at: input.now };
        if (input.to === 'APPROVED') {
            changes.approved_at = input.now;
            changes.approved_by = input.actorId;
        }
        if (input.to === 'CANCELLED')
            changes.cancelled_at = input.now;
        if (input.to === 'PAID')
            changes.paid_at = input.now;
        transaction.set(ref, changes, { merge: true });
        return { before, after: (0, affiliate_api_contracts_js_1.toAffiliateRewardDto)(snapshot.id, { ...data, ...changes }) };
    });
}
/** Compared, never printed, and never stored: the phone stays out of events. */
function phoneFingerprint(phoneE164) {
    if (phoneE164 === null || phoneE164 === '')
        return '';
    return (0, crypto_1.createHash)('sha256').update(`affiliate-phone-v1:${phoneE164}`).digest('hex');
}
/**
 * What the till is shown before a sale exists.
 *
 * With an amount, this is the real calculation — the same one the commit will
 * run. Without one there is nothing to take a percentage of, so the text
 * describes the code rather than a discount: "10% de desconto", not
 * "10% de desconto (0 MT)", which would read as a discount worth nothing.
 */
function advisoryBenefit(code, saleAmount) {
    if (saleAmount !== null) {
        const calculated = (0, affiliate_engine_js_1.calculateBenefit)(code, saleAmount);
        return {
            type: calculated.type,
            value: calculated.value,
            displayText: calculated.displayText,
        };
    }
    if (code.benefitType === 'POINTS') {
        const points = Math.floor(code.benefitValue);
        return {
            type: 'POINTS',
            value: points,
            displayText: `${points.toLocaleString('pt-PT')} pontos extra`,
        };
    }
    return {
        type: code.benefitType,
        value: code.benefitValue,
        displayText: code.benefitType === 'PERCENTAGE'
            ? `${code.benefitValue}% de desconto`
            : `${code.benefitValue} MT de desconto`,
    };
}
/**
 * Runs §5.1 against what Firestore actually holds.
 *
 * The lookup is global, so the first thing done with its answer is to compare
 * the business it names with the business asking. A code belonging to somebody
 * else is turned into `CODE_NOT_FOUND` before anything else is read — no
 * document of theirs is fetched, so not even a timing difference distinguishes
 * "exists elsewhere" from "does not exist".
 */
async function validateReferralCode(input) {
    const normalizedCode = (0, affiliate_engine_js_1.normalizeAffiliateCode)(input.rawCode);
    const customerFingerprint = phoneFingerprint(input.customerPhoneE164);
    const dedupeKey = (0, crypto_1.createHash)('sha256')
        .update([input.merchantId, normalizedCode, customerFingerprint].join('\u001f'))
        .digest('hex')
        .slice(0, 40);
    const base = {
        affiliateId: null,
        affiliateName: null,
        codeId: null,
        normalizedCode,
        firstVisitOnly: true,
        benefit: null,
        customerId: null,
        dedupeKey,
    };
    const lookup = await (0, affiliate_firestore_js_1.resolveCodeLookup)(normalizedCode);
    if (lookup === null || lookup.merchantId !== input.merchantId) {
        return { ...base, validation: { ok: false, reason: 'CODE_NOT_FOUND' } };
    }
    const [codeSnapshot, affiliateSnapshot, linkSnapshot] = await Promise.all([
        affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, lookup.codeId).get(),
        affiliate_firestore_js_1.affiliateRefs.affiliate(lookup.affiliateId).get(),
        affiliate_firestore_js_1.affiliateRefs
            .link(input.merchantId, affiliate_engine_js_1.affiliateIds.link(lookup.affiliateId, input.merchantId))
            .get(),
    ]);
    if (!codeSnapshot.exists) {
        return { ...base, validation: { ok: false, reason: 'CODE_NOT_FOUND' } };
    }
    const codeData = (codeSnapshot.data() ?? {});
    const code = (0, affiliate_api_contracts_js_1.toAffiliateCodeDto)(codeSnapshot.id, codeData);
    if (code.merchant_id !== input.merchantId) {
        return { ...base, validation: { ok: false, reason: 'CODE_NOT_FOUND' } };
    }
    const affiliateData = (affiliateSnapshot.data() ?? {});
    const affiliate = (0, affiliate_api_contracts_js_1.toAffiliateDto)(lookup.affiliateId, affiliateData);
    const linkData = linkSnapshot.exists ? (linkSnapshot.data() ?? {}) : null;
    const merchantAffiliate = affiliateWithLinkName(affiliate, linkData ?? {});
    const history = await loadCustomerHistory({
        merchantId: input.merchantId,
        phoneE164: input.customerPhoneE164,
    });
    const snapshot = {
        codeId: code.id,
        merchantId: code.merchant_id,
        affiliateId: code.affiliate_id,
        status: code.status,
        startsAt: code.starts_at ?? 0,
        expiresAt: code.expires_at ?? Number.MAX_SAFE_INTEGER,
        usageLimit: code.usage_limit,
        usageCount: code.usage_count,
        firstVisitOnly: code.first_visit_only,
        benefitType: code.benefit_type,
        benefitValue: code.benefit_value,
    };
    const validation = (0, affiliate_engine_js_1.validateReferral)(snapshot, {
        merchantId: input.merchantId,
        now: input.now,
        affiliateStatus: affiliateSnapshot.exists ? affiliate.status : 'INACTIVE',
        linkStatus: linkData === null ? 'INACTIVE' : linkStatusOf(linkData),
        affiliatePhoneHash: phoneFingerprint(rowString(affiliateData, 'phone_e164', 'phone')),
        customerPhoneHash: customerFingerprint,
        customerIsNew: history.isNew,
        existingAttributionStatus: history.attributionStatus,
        saleAmount: input.saleAmount,
    });
    const benefit = advisoryBenefit(snapshot, input.saleAmount);
    return {
        validation,
        affiliateId: code.affiliate_id,
        affiliateName: merchantAffiliate.first_name || merchantAffiliate.name,
        codeId: code.id,
        normalizedCode: code.normalized_code || normalizedCode,
        firstVisitOnly: code.first_visit_only,
        benefit,
        customerId: history.customerId,
        dedupeKey,
    };
}
/**
 * What the till already knows about this phone at this business.
 *
 * Phones are stored either as E.164 or as the nine local digits depending on
 * which path wrote the record, which is why both are asked for — the same
 * candidate list `requestHasBusinessMembership` builds for app users.
 *
 * With no phone at all the customer cannot be shown to be new, so they are
 * treated as not new. `firstVisitOnly` then refuses, which is the safe way
 * round: a benefit withheld is a conversation, a benefit given to an existing
 * customer is an acquisition reward that was never earned.
 */
async function loadCustomerHistory(input) {
    if (input.phoneE164 === null || input.phoneE164 === '') {
        return { customerId: null, isNew: false, attributionStatus: null };
    }
    const candidates = [input.phoneE164, input.phoneE164.slice(-9)];
    const customers = db()
        .collection('businesses')
        .doc(input.merchantId)
        .collection('customers');
    const matched = new Map();
    for (const candidate of candidates) {
        const snapshot = await customers.where('phone', '==', candidate).limit(25).get();
        for (const doc of snapshot.docs) {
            matched.set(doc.id, (doc.data() ?? {}));
        }
    }
    if (matched.size === 0) {
        return { customerId: null, isNew: true, attributionStatus: null };
    }
    const entries = [...matched.entries()];
    const [primaryId, primaryData] = entries[0];
    const attribution = await readAttributionForCustomer(input.merchantId, primaryId);
    const hasPreviousCompletedSale = await hasCompletedSale(input.merchantId, entries.map(([id]) => id));
    const isNew = (0, affiliate_engine_js_1.isNewCustomer)({
        hasPreviousCompletedSale,
        hasNonRejectedAttribution: attribution !== null && attribution !== 'REJECTED',
        // More than one record on one phone is a duplicate the till has not
        // merged; treating it as new would be a second first visit.
        phoneAlreadyKnown: entries.length > 1,
        // Self-referral is checked before eligibility and has its own reason code,
        // so this clause is deliberately not used to swallow it here.
        isAffiliate: false,
        isTestAccount: readFlag(primaryData, 'is_test', 'is_test_account'),
        isBlocked: readFlag(primaryData, 'is_blocked') ||
            String(primaryData.relationship_status ?? '').toUpperCase() === 'BLOCKED',
    });
    return { customerId: primaryId, isNew, attributionStatus: attribution };
}
function readFlag(data, ...keys) {
    for (const key of keys) {
        if (data[key] === true)
            return true;
    }
    return false;
}
async function readAttributionForCustomer(merchantId, customerId) {
    const snapshot = await affiliate_firestore_js_1.affiliateRefs
        .attribution(merchantId, affiliate_engine_js_1.affiliateIds.attribution(merchantId, customerId))
        .get();
    if (!snapshot.exists)
        return null;
    const status = String((snapshot.data() ?? {}).status ?? '').toUpperCase();
    if (status === 'CONFIRMED' || status === 'REJECTED' || status === 'CANCELLED') {
        return status;
    }
    return null;
}
/** A sale counts as completed unless it was cancelled. */
async function hasCompletedSale(merchantId, customerIds) {
    const sales = db()
        .collection('businesses')
        .doc(merchantId)
        .collection('sales');
    for (const customerId of customerIds.slice(0, 5)) {
        const snapshot = await sales
            .where('customer_id', '==', customerId)
            .limit(25)
            .get();
        for (const doc of snapshot.docs) {
            const data = (doc.data() ?? {});
            const cancellation = String(data.cancellation_status ?? '').toUpperCase();
            const confirmation = String(data.confirmation_status ?? '').toUpperCase();
            if (cancellation === 'CANCELLED' || confirmation === 'CANCELLED')
                continue;
            const amount = typeof data.amount === 'number' ? data.amount : 0;
            if (amount > 0)
                return true;
        }
    }
    return false;
}
/* ----------------------------------------------------------------- metrics */
/**
 * The numbers behind the metrics screen, from three bounded reads.
 *
 * Validation attempts are counted by distinct `dedupe_key`, so a till that
 * retried four times has tried once — otherwise the conversion rate would fall
 * every time somebody mistyped and corrected a code. `summarizeAffiliateMetrics`
 * owns the division, which is how a business with no attempts yet reads 0
 * rather than NaN.
 */
async function affiliateMetrics(input) {
    const scope = input.affiliateId
        ? { field: 'affiliate_id', value: input.affiliateId }
        : undefined;
    const [attributions, rewards, events] = await Promise.all([
        readScoped(input.merchantId, 'affiliate_attributions', scope),
        readScoped(input.merchantId, 'affiliate_rewards', scope),
        readEvents(input.merchantId, input.affiliateId),
    ]);
    let confirmed = 0;
    let rejected = 0;
    for (const doc of attributions.docs) {
        const status = String(doc.data.status ?? '').toUpperCase();
        if (status === 'CONFIRMED')
            confirmed++;
        else if (status === 'REJECTED')
            rejected++;
    }
    let pendingCount = 0;
    let pendingPoints = 0;
    let approvedCount = 0;
    let approvedPoints = 0;
    for (const doc of rewards.docs) {
        const reward = (0, affiliate_api_contracts_js_1.toAffiliateRewardDto)(doc.id, doc.data);
        if (reward.value_type !== 'POINTS')
            continue;
        if (reward.status === 'PENDING') {
            pendingCount++;
            pendingPoints += Math.max(0, reward.value);
        }
        else if (reward.status === 'APPROVED') {
            approvedCount++;
            approvedPoints += Math.max(0, reward.value);
        }
    }
    const attempts = new Set();
    const returned = new Set();
    let lastEventAt = null;
    for (const doc of events.docs) {
        const type = String(doc.data.event_type ?? '').toUpperCase();
        const createdAt = typeof doc.data.created_at === 'number' ? doc.data.created_at : null;
        if (createdAt !== null && (lastEventAt === null || createdAt > lastEventAt)) {
            lastEventAt = createdAt;
        }
        if (type === 'REFERRAL_CODE_VALIDATED' || type === 'REFERRAL_REJECTED') {
            const key = typeof doc.data.dedupe_key === 'string' && doc.data.dedupe_key !== ''
                ? doc.data.dedupe_key
                : doc.id;
            attempts.add(key);
        }
        if (type === 'REFERRED_CUSTOMER_RETURNED') {
            const metadata = doc.data.metadata != null && typeof doc.data.metadata === 'object'
                ? doc.data.metadata
                : {};
            const attributionId = typeof metadata.attribution_id === 'string' ? metadata.attribution_id : doc.id;
            returned.add(attributionId);
        }
    }
    const summary = (0, affiliate_engine_js_1.summarizeAffiliateMetrics)({
        uniqueValidationAttempts: attempts.size,
        confirmedAttributions: confirmed,
        rejectedAttributions: rejected,
        returnedCustomers: returned.size,
        pendingRewardCount: pendingCount,
        pendingRewardPoints: pendingPoints,
        approvedRewardCount: approvedCount,
        approvedRewardPoints: approvedPoints,
        lastEventAt,
    });
    return {
        merchant_id: input.merchantId,
        affiliate_id: input.affiliateId,
        unique_validation_attempts: summary.uniqueValidationAttempts,
        confirmed_attributions: summary.confirmedAttributions,
        rejected_attributions: summary.rejectedAttributions,
        returned_customers: summary.returnedCustomers,
        pending_reward_count: summary.pendingRewardCount,
        pending_reward_points: summary.pendingRewardPoints,
        approved_reward_count: summary.approvedRewardCount,
        approved_reward_points: summary.approvedRewardPoints,
        conversion_rate: summary.conversionRate,
        last_activity_at: summary.lastEventAt,
        truncated: attributions.truncated || rewards.truncated || events.truncated,
    };
}
async function readEvents(merchantId, affiliateId) {
    let query = affiliate_firestore_js_1.affiliateRefs
        .events(merchantId)
        .where('merchant_id', '==', merchantId);
    if (affiliateId)
        query = query.where('affiliate_id', '==', affiliateId);
    const snapshot = await query.limit(exports.AFFILIATE_SCAN_CAP + 1).get();
    const capped = (0, merchant_records_js_1.capDocuments)(snapshot.docs, exports.AFFILIATE_SCAN_CAP);
    return {
        docs: capped.docs.map((doc) => ({
            id: doc.id,
            data: (doc.data() ?? {}),
        })),
        truncated: capped.truncated,
    };
}
/* ------------------------------------------------------------------- admin */
async function listAllAffiliates(query) {
    const snapshot = await db()
        .collection('affiliates')
        .limit(exports.AFFILIATE_SCAN_CAP + 1)
        .get();
    const capped = (0, merchant_records_js_1.capDocuments)(snapshot.docs, exports.AFFILIATE_SCAN_CAP);
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const rows = capped.docs
        .map((doc) => (0, affiliate_api_contracts_js_1.toAdminAffiliateDto)(doc.id, (doc.data() ?? {})))
        .filter((row) => {
        if (status !== '' && row.status !== status)
            return false;
        if (search === '')
            return true;
        // Searching by the last four digits is how an operator finds somebody
        // from a support call without the directory holding a searchable phone.
        return ((0, merchant_records_js_1.matchesSearch)([row.name, row.id], search) ||
            (row.phone_last4 !== null && (0, merchant_records_js_1.fold)(row.phone_last4) === (0, merchant_records_js_1.fold)(search)));
    })
        .sort((left, right) => (right.created_at ?? 0) - (left.created_at ?? 0));
    return { ...(0, merchant_records_js_1.paginate)(rows, query), truncated: capped.truncated };
}
async function getAffiliate(affiliateId) {
    const snapshot = await affiliate_firestore_js_1.affiliateRefs.affiliate(affiliateId).get();
    if (!snapshot.exists)
        return null;
    return (0, affiliate_api_contracts_js_1.toAdminAffiliateDto)(snapshot.id, (snapshot.data() ?? {}));
}
/**
 * Creates a global identity with no business attached.
 *
 * The console needs this because an affiliate can exist before anyone has
 * decided which shop they belong to. The deterministic id is what stops it
 * from being a second identity for a phone that already has one.
 */
async function createGlobalAffiliate(input) {
    return db().runTransaction(async (transaction) => {
        const ref = affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId);
        const snapshot = await transaction.get(ref);
        if (snapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'affiliate_already_linked');
        const fields = {
            id: input.affiliateId,
            phone_e164: input.phoneE164,
            phone_last4: input.phoneE164.slice(-4),
            first_name: input.name.firstName,
            last_name: input.name.lastName,
            display_name: input.name.displayName,
            status: 'ACTIVE',
            merchant_ids: [],
            created_at: input.now,
            updated_at: input.now,
        };
        transaction.set(ref, fields);
        return (0, affiliate_api_contracts_js_1.toAdminAffiliateDto)(input.affiliateId, fields);
    });
}
/**
 * Links an existing identity to a business, creating its code if it has none.
 *
 * Re-linking somebody who was unlinked reactivates the link rather than
 * refusing: the history — the attributions, the rewards, the events — is
 * already under that business and should come back with them.
 */
async function linkAffiliateToMerchant(input) {
    const linkId = affiliate_engine_js_1.affiliateIds.link(input.affiliateId, input.merchantId);
    await db().runTransaction(async (transaction) => {
        const [affiliateSnapshot, linkSnapshot] = await Promise.all([
            transaction.get(affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId)),
            transaction.get(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId)),
        ]);
        if (!affiliateSnapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        const data = (affiliateSnapshot.data() ?? {});
        if (String(data.status ?? '').toUpperCase() === 'SUSPENDED') {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'affiliate_suspended');
        }
        if (linkSnapshot.exists &&
            linkStatusOf((linkSnapshot.data() ?? {})) === 'ACTIVE') {
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'affiliate_already_linked');
        }
        transaction.set(affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId), {
            merchant_ids: admin.firestore.FieldValue.arrayUnion(input.merchantId),
            updated_at: input.now,
        }, { merge: true });
        transaction.set(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId), {
            id: linkId,
            merchant_id: input.merchantId,
            affiliate_id: input.affiliateId,
            ...(!linkSnapshot.exists
                ? {
                    first_name: typeof data.first_name === 'string' ? data.first_name : '',
                    last_name: typeof data.last_name === 'string' ? data.last_name : null,
                    display_name: typeof data.display_name === 'string' ? data.display_name : '',
                }
                : {}),
            status: 'ACTIVE',
            linked_at: linkSnapshot.exists
                ? (linkSnapshot.data() ?? {}).linked_at ?? input.now
                : input.now,
            created_at: linkSnapshot.exists
                ? (linkSnapshot.data() ?? {}).created_at ?? input.now
                : input.now,
            updated_at: input.now,
        }, { merge: true });
    });
    const codeId = affiliate_engine_js_1.affiliateIds.code(input.affiliateId, input.merchantId);
    const existingCode = await affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, codeId).get();
    if (!existingCode.exists) {
        await createCodeForLinkedAffiliate({
            merchantId: input.merchantId,
            affiliateId: input.affiliateId,
            defaults: input.defaults,
            now: input.now,
        });
    }
    else {
        await affiliate_firestore_js_1.affiliateRefs
            .code(input.merchantId, codeId)
            .set({ status: 'ACTIVE', updated_at: input.now }, { merge: true });
    }
    const affiliate = await getMerchantAffiliate(input.merchantId, input.affiliateId);
    if (affiliate === null)
        throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
    return affiliate;
}
/**
 * Detaches an affiliate from a business without erasing anything.
 *
 * The link stays, as `INACTIVE`, and the code is disabled rather than removed:
 * a code that vanished would make every attribution pointing at it unreadable,
 * and the MVP has no physical deletion at all.
 */
async function unlinkAffiliateFromMerchant(input) {
    const linkId = affiliate_engine_js_1.affiliateIds.link(input.affiliateId, input.merchantId);
    const codeId = affiliate_engine_js_1.affiliateIds.code(input.affiliateId, input.merchantId);
    await db().runTransaction(async (transaction) => {
        const [linkSnapshot, codeSnapshot] = await Promise.all([
            transaction.get(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId)),
            transaction.get(affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, codeId)),
        ]);
        if (!linkSnapshot.exists)
            throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'affiliate_not_found');
        transaction.set(affiliate_firestore_js_1.affiliateRefs.link(input.merchantId, linkId), { status: 'INACTIVE', updated_at: input.now }, { merge: true });
        if (codeSnapshot.exists) {
            transaction.set(affiliate_firestore_js_1.affiliateRefs.code(input.merchantId, codeId), { status: 'DISABLED', updated_at: input.now }, { merge: true });
        }
        transaction.set(affiliate_firestore_js_1.affiliateRefs.affiliate(input.affiliateId), {
            merchant_ids: admin.firestore.FieldValue.arrayRemove(input.merchantId),
            updated_at: input.now,
        }, { merge: true });
    });
}
