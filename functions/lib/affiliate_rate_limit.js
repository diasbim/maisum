"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.VALIDATE_CODE_POLICY = void 0;
exports.evaluateRateLimit = evaluateRateLimit;
exports.rateLimitBucketId = rateLimitBucketId;
exports.windowStartFor = windowStartFor;
const crypto_1 = require("crypto");
/**
 * Generous for a real till and useless for a search.
 *
 * A cashier validates a code once or twice per sale. Thirty a minute is far
 * more than any counter does and still caps a determined caller at well under
 * fifty thousand a day — against an alphabet of 31 characters over four
 * positions, that is hundreds of years per code prefix.
 */
exports.VALIDATE_CODE_POLICY = {
    limit: 30,
    windowMs: 60000,
};
/**
 * The whole decision, as a function of the stored bucket and the clock.
 *
 * Pure on purpose: the Firestore transaction around it does nothing but read,
 * call this, and write. That is what makes the policy testable without an
 * emulator, and what keeps "is this caller over the limit?" from being spread
 * across a transaction body.
 */
function evaluateRateLimit(existing, policy, now) {
    const windowStart = Math.floor(now / policy.windowMs) * policy.windowMs;
    // A bucket from an earlier window is not decayed, it is replaced: the whole
    // point of a fixed window is that the past does not carry over.
    const inWindow = existing !== null && existing.windowStart === windowStart
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
function rateLimitBucketId(input) {
    const digest = (0, crypto_1.createHash)('sha256')
        .update([input.merchantId, input.actorId, input.action, String(input.windowStart)].join('\u001f'))
        .digest('hex')
        .slice(0, 40);
    return `rl_${digest}`;
}
/**
 * The window a moment belongs to. Exported so a caller can build the bucket id
 * and read the document before opening a transaction.
 */
function windowStartFor(now, policy) {
    return Math.floor(now / policy.windowMs) * policy.windowMs;
}
