import 'server-only';

import { hasAdminClaims } from './admin-claims';
import { fetchMyBusinesses } from './merchant-api';
import { getPortalSession } from './session';

export type PortalHome = '/login' | '/admin' | '/negocio' | '/no-access';

/**
 * Where a signed-in person belongs.
 *
 * The portal has two areas, and until now three places decided independently
 * which one someone was in: the sign-in exchange, the console's gate, and the
 * business area's gate. The bare `/` did not decide at all — it sent everyone
 * to `/admin`, so a business owner who typed the address was told they had no
 * access to a portal they do have.
 *
 * Asking the same question in one place also fixes the reverse: an area gate
 * that turns someone away can now send them somewhere useful instead of to the
 * dead end that `/no-access` is meant for.
 *
 * Order matters. Internal access wins when an account somehow has both, since
 * the console is the surface that account exists to use, and it is settled
 * from the token alone — an admin never pays for the business lookup.
 */
export async function resolvePortalHome(): Promise<PortalHome> {
  const session = await getPortalSession();
  if (!session) return '/login';
  if (hasAdminClaims(session.claims)) return '/admin';

  // Most merchants hold no claim; only the API can say whether any business
  // answers to them. `fetchMyBusinesses` treats a 403 as "none", so this is a
  // question with an answer rather than an error path.
  const businesses = await fetchMyBusinesses();
  return businesses.length > 0 ? '/negocio' : '/no-access';
}
