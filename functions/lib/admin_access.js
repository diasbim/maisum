"use strict";
/**
 * Canonical definition of "is this caller an internal admin?".
 *
 * This predicate is mirrored in two other places that CANNOT import it. When it
 * changes, all three must change together:
 *
 *   1. `firestore.rules` -> `isAdmin()`
 *   2. `lib/features/auth/presentation/auth_controller.dart` ->
 *      `hasInternalAdminClaim()`
 *
 * The parity tests in `admin_access.test.ts` assert that `firestore.rules`
 * still accepts exactly the same claim set, so a drift fails the build rather
 * than silently granting an admin API access it cannot use against Firestore.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ADMIN_API_KEY_PATHS = exports.PRIMARY_ADMIN_CLAIM = exports.ADMIN_ROLE_VALUES = exports.ADMIN_BOOLEAN_CLAIMS = void 0;
exports.hasAdminClaims = hasAdminClaims;
exports.matchesAdminRole = matchesAdminRole;
exports.withAdminClaim = withAdminClaim;
exports.isAdminApiKeyPath = isAdminApiKeyPath;
exports.adminApiKeyMatches = adminApiKeyMatches;
exports.adminClaimNames = adminClaimNames;
const node_crypto_1 = require("node:crypto");
function sha256(value) {
    return (0, node_crypto_1.createHash)('sha256').update(value, 'utf8').digest();
}
/** Custom claims that grant admin access when set to boolean `true`. */
exports.ADMIN_BOOLEAN_CLAIMS = [
    'admin',
    'is_admin',
    'internal_admin',
];
/**
 * Values of the `role` claim that grant admin access. Compared after trimming
 * and lower-casing, so `"Internal_Admin"` and `" admin "` both match.
 */
exports.ADMIN_ROLE_VALUES = ['admin', 'internal_admin'];
/**
 * True when the decoded token claims grant internal admin access.
 *
 * Accepts `unknown` because callers hold loosely-typed decoded tokens; anything
 * that is not a plain object is treated as "no claims".
 */
function hasAdminClaims(claims) {
    if (claims == null || typeof claims !== 'object')
        return false;
    const record = claims;
    for (const claim of exports.ADMIN_BOOLEAN_CLAIMS) {
        if (record[claim] === true)
            return true;
    }
    return matchesAdminRole(record.role);
}
/** True when a `role` claim value is one of the admin roles. */
function matchesAdminRole(role) {
    if (typeof role !== 'string')
        return false;
    const normalized = role.trim().toLowerCase();
    return exports.ADMIN_ROLE_VALUES.includes(normalized);
}
/**
 * The claim `scripts/admin_claims.js` writes when granting admin access.
 *
 * The predicate accepts several historical spellings, but only one is issued,
 * so revoking is unambiguous.
 */
exports.PRIMARY_ADMIN_CLAIM = 'internal_admin';
/**
 * Existing custom claims with admin access added or removed, preserving every
 * other claim. Removing also strips the alternative spellings, so a user
 * granted admin by an older path is fully revoked rather than partially.
 */
function withAdminClaim(existing, grant) {
    const claims = { ...(existing ?? {}) };
    if (grant) {
        claims[exports.PRIMARY_ADMIN_CLAIM] = true;
        return claims;
    }
    for (const claim of exports.ADMIN_BOOLEAN_CLAIMS) {
        delete claims[claim];
    }
    if (matchesAdminRole(claims.role)) {
        delete claims.role;
    }
    return claims;
}
// --- ADMIN_API_KEY -----------------------------------------------------------
// The shared `x-admin-key` header authenticates automation, not a person. It
// carries no identity, so it is restricted to the batch endpoints a scheduled
// job legitimately needs. Everything else — reads, plan/price writes,
// entitlement overrides — requires a real admin identity that can be audited.
/** Full request paths on which `x-admin-key` is accepted. */
exports.ADMIN_API_KEY_PATHS = [
    '/admin/customer-core/business-customers/backfill',
    '/admin/customer-core/nfc-cards/backfill',
    '/admin/loyalty/ledger/backfill',
    '/admin/loyalty/ledger/reconcile',
    '/admin/retention/classifications/scan',
];
/** True when `x-admin-key` may authenticate this full request path. */
function isAdminApiKeyPath(path) {
    if (typeof path !== 'string')
        return false;
    const normalized = path.trim().replace(/\/+$/, '');
    return exports.ADMIN_API_KEY_PATHS.includes(normalized);
}
/**
 * Constant-time comparison of the configured admin key with the one supplied.
 * Both values are hashed first so the comparison never leaks their length.
 */
function adminApiKeyMatches(expected, provided) {
    if (typeof expected !== 'string' || expected.length === 0)
        return false;
    if (typeof provided !== 'string' || provided.length === 0)
        return false;
    return (0, node_crypto_1.timingSafeEqual)(sha256(expected), sha256(provided));
}
/**
 * Which claims on a token actually grant admin access.
 *
 * `hasAdminClaims` answers yes or no; this answers why. Revoking access means
 * knowing which of the three boolean claims or the role claim to clear — they
 * are set by different paths, and clearing only one of two leaves the access
 * in place.
 */
function adminClaimNames(claims) {
    if (claims == null || typeof claims !== 'object')
        return [];
    const record = claims;
    const granting = [];
    for (const claim of exports.ADMIN_BOOLEAN_CLAIMS) {
        if (record[claim] === true)
            granting.push(claim);
    }
    if (matchesAdminRole(record.role)) {
        granting.push(`role=${String(record.role).trim().toLowerCase()}`);
    }
    return granting;
}
