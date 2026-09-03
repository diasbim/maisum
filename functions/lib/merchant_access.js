"use strict";
/**
 * Who may act as a business, and for which business.
 *
 * This mirrors `canAccessBusiness()` in `firestore.rules`. The rules are the
 * authority for anything a client reads directly; this is the authority for the
 * `/merchant/*` endpoints, which run with the Admin SDK and therefore bypass
 * the rules entirely. The two must not drift — `merchant_access.test.ts` reads
 * `firestore.rules` and fails if they do.
 *
 * There are four ways in, and they exist because merchants arrived by four
 * different paths:
 *
 *   1. A `merchant_id` claim, set deliberately by `scripts/admin_claims.js`.
 *   2. A `merchant_ids` list, for one person running several businesses.
 *   3. The business document naming them as owner.
 *   4. The business phone matching the phone they signed in with.
 *
 * Most existing merchants have no claim at all: the app bootstraps a business
 * whose id is the owner's uid, so gating on claims alone would lock out
 * essentially everyone who signed up before claims existed.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.merchantIdsFromClaims = merchantIdsFromClaims;
exports.businessGrantsAccess = businessGrantsAccess;
exports.withMerchantClaim = withMerchantClaim;
exports.canAccessBusiness = canAccessBusiness;
/** The claim names the rules honour, in both snake and camel case. */
const SINGULAR_CLAIMS = ['merchant_id', 'merchantId'];
const LIST_CLAIMS = ['merchant_ids', 'merchantIds'];
/** Business fields that name the owning user. */
const OWNER_FIELDS = ['owner_user_id', 'firebase_uid'];
/**
 * Every business id the token itself asserts.
 *
 * Deduplicated and order-preserving: a token may legitimately carry both the
 * singular and the list form, and the caller uses the first as the default
 * business to show.
 */
function merchantIdsFromClaims(claims) {
    if (claims == null || typeof claims !== 'object')
        return [];
    const record = claims;
    const ids = [];
    const add = (value) => {
        if (typeof value !== 'string')
            return;
        const trimmed = value.trim();
        if (trimmed !== '' && !ids.includes(trimmed))
            ids.push(trimmed);
    };
    for (const key of SINGULAR_CLAIMS)
        add(record[key]);
    for (const key of LIST_CLAIMS) {
        const list = record[key];
        if (Array.isArray(list))
            for (const entry of list)
                add(entry);
    }
    return ids;
}
/**
 * Whether a business document itself grants access to this user.
 *
 * The phone comparison is exact, as it is in the rules. Normalizing here and
 * not there would hand out access the rules would refuse.
 */
function businessGrantsAccess(business, user) {
    if (!business || typeof business !== 'object')
        return false;
    if (!user.uid)
        return false;
    const record = business;
    for (const field of OWNER_FIELDS) {
        if (typeof record[field] === 'string' && record[field] === user.uid) {
            return true;
        }
    }
    return (typeof user.phoneNumber === 'string' &&
        user.phoneNumber !== '' &&
        typeof record.phone === 'string' &&
        record.phone === user.phoneNumber);
}
/**
 * The claim set after granting or revoking one business.
 *
 * `merchant_ids` is the list of record, and `merchant_id` mirrors its first
 * entry: `resolveMerchantId()` in index.ts and several Firestore rules read
 * only the singular form, so writing the list alone would grant access the app
 * cannot see. Revoking the last business clears both rather than leaving an
 * empty list behind, which reads as "granted nothing" instead of "not a
 * merchant".
 *
 * Other claims are carried through untouched — a person can be internal staff
 * and run a business.
 */
function withMerchantClaim(claims, merchantId, grant) {
    const base = claims != null && typeof claims === 'object'
        ? { ...claims }
        : {};
    const target = merchantId.trim();
    if (target === '')
        return base;
    const current = merchantIdsFromClaims(base);
    const next = grant
        ? current.includes(target)
            ? current
            : [...current, target]
        : current.filter((id) => id !== target);
    // The camelCase spellings are read by the rules but never written here;
    // leaving a stale one behind would keep access alive after a revoke.
    delete base.merchantId;
    delete base.merchantIds;
    if (next.length === 0) {
        delete base.merchant_id;
        delete base.merchant_ids;
        return base;
    }
    base.merchant_id = next[0];
    base.merchant_ids = next;
    return base;
}
/**
 * Whether this user may act as this business, given what the token says and
 * what the business document says.
 *
 * `businesses/{uid}` counts: that is the id the app bootstraps a business
 * under, and the rules accept it through `canBootstrapBusinessRead`.
 */
function canAccessBusiness(merchantId, claims, business, user) {
    if (!merchantId)
        return false;
    if (merchantIdsFromClaims(claims).includes(merchantId))
        return true;
    if (merchantId === user.uid)
        return true;
    return businessGrantsAccess(business, user);
}
