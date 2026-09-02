/**
 * Mirror of `functions/src/admin_access.ts` -> `hasAdminClaims()`.
 *
 * It is duplicated rather than imported: Next's bundler will not resolve a
 * runtime import from outside the app root, and the alternatives (a workspace
 * package, a copy step) cost more than this file is worth.
 *
 * The duplication is guarded — `functions/src/admin_access.test.ts` reads this
 * file and fails if it stops accepting the same claim set, the same way it
 * guards `firestore.rules`.
 *
 * This check is a convenience, not the authority: the admin API independently
 * rejects a caller without the claim. It exists so a non-admin never receives a
 * portal session cookie in the first place.
 */

const ADMIN_BOOLEAN_CLAIMS = ['admin', 'is_admin', 'internal_admin'] as const;
const ADMIN_ROLE_VALUES = ['admin', 'internal_admin'] as const;

export function hasAdminClaims(claims: unknown): boolean {
  if (claims == null || typeof claims !== 'object') return false;
  const record = claims as Record<string, unknown>;

  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    if (record[claim] === true) return true;
  }

  const role = record.role;
  if (typeof role !== 'string') return false;
  return (ADMIN_ROLE_VALUES as readonly string[]).includes(
    role.trim().toLowerCase(),
  );
}

/**
 * Which claims grant the access, rather than merely whether one does.
 *
 * Mirrors `adminClaimNames()` in `functions/src/admin_access.ts`. Three separate
 * booleans and a role value can each open the portal, and they are set by
 * different paths — so "you are an admin" is not enough to act on. Revoking
 * means clearing every grant listed here; clearing one of two leaves the access
 * in place.
 */
export function adminClaimNames(claims: unknown): string[] {
  if (claims == null || typeof claims !== 'object') return [];
  const record = claims as Record<string, unknown>;
  const granting: string[] = [];

  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    if (record[claim] === true) granting.push(claim);
  }

  const role = record.role;
  if (
    typeof role === 'string' &&
    (ADMIN_ROLE_VALUES as readonly string[]).includes(role.trim().toLowerCase())
  ) {
    granting.push(`role=${role.trim().toLowerCase()}`);
  }

  return granting;
}
