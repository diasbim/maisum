import assert from 'node:assert/strict';
import test from 'node:test';

import {
  evaluateRateLimit,
  rateLimitBucketId,
  VALIDATE_CODE_POLICY,
  windowStartFor,
  type RateLimitBucket,
} from './affiliate_rate_limit.js';

const POLICY = { limit: 3, windowMs: 60_000 };
const WINDOW = 1_788_307_020_000; // A whole minute.

test('the first attempt in a window is allowed', () => {
  const decision = evaluateRateLimit(null, POLICY, WINDOW);
  assert.equal(decision.allowed, true);
  assert.deepEqual(decision.bucket, { windowStart: WINDOW, count: 1 });
  assert.equal(decision.remaining, 2);
});

test('the limit is the last allowed attempt, not the first refused one', () => {
  let bucket: RateLimitBucket | null = null;
  const allowed: boolean[] = [];
  for (let i = 0; i < 5; i++) {
    const decision = evaluateRateLimit(bucket, POLICY, WINDOW + i);
    allowed.push(decision.allowed);
    bucket = decision.bucket;
  }
  assert.deepEqual(allowed, [true, true, true, false, false]);
});

test('a refused attempt does not push the reset further out', () => {
  // Counting refusals would turn a rate limit into a lockout: a caller
  // hammering the endpoint would never see their window end.
  const full: RateLimitBucket = { windowStart: WINDOW, count: POLICY.limit };
  const first = evaluateRateLimit(full, POLICY, WINDOW + 10);
  const second = evaluateRateLimit(first.bucket, POLICY, WINDOW + 20);

  assert.equal(first.allowed, false);
  assert.equal(second.allowed, false);
  assert.equal(second.bucket.count, POLICY.limit);
});

test('a new window replaces the old count rather than decaying it', () => {
  const spent: RateLimitBucket = { windowStart: WINDOW, count: 99 };
  const decision = evaluateRateLimit(spent, POLICY, WINDOW + POLICY.windowMs);

  assert.equal(decision.allowed, true);
  assert.deepEqual(decision.bucket, {
    windowStart: WINDOW + POLICY.windowMs,
    count: 1,
  });
});

test('the window turns over on the boundary, not after it', () => {
  const spent: RateLimitBucket = { windowStart: WINDOW, count: POLICY.limit };
  assert.equal(
    evaluateRateLimit(spent, POLICY, WINDOW + POLICY.windowMs - 1).allowed,
    false,
  );
  assert.equal(
    evaluateRateLimit(spent, POLICY, WINDOW + POLICY.windowMs).allowed,
    true,
  );
});

test('retryAfter counts to the end of the window', () => {
  const spent: RateLimitBucket = { windowStart: WINDOW, count: POLICY.limit };
  const decision = evaluateRateLimit(spent, POLICY, WINDOW + 15_000);
  assert.equal(decision.retryAfterMs, 45_000);
});

test('a corrupt count is treated as none, not as a negative allowance', () => {
  const decision = evaluateRateLimit(
    { windowStart: WINDOW, count: -5 },
    POLICY,
    WINDOW,
  );
  assert.equal(decision.allowed, true);
  assert.equal(decision.bucket.count, 1);
});

test('a bucket from the future is not this window', () => {
  // Clock skew between instances must not hand out a fresh allowance inside a
  // window that is already spent, nor refuse one that is not.
  const future: RateLimitBucket = { windowStart: WINDOW + POLICY.windowMs, count: 99 };
  const decision = evaluateRateLimit(future, POLICY, WINDOW);
  assert.equal(decision.allowed, true);
  assert.equal(decision.bucket.windowStart, WINDOW);
});

/* ------------------------------------------------------------- bucket ids */

test('the same caller in the same window shares a bucket', () => {
  const input = {
    merchantId: 'merchant-1',
    actorId: 'device-9',
    action: 'validate-code',
    windowStart: WINDOW,
  };
  assert.equal(rateLimitBucketId(input), rateLimitBucketId(input));
});

test('one business cannot spend another business budget', () => {
  const base = { actorId: 'device-9', action: 'validate-code', windowStart: WINDOW };
  assert.notEqual(
    rateLimitBucketId({ ...base, merchantId: 'merchant-1' }),
    rateLimitBucketId({ ...base, merchantId: 'merchant-2' }),
  );
});

test('two callers at one business are counted apart', () => {
  const base = {
    merchantId: 'merchant-1',
    action: 'validate-code',
    windowStart: WINDOW,
  };
  assert.notEqual(
    rateLimitBucketId({ ...base, actorId: 'device-9' }),
    rateLimitBucketId({ ...base, actorId: 'device-8' }),
  );
});

test('each window gets its own document, so old ones can be swept', () => {
  const base = {
    merchantId: 'merchant-1',
    actorId: 'device-9',
    action: 'validate-code',
  };
  assert.notEqual(
    rateLimitBucketId({ ...base, windowStart: WINDOW }),
    rateLimitBucketId({ ...base, windowStart: WINDOW + POLICY.windowMs }),
  );
});

test('a bucket id carries no device id or uid', () => {
  // The id is readable in a console and printable in a log.
  const id = rateLimitBucketId({
    merchantId: 'merchant-1',
    actorId: 'uid-abc-258840000001',
    action: 'validate-code',
    windowStart: WINDOW,
  });
  assert.ok(!id.includes('uid-abc'));
  assert.ok(!id.includes('840000001'));
});

test('the parts of a bucket id cannot be smeared into each other', () => {
  const base = { action: 'validate-code', windowStart: WINDOW };
  assert.notEqual(
    rateLimitBucketId({ ...base, merchantId: 'ab', actorId: 'c' }),
    rateLimitBucketId({ ...base, merchantId: 'a', actorId: 'bc' }),
  );
});

/* -------------------------------------------------------------- the policy */

test('the window helper agrees with the evaluator', () => {
  const now = WINDOW + 31_234;
  assert.equal(windowStartFor(now, POLICY), WINDOW);
  assert.equal(evaluateRateLimit(null, POLICY, now).bucket.windowStart, WINDOW);
});

test('the shipped policy is generous for a till and useless for a search', () => {
  // A cashier validates a code once or twice per sale; this is far more than
  // any counter does. The upper bound is what matters: even at the ceiling,
  // enumerating a four-character suffix would take centuries.
  assert.ok(VALIDATE_CODE_POLICY.limit >= 10, 'too tight for a busy counter');
  const perDay = VALIDATE_CODE_POLICY.limit * (86_400_000 / VALIDATE_CODE_POLICY.windowMs);
  assert.ok(perDay < 100_000, `${perDay}/day is fast enough to enumerate`);
});
