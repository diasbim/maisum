import { createHash } from 'crypto';

/**
 * Rate limiting for code validation.
 *
 * `validate-code` is the one referral endpoint a till can call in a loop, and
 * the thing it leaks is existence: without a limit, someone with a valid
 * session can walk the code space and learn which strings are real. So the
 * limit is not about load. It is about making enumeration slow enough to be
 * useless, and the 429 says nothing about whether the code existed.
 *
 * The state lives in Firestore rather than in memory because Cloud Functions
 * run as many instances and an in-process counter limits one instance while the
 * caller is being served by ten. Adding a rate-limiter dependency would not fix
 * that either — the distribution is the whole problem, and Firestore is already
 * the shared store.
 *
 * Fixed windows, not a sliding log. A sliding window would need every timestamp
 * kept per caller; a fixed window needs one integer, and the worst case it
 * admits — a burst across a boundary — is two windows' worth, which is still
 * far too slow to enumerate anything.
 */

export type RateLimitPolicy = {
  /** How many attempts are allowed inside one window. */
  limit: number;
  windowMs: number;
};

/**
 * Generous for a real till and useless for a search.
 *
 * A cashier validates a code once or twice per sale. Thirty a minute is far
 * more than any counter does and still caps a determined caller at well under
 * fifty thousand a day — against an alphabet of 31 characters over four
 * positions, that is hundreds of years per code prefix.
 */
export const VALIDATE_CODE_POLICY: RateLimitPolicy = {
  limit: 30,
  windowMs: 60_000,
};

export type RateLimitBucket = {
  windowStart: number;
  count: number;
};

export type RateLimitDecision = {
  allowed: boolean;
  /** What to write back. Always written, so a new window replaces an old one. */
  bucket: RateLimitBucket;
  /** How many more attempts this window admits, after this one. */
  remaining: number;
  /** When the caller may try again. Only meaningful when refused. */
  retryAfterMs: number;
};

/**
 * The whole decision, as a function of the stored bucket and the clock.
 *
 * Pure on purpose: the Firestore transaction around it does nothing but read,
 * call this, and write. That is what makes the policy testable without an
 * emulator, and what keeps "is this caller over the limit?" from being spread
 * across a transaction body.
 */
export function evaluateRateLimit(
  existing: RateLimitBucket | null,
  policy: RateLimitPolicy,
  now: number,
): RateLimitDecision {
  const windowStart = Math.floor(now / policy.windowMs) * policy.windowMs;

  // A bucket from an earlier window is not decayed, it is replaced: the whole
  // point of a fixed window is that the past does not carry over.
  const inWindow =
    existing !== null && existing.windowStart === windowStart
      ? Math.max(0, existing.count)
      : 0;

  const retryAfterMs = windowStart + policy.windowMs - now;

  if (inWindow >= policy.limit) {
    return {
      allowed: false,
      // The count is not incremented by a refused attempt. Otherwise a caller
      // who keeps hammering pushes their own reset further out with every try,
      // which turns a rate limit into a lockout.
      bucket: { windowStart, count: inWindow },
      remaining: 0,
      retryAfterMs,
    };
  }

  const count = inWindow + 1;
  return {
    allowed: true,
    bucket: { windowStart, count },
    remaining: policy.limit - count,
    retryAfterMs,
  };
}

/**
 * The document one caller's attempts are counted against.
 *
 * Scoped to the business as well as the caller, so one busy shop cannot spend
 * another's budget, and hashed so that a bucket id — which is readable in a
 * Firestore console and printable in a log — carries no device id or uid.
 *
 * The window is part of the id, which means an expired bucket is never read
 * again and can be swept by a TTL policy rather than by a cleanup job.
 */
export function rateLimitBucketId(input: {
  merchantId: string;
  /** The till, the device, or the signed-in uid — whatever identifies a caller. */
  actorId: string;
  action: string;
  windowStart: number;
}): string {
  const digest = createHash('sha256')
    .update(
      [input.merchantId, input.actorId, input.action, String(input.windowStart)].join(
        '\u001f',
      ),
    )
    .digest('hex')
    .slice(0, 40);
  return `rl_${digest}`;
}

/**
 * The window a moment belongs to. Exported so a caller can build the bucket id
 * and read the document before opening a transaction.
 */
export function windowStartFor(now: number, policy: RateLimitPolicy): number {
  return Math.floor(now / policy.windowMs) * policy.windowMs;
}
