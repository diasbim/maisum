import 'server-only';

import { cookies } from 'next/headers';
import type { DecodedIdToken } from 'firebase-admin/auth';

import { hasAdminClaims } from './admin-claims';
import { verifySessionToken } from './firebase-admin';

export { SESSION_COOKIE, SESSION_MAX_AGE_SECONDS } from './session-cookie';
import { SESSION_COOKIE } from './session-cookie';

export type AdminSession = {
  uid: string;
  email: string | null;
  idToken: string;
  claims: DecodedIdToken;
};

/**
 * The signed-in admin, or `null`.
 *
 * Verification happens here, on every request that needs it — never in
 * middleware alone, which only checks that a cookie is present. Middleware runs
 * before the app and is the wrong place to be the only gate.
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  const session = await getPortalSession();
  if (!session) return null;
  if (!hasAdminClaims(session.claims)) return null;
  return session;
}

/**
 * A verified signed-in person, with no opinion on what they may do.
 *
 * The portal now has two audiences — internal staff under `/admin`, and
 * business owners under `/negocio` — and they are gated by different questions.
 * This answers only "is this a real, current session"; each area then asks its
 * own. Nothing routes off this alone.
 */
export async function getPortalSession(): Promise<AdminSession | null> {
  const store = await cookies();
  const idToken = store.get(SESSION_COOKIE)?.value;
  if (!idToken) return null;

  const claims = await verifySessionToken(idToken);
  if (!claims) return null;

  return {
    uid: claims.uid,
    email: typeof claims.email === 'string' ? claims.email : null,
    idToken,
    claims,
  };
}

