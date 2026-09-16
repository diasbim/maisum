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

/**
 * Mirror of `resolveAppUserRole()` in `functions/src/index.ts`.
 *
 * The app writes one of two roles into the token, and the API reads it to
 * decide who may change an affiliate, a code or a reward. Anything that is not
 * `STAFF` — including a token with no role at all — is the owner, which is the
 * same fallback the API applies: a business bootstrapped under the owner's own
 * uid carries no role claim.
 */
export function appUserRole(claims: unknown): 'OWNER' | 'STAFF' {
  if (claims == null || typeof claims !== 'object') return 'OWNER';
  const record = claims as Record<string, unknown>;
  const raw =
    typeof record.app_user_role === 'string'
      ? record.app_user_role
      : typeof record.appUserRole === 'string'
        ? record.appUserRole
        : typeof record.role === 'string'
          ? record.role
          : null;
  return raw?.trim().toUpperCase() === 'STAFF' ? 'STAFF' : 'OWNER';
}

/**
 * Mirror of `isOwnerOrAdminRequest()` in `functions/src/index.ts`.
 *
 * Used to decide whether a business screen offers a control or explains why it
 * cannot. It is a courtesy, never the gate: the API re-derives exactly this
 * from the same token and answers 403 with its own sentence, so a hidden
 * button is not what stops a manager from approving a reward.
 */
export function canManageAsOwner(claims: unknown): boolean {
  return hasAdminClaims(claims) || appUserRole(claims) === 'OWNER';
}
