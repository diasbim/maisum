"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_rate_limit_js_1 = require("./affiliate_rate_limit.js");
const POLICY = { limit: 3, windowMs: 60000 };
const WINDOW = 1788307020000; // A whole minute.
(0, node_test_1.default)('the first attempt in a window is allowed', () => {
    const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(null, POLICY, WINDOW);
    strict_1.default.equal(decision.allowed, true);
    strict_1.default.deepEqual(decision.bucket, { windowStart: WINDOW, count: 1 });
    strict_1.default.equal(decision.remaining, 2);
});
(0, node_test_1.default)('the limit is the last allowed attempt, not the first refused one', () => {
    let bucket = null;
    const allowed = [];
    for (let i = 0; i < 5; i++) {
        const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(bucket, POLICY, WINDOW + i);
        allowed.push(decision.allowed);
        bucket = decision.bucket;
    }
    strict_1.default.deepEqual(allowed, [true, true, true, false, false]);
});
(0, node_test_1.default)('a refused attempt does not push the reset further out', () => {
    // Counting refusals would turn a rate limit into a lockout: a caller
    // hammering the endpoint would never see their window end.
    const full = { windowStart: WINDOW, count: POLICY.limit };
    const first = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(full, POLICY, WINDOW + 10);
    const second = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(first.bucket, POLICY, WINDOW + 20);
    strict_1.default.equal(first.allowed, false);
    strict_1.default.equal(second.allowed, false);
    strict_1.default.equal(second.bucket.count, POLICY.limit);
});
(0, node_test_1.default)('a new window replaces the old count rather than decaying it', () => {
    const spent = { windowStart: WINDOW, count: 99 };
    const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(spent, POLICY, WINDOW + POLICY.windowMs);
    strict_1.default.equal(decision.allowed, true);
    strict_1.default.deepEqual(decision.bucket, {
        windowStart: WINDOW + POLICY.windowMs,
        count: 1,
    });
});
(0, node_test_1.default)('the window turns over on the boundary, not after it', () => {
    const spent = { windowStart: WINDOW, count: POLICY.limit };
    strict_1.default.equal((0, affiliate_rate_limit_js_1.evaluateRateLimit)(spent, POLICY, WINDOW + POLICY.windowMs - 1).allowed, false);
    strict_1.default.equal((0, affiliate_rate_limit_js_1.evaluateRateLimit)(spent, POLICY, WINDOW + POLICY.windowMs).allowed, true);
});
(0, node_test_1.default)('retryAfter counts to the end of the window', () => {
    const spent = { windowStart: WINDOW, count: POLICY.limit };
    const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(spent, POLICY, WINDOW + 15000);
    strict_1.default.equal(decision.retryAfterMs, 45000);
});
(0, node_test_1.default)('a corrupt count is treated as none, not as a negative allowance', () => {
    const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)({ windowStart: WINDOW, count: -5 }, POLICY, WINDOW);
    strict_1.default.equal(decision.allowed, true);
    strict_1.default.equal(decision.bucket.count, 1);
});
(0, node_test_1.default)('a bucket from the future is not this window', () => {
    // Clock skew between instances must not hand out a fresh allowance inside a
    // window that is already spent, nor refuse one that is not.
    const future = { windowStart: WINDOW + POLICY.windowMs, count: 99 };
    const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(future, POLICY, WINDOW);
    strict_1.default.equal(decision.allowed, true);
    strict_1.default.equal(decision.bucket.windowStart, WINDOW);
});
/* ------------------------------------------------------------- bucket ids */
(0, node_test_1.default)('the same caller in the same window shares a bucket', () => {
    const input = {
        merchantId: 'merchant-1',
        actorId: 'device-9',
        action: 'validate-code',
        windowStart: WINDOW,
    };
    strict_1.default.equal((0, affiliate_rate_limit_js_1.rateLimitBucketId)(input), (0, affiliate_rate_limit_js_1.rateLimitBucketId)(input));
});
(0, node_test_1.default)('one business cannot spend another business budget', () => {
    const base = { actorId: 'device-9', action: 'validate-code', windowStart: WINDOW };
    strict_1.default.notEqual((0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, merchantId: 'merchant-1' }), (0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, merchantId: 'merchant-2' }));
});
(0, node_test_1.default)('two callers at one business are counted apart', () => {
    const base = {
        merchantId: 'merchant-1',
        action: 'validate-code',
        windowStart: WINDOW,
    };
    strict_1.default.notEqual((0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, actorId: 'device-9' }), (0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, actorId: 'device-8' }));
});
(0, node_test_1.default)('each window gets its own document, so old ones can be swept', () => {
    const base = {
        merchantId: 'merchant-1',
        actorId: 'device-9',
        action: 'validate-code',
    };
    strict_1.default.notEqual((0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, windowStart: WINDOW }), (0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, windowStart: WINDOW + POLICY.windowMs }));
});
(0, node_test_1.default)('a bucket id carries no device id or uid', () => {
    // The id is readable in a console and printable in a log.
    const id = (0, affiliate_rate_limit_js_1.rateLimitBucketId)({
        merchantId: 'merchant-1',
        actorId: 'uid-abc-258840000001',
        action: 'validate-code',
        windowStart: WINDOW,
    });
    strict_1.default.ok(!id.includes('uid-abc'));
    strict_1.default.ok(!id.includes('840000001'));
});
(0, node_test_1.default)('the parts of a bucket id cannot be smeared into each other', () => {
    const base = { action: 'validate-code', windowStart: WINDOW };
    strict_1.default.notEqual((0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, merchantId: 'ab', actorId: 'c' }), (0, affiliate_rate_limit_js_1.rateLimitBucketId)({ ...base, merchantId: 'a', actorId: 'bc' }));
});
/* -------------------------------------------------------------- the policy */
(0, node_test_1.default)('the window helper agrees with the evaluator', () => {
    const now = WINDOW + 31234;
    strict_1.default.equal((0, affiliate_rate_limit_js_1.windowStartFor)(now, POLICY), WINDOW);
    strict_1.default.equal((0, affiliate_rate_limit_js_1.evaluateRateLimit)(null, POLICY, now).bucket.windowStart, WINDOW);
});
(0, node_test_1.default)('the shipped policy is generous for a till and useless for a search', () => {
    // A cashier validates a code once or twice per sale; this is far more than
    // any counter does. The upper bound is what matters: even at the ceiling,
    // enumerating a four-character suffix would take centuries.
    strict_1.default.ok(affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY.limit >= 10, 'too tight for a busy counter');
    const perDay = affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY.limit * (86400000 / affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY.windowMs);
    strict_1.default.ok(perDay < 100000, `${perDay}/day is fast enough to enumerate`);
});
