"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.LOCAL_ORIGIN_PATTERN = exports.DEFAULT_ALLOWED_ORIGINS = exports.PRIMARY_SITE_ORIGIN = void 0;
exports.allowedOrigins = allowedOrigins;
exports.runningInEmulator = runningInEmulator;
/** The production site, from Firebase Hosting's `docs` target. */
exports.PRIMARY_SITE_ORIGIN = 'https://maisum.tsintsivadigital.com';
/**
 * Origins allowed without configuration.
 *
 * The bare apex is included alongside the app subdomain because a browser sends
 * the origin it was served from, and both are plausible homes for the web
 * build.
 */
exports.DEFAULT_ALLOWED_ORIGINS = [
    exports.PRIMARY_SITE_ORIGIN,
    'https://app.maisum.tsintsivadigital.com',
    'https://admin.maisum.tsintsivadigital.com',
];
/** Local origins, allowed only when running against the emulators. */
exports.LOCAL_ORIGIN_PATTERN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/;
function parseOriginList(raw) {
    if (typeof raw !== 'string')
        return [];
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
function allowedOrigins(env, isEmulator) {
    const configured = parseOriginList(env.CORS_ALLOWED_ORIGINS);
    const origins = configured.length > 0 ? [...configured] : [...exports.DEFAULT_ALLOWED_ORIGINS];
    // Never in a deployed environment: localhost is an origin an attacker can
    // serve from a victim's own machine.
    if (isEmulator)
        origins.push(exports.LOCAL_ORIGIN_PATTERN);
    return origins;
}
/** True when the process is running under the Firebase emulator suite. */
function runningInEmulator(env) {
    return (env.FUNCTIONS_EMULATOR === 'true' ||
        typeof env.FIREBASE_AUTH_EMULATOR_HOST === 'string');
}
