/**
 * Configuration, read once and validated loudly.
 *
 * Anything missing should fail at the first request with a message naming the
 * variable, rather than surfacing later as an opaque auth or fetch error.
 */

function required(name: string, value: string | undefined): string {
  if (!value || value.trim().length === 0) {
    throw new Error(
      `Missing required environment variable ${name}. ` +
        'See admin/.env.example.',
    );
  }
  return value.trim();
}

/** Values shipped to the browser. These are public by design. */
export const publicConfig = {
  firebaseApiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? '',
  firebaseAuthDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN ?? '',
  firebaseProjectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? '',
  /**
   * e.g. http://127.0.0.1:9099 — set only for local development against the
   * Firebase Auth emulator. Must be unset in every deployed environment.
   */
  authEmulatorHost: process.env.NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST ?? '',
};

/** Server-only values. Never import this module from a client component. */
export function serverConfig() {
  return {
    projectId: required(
      'FIREBASE_PROJECT_ID',
      process.env.FIREBASE_PROJECT_ID ?? publicConfig.firebaseProjectId,
    ),
    /**
     * Base URL of the Cloud Functions HTTP API, without a trailing slash.
     * The portal never talks to PostgreSQL or Firestore directly — it calls
     * this API, so authorization stays in one place and the portal is
     * unaffected when those queries are rewritten.
     */
    adminApiBaseUrl: required(
      'ADMIN_API_BASE_URL',
      process.env.ADMIN_API_BASE_URL,
    ).replace(/\/+$/, ''),
    /**
     * Optional service account JSON. When absent, the Admin SDK falls back to
     * Application Default Credentials, which is the right setup on Cloud Run
     * and for `gcloud auth application-default login` locally.
     */
    serviceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim() || null,
    isProduction: process.env.NODE_ENV === 'production',
  };
}

export function assertPublicConfig(): void {
  // authEmulatorHost is intentionally excluded: it is optional and empty in
  // every deployed environment.
  const required = ['firebaseApiKey', 'firebaseAuthDomain', 'firebaseProjectId'] as const;
  const missing = required.filter((key) => publicConfig[key].length === 0);
  if (missing.length > 0) {
    throw new Error(
      `Missing NEXT_PUBLIC_FIREBASE_* configuration: ${missing.join(', ')}. ` +
        'See admin/.env.example.',
    );
  }
}
