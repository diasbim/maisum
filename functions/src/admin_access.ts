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

import { createHash, timingSafeEqual } from 'node:crypto';

function sha256(value: string): Buffer {
  return createHash('sha256').update(value, 'utf8').digest();
}

/** Custom claims that grant admin access when set to boolean `true`. */
export const ADMIN_BOOLEAN_CLAIMS = [
  'admin',
  'is_admin',
  'internal_admin',
] as const;

/**
 * Values of the `role` claim that grant admin access. Compared after trimming
 * and lower-casing, so `"Internal_Admin"` and `" admin "` both match.
 */
export const ADMIN_ROLE_VALUES = ['admin', 'internal_admin'] as const;

/**
 * True when the decoded token claims grant internal admin access.
 *
 * Accepts `unknown` because callers hold loosely-typed decoded tokens; anything
 * that is not a plain object is treated as "no claims".
 */
export function hasAdminClaims(claims: unknown): boolean {
  if (claims == null || typeof claims !== 'object') return false;
  const record = claims as Record<string, unknown>;

  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    if (record[claim] === true) return true;
  }

  return matchesAdminRole(record.role);
}

/** True when a `role` claim value is one of the admin roles. */
export function matchesAdminRole(role: unknown): boolean {
  if (typeof role !== 'string') return false;
  const normalized = role.trim().toLowerCase();
  return (ADMIN_ROLE_VALUES as readonly string[]).includes(normalized);
}

/**
 * The claim `scripts/admin_claims.js` writes when granting admin access.
 *
 * The predicate accepts several historical spellings, but only one is issued,
 * so revoking is unambiguous.
 */
export const PRIMARY_ADMIN_CLAIM = 'internal_admin';

/**
 * Existing custom claims with admin access added or removed, preserving every
 * other claim. Removing also strips the alternative spellings, so a user
 * granted admin by an older path is fully revoked rather than partially.
 */
export function withAdminClaim(
  existing: Record<string, unknown> | undefined | null,
  grant: boolean,
): Record<string, unknown> {
  const claims: Record<string, unknown> = { ...(existing ?? {}) };
  if (grant) {
    claims[PRIMARY_ADMIN_CLAIM] = true;
    return claims;
  }

  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
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
export const ADMIN_API_KEY_PATHS = [
  '/admin/customer-core/business-customers/backfill',
  '/admin/customer-core/nfc-cards/backfill',
  '/admin/loyalty/ledger/backfill',
  '/admin/loyalty/ledger/reconcile',
  '/admin/retention/classifications/scan',
] as const;

/** True when `x-admin-key` may authenticate this full request path. */
export function isAdminApiKeyPath(path: unknown): boolean {
  if (typeof path !== 'string') return false;
  const normalized = path.trim().replace(/\/+$/, '');
  return (ADMIN_API_KEY_PATHS as readonly string[]).includes(normalized);
}

/**
 * Constant-time comparison of the configured admin key with the one supplied.
 * Both values are hashed first so the comparison never leaks their length.
 */
export function adminApiKeyMatches(
  expected: unknown,
  provided: unknown,
): boolean {
  if (typeof expected !== 'string' || expected.length === 0) return false;
  if (typeof provided !== 'string' || provided.length === 0) return false;
  return timingSafeEqual(sha256(expected), sha256(provided));
}

/**
 * Which claims on a token actually grant admin access.
 *
 * `hasAdminClaims` answers yes or no; this answers why. Revoking access means
 * knowing which of the three boolean claims or the role claim to clear — they
 * are set by different paths, and clearing only one of two leaves the access
 * in place.
 */
export function adminClaimNames(claims: unknown): string[] {
  if (claims == null || typeof claims !== 'object') return [];
  const record = claims as Record<string, unknown>;
  const granting: string[] = [];

  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    if (record[claim] === true) granting.push(claim);
  }

  if (matchesAdminRole(record.role)) {
    granting.push(`role=${String(record.role).trim().toLowerCase()}`);
  }

  return granting;
}
