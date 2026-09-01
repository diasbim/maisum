/**
 * Cookie constants with no dependencies, so `middleware.ts` can import them
 * without pulling `firebase-admin` into the Edge runtime.
 */

/**
 * Firebase ID token, held httpOnly so no script on the page can read it.
 *
 * ID tokens last an hour; the client refreshes this cookie through
 * `onIdTokenChanged`, so nothing here deals with renewal.
 */
export const SESSION_COOKIE = 'maisum_admin_session';

/** Slightly under the one-hour ID token lifetime, so a stale cookie expires. */
export const SESSION_MAX_AGE_SECONDS = 55 * 60;
