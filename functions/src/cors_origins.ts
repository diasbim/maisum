/**
 * Which browser origins may call the API.
 *
 * `cors: true` allowed any origin. That was broader than anything needed:
 *
 *  - the Next.js portal calls the API from its own server, never from the
 *    browser, so it needs no CORS entry at all;
 *  - the Flutter mobile app is native, so the browser's origin policy does not
 *    apply to it;
 *  - the landing page makes no API calls.
 *
 * What remains is the Flutter web build (`web/`, titled "Portal de gestão"),
 * which does run in a browser. So the list is explicit and configurable rather
 * than empty — an empty list would break that build the moment it is deployed,
 * with a failure that looks like an outage rather than a config gap.
 */

/** The production site, from Firebase Hosting's `docs` target. */
export const PRIMARY_SITE_ORIGIN = 'https://maisum.tsintsivadigital.com';

/**
 * Origins allowed without configuration.
 *
 * The bare apex is included alongside the app subdomain because a browser sends
 * the origin it was served from, and both are plausible homes for the web
 * build.
 */
export const DEFAULT_ALLOWED_ORIGINS = [
  PRIMARY_SITE_ORIGIN,
  'https://app.maisum.tsintsivadigital.com',
  'https://admin.maisum.tsintsivadigital.com',
] as const;

/** Local origins, allowed only when running against the emulators. */
export const LOCAL_ORIGIN_PATTERN =
  /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/;

function parseOriginList(raw: unknown): string[] {
  if (typeof raw !== 'string') return [];
  return raw
    .split(',')
    .map((entry) => entry.trim().replace(/\/+$/, ''))
    .filter((entry) => entry.length > 0);
}

/**
 * Builds the allowlist.
 *
 * `CORS_ALLOWED_ORIGINS` replaces the defaults outright rather than adding to
 * them, so a deployment that needs a different hostname is not silently still
 * trusting this one.
 *
 * `isEmulator` is passed in rather than read from the environment here, so the
 * decision to trust localhost is visible at the call site.
 */
export function allowedOrigins(
  env: Record<string, string | undefined>,
  isEmulator: boolean,
): Array<string | RegExp> {
  const configured = parseOriginList(env.CORS_ALLOWED_ORIGINS);
  const origins: Array<string | RegExp> =
    configured.length > 0 ? [...configured] : [...DEFAULT_ALLOWED_ORIGINS];

  // Never in a deployed environment: localhost is an origin an attacker can
  // serve from a victim's own machine.
  if (isEmulator) origins.push(LOCAL_ORIGIN_PATTERN);

  return origins;
}

/** True when the process is running under the Firebase emulator suite. */
export function runningInEmulator(
  env: Record<string, string | undefined>,
): boolean {
  return (
    env.FUNCTIONS_EMULATOR === 'true' ||
    typeof env.FIREBASE_AUTH_EMULATOR_HOST === 'string'
  );
}
