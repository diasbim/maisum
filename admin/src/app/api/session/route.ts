import { NextResponse, type NextRequest } from 'next/server';

import { hasAdminClaims } from '@/lib/admin-claims';
import { serverConfig } from '@/lib/env';
import { verifySessionToken } from '@/lib/firebase-admin';
import { SESSION_COOKIE, SESSION_MAX_AGE_SECONDS } from '@/lib/session-cookie';

export const runtime = 'nodejs';

/**
 * Exchanges a Firebase ID token for an httpOnly session cookie.
 *
 * The token is verified here, and the admin claim is required, so a non-admin
 * never gets a portal cookie at all. The client re-posts on every
 * `onIdTokenChanged`, which is what keeps the cookie fresh as tokens rotate.
 */
export async function POST(request: NextRequest) {
  let idToken: unknown;
  try {
    const body: unknown = await request.json();
    idToken = (body as { idToken?: unknown } | null)?.idToken;
  } catch {
    return NextResponse.json(
      { error: 'Expected a JSON body.' },
      { status: 400 },
    );
  }

  if (typeof idToken !== 'string' || idToken.length === 0) {
    return NextResponse.json({ error: 'Missing idToken.' }, { status: 400 });
  }

  const claims = await verifySessionToken(idToken);
  if (!claims) {
    return NextResponse.json({ error: 'Invalid token.' }, { status: 401 });
  }

  if (!hasAdminClaims(claims)) {
    // Deliberately not a cookie-setting path: an authenticated non-admin gets
    // no session at all, so nothing downstream has to re-check.
    return NextResponse.json(
      { error: 'This account does not have admin access.' },
      { status: 403 },
    );
  }

  const response = NextResponse.json({ uid: claims.uid, email: claims.email ?? null });
  response.cookies.set({
    name: SESSION_COOKIE,
    value: idToken,
    httpOnly: true,
    secure: serverConfig().isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: SESSION_MAX_AGE_SECONDS,
  });
  return response;
}

/** Signs out by clearing the cookie. */
export async function DELETE() {
  const response = NextResponse.json({ ok: true });
  response.cookies.set({
    name: SESSION_COOKIE,
    value: '',
    httpOnly: true,
    secure: serverConfig().isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: 0,
  });
  return response;
}
