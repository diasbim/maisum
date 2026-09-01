import 'server-only';

import {
  applicationDefault,
  cert,
  getApps,
  initializeApp,
  type App,
} from 'firebase-admin/app';
import { getAuth, type DecodedIdToken } from 'firebase-admin/auth';

import { serverConfig } from './env';

let cached: App | null = null;

function adminApp(): App {
  if (cached) return cached;
  const existing = getApps();
  if (existing.length > 0) {
    cached = existing[0];
    return cached;
  }

  const config = serverConfig();
  cached = initializeApp({
    projectId: config.projectId,
    credential: config.serviceAccountJson
      ? cert(JSON.parse(config.serviceAccountJson) as Record<string, string>)
      : applicationDefault(),
  });
  return cached;
}

/**
 * Verifies a Firebase ID token.
 *
 * `checkRevoked` is on: an operator whose admin claim was revoked with
 * `functions/scripts/admin_claims.js` has their refresh tokens invalidated, and
 * this is what makes that take effect here rather than at token expiry.
 *
 * Returns `null` for any invalid, expired or revoked token — callers treat that
 * as "not signed in" and never see the underlying error.
 */
export async function verifySessionToken(
  idToken: string,
): Promise<DecodedIdToken | null> {
  try {
    return await getAuth(adminApp()).verifyIdToken(idToken, true);
  } catch {
    return null;
  }
}
