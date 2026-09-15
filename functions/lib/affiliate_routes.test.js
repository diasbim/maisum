"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_routes_js_1 = require("./affiliate_routes.js");
const affiliate_api_contracts_js_1 = require("./affiliate_api_contracts.js");
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_store_js_1 = require("./affiliate_store.js");
const affiliate_rate_limit_js_1 = require("./affiliate_rate_limit.js");
/**
 * The referral API's guards, checked two ways.
 *
 * The first is by running the handlers. `registerAffiliateRoutes` takes its
 * routers and every authority it uses as arguments, so a fake router collects
 * the handlers and a fake request walks them — which is how "a cashier cannot
 * approve a reward" becomes an assertion rather than a claim. Everything that
 * refuses does so before Firestore is touched, which is itself the property
 * worth having: authorization is not something the data layer is asked about.
 *
 * The second is by reading the source. Some of what matters here is not
 * observable from one call — that every mutation writes to the audit trail,
 * that no reward decision reads an amount from the body, that events are only
 * ever created and never updated. Those are properties of how the code is
 * written, and a test that reads it is the only kind that notices them going
 * missing.
 *
 * `merchant_routes.test.ts` reads this file too, and holds these handlers to
 * the same business-resolution rules as the ones written inside index.ts.
 */
const ROUTES_SOURCE = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_routes.ts'), 'utf8');
const STORE_SOURCE = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_store.ts'), 'utf8');
function fakeRouter(sink, _name) {
    const add = (method) => (route, handler) => {
        sink.push({ method, route, handler });
    };
    return {
        get: add('get'),
        post: add('post'),
        put: add('put'),
        patch: add('patch'),
        delete: add('delete'),
    };
}
function fakeResponse(captured) {
    const res = {
        status(code) {
            captured.status = code;
            return res;
        },
        json(body) {
            captured.body = body;
            return res;
        },
        setHeader(key, value) {
            captured.headers[key] = value;
        },
    };
    return res;
}
function harness(overrides = {}) {
    const merchant = [];
    const admin = [];
    const captured = { status: 200, body: undefined, headers: {}, serverErrors: [] };
    const calls = { requireBusiness: 0, ownerChecks: 0 };
    const business = overrides.business === undefined ? { id: 'm1', name: 'Loja' } : overrides.business;
    const deps = {
        merchantRouter: fakeRouter(merchant, 'merchant'),
        adminRouter: fakeRouter(admin, 'admin'),
        requireBusiness: async (_req, res) => {
            calls.requireBusiness++;
            if (business === null) {
                // The real one answers the request itself and returns null.
                res
                    .status(403)
                    .json({ success: false, message: 'denied' });
                return null;
            }
            return business;
        },
        isOwnerOrAdminRequest: () => {
            calls.ownerChecks++;
            return overrides.isOwnerOrAdminRequest ? overrides.isOwnerOrAdminRequest({}) : true;
        },
        auditActorFrom: () => ({ appUserId: 'u1', firebaseUid: 'uid1', role: 'OWNER' }),
        respondServerError: (res, operation) => {
            captured.serverErrors.push(operation);
            return res
                .status(500)
                .json({ success: false, message: 'Server error' });
        },
        normalizePhone: (raw) => raw === '841234567' || raw === '+258841234567' ? '+258841234567' : null,
        affiliateIdForPhone: () => 'af_test',
        now: () => 1800000000000,
    };
    (0, affiliate_routes_js_1.registerAffiliateRoutes)(deps);
    const call = async (routes, method, route, req = {}) => {
        const found = routes.find((entry) => entry.method === method && entry.route === route);
        strict_1.default.ok(found, `${method.toUpperCase()} ${route} is not registered`);
        captured.status = 200;
        captured.body = undefined;
        await found.handler({ params: {}, query: {}, body: {}, appUserId: 'u1', ...req }, fakeResponse(captured));
    };
    return { merchant, admin, captured, calls, call };
}
function body(captured) {
    return (captured.body ?? {});
}
/* ------------------------------------------------------------ route surface */
const MERCHANT_ROUTES = [
    ['post', '/affiliates'],
    ['get', '/affiliates'],
    ['get', '/affiliates/metrics'],
    ['get', '/affiliates/:affiliateId'],
    ['get', '/affiliates/:affiliateId/metrics'],
    ['patch', '/affiliates/:affiliateId'],
    ['post', '/affiliates/:affiliateId/activate'],
    ['post', '/affiliates/:affiliateId/deactivate'],
    ['post', '/affiliate-codes'],
    ['get', '/affiliate-codes'],
    ['get', '/affiliate-codes/:codeId'],
    ['patch', '/affiliate-codes/:codeId'],
    ['post', '/affiliate-codes/:codeId/enable'],
    ['post', '/affiliate-codes/:codeId/disable'],
    ['post', '/referrals/validate-code'],
    ['get', '/referrals'],
    ['get', '/referrals/:attributionId'],
    ['get', '/affiliate-rewards'],
    ['post', '/affiliate-rewards/:rewardId/approve'],
    ['post', '/affiliate-rewards/:rewardId/cancel'],
];
const ADMIN_ROUTES = [
    ['get', '/affiliates'],
    ['post', '/affiliates'],
    ['get', '/affiliates/:affiliateId'],
    ['patch', '/affiliates/:affiliateId'],
    ['post', '/affiliates/:affiliateId/status'],
    ['post', '/affiliates/:affiliateId/merchants/:merchantId'],
    ['delete', '/affiliates/:affiliateId/merchants/:merchantId'],
    ['get', '/merchants/:merchantId/affiliates'],
    ['get', '/merchants/:merchantId/affiliate-rewards'],
    ['get', '/merchants/:merchantId/affiliate-metrics'],
];
(0, node_test_1.default)('every planned merchant route is registered, and nothing else is', () => {
    const { merchant } = harness();
    const actual = merchant.map((entry) => `${entry.method} ${entry.route}`).sort();
    const expected = MERCHANT_ROUTES.map(([method, route]) => `${method} ${route}`).sort();
    strict_1.default.deepEqual(actual, expected);
});
(0, node_test_1.default)('every planned admin route is registered, and nothing else is', () => {
    const { admin } = harness();
    const actual = admin.map((entry) => `${entry.method} ${entry.route}`).sort();
    const expected = ADMIN_ROUTES.map(([method, route]) => `${method} ${route}`).sort();
    strict_1.default.deepEqual(actual, expected);
});
(0, node_test_1.default)('the metrics route is declared before the one that would swallow it', () => {
    // Express matches in registration order, so `/affiliates/:affiliateId`
    // declared first would read "metrics" as an affiliate id and answer 404.
    const { merchant } = harness();
    const metrics = merchant.findIndex((entry) => entry.route === '/affiliates/metrics');
    const byId = merchant.findIndex((entry) => entry.method === 'get' && entry.route === '/affiliates/:affiliateId');
    strict_1.default.ok(metrics >= 0 && byId >= 0);
    strict_1.default.ok(metrics < byId, 'the id route would capture /affiliates/metrics');
});
/* ---------------------------------------------------------------- isolation */
(0, node_test_1.default)('a denied business stops every merchant handler before it reads anything', async () => {
    for (const [method, route] of MERCHANT_ROUTES) {
        const { merchant, captured, call, calls } = harness({ business: null });
        await call(merchant, method, route);
        strict_1.default.equal(calls.requireBusiness, 1, `${route} did not resolve a business`);
        // `requireBusiness` answered with its own 403; the handler added nothing.
        strict_1.default.equal(captured.status, 403, `${route} continued past the denial`);
        strict_1.default.deepEqual(captured.serverErrors, [], `${route} fell through to a 500`);
    }
});
(0, node_test_1.default)('the business is resolved before the owner check, never after', async () => {
    const { merchant, call, calls } = harness({
        business: null,
        isOwnerOrAdminRequest: () => false,
    });
    await call(merchant, 'post', '/affiliates');
    strict_1.default.equal(calls.requireBusiness, 1);
    // A handler that asked "are you an owner?" first would leak that a caller is
    // not an owner of a business they have no access to at all.
    strict_1.default.equal(calls.ownerChecks, 0);
});
/* --------------------------------------------------------------------- RBAC */
const OWNER_ONLY = [
    ['post', '/affiliates'],
    ['patch', '/affiliates/:affiliateId'],
    ['post', '/affiliates/:affiliateId/activate'],
    ['post', '/affiliates/:affiliateId/deactivate'],
    ['post', '/affiliate-codes'],
    ['patch', '/affiliate-codes/:codeId'],
    ['post', '/affiliate-codes/:codeId/enable'],
    ['post', '/affiliate-codes/:codeId/disable'],
    ['post', '/affiliate-rewards/:rewardId/approve'],
    ['post', '/affiliate-rewards/:rewardId/cancel'],
];
(0, node_test_1.default)('a cashier cannot change an affiliate, a code or a reward', async () => {
    for (const [method, route] of OWNER_ONLY) {
        const { merchant, captured, call } = harness({
            isOwnerOrAdminRequest: () => false,
        });
        await call(merchant, method, route, {
            params: { affiliateId: 'af_1', codeId: 'ac_1', rewardId: 'ar_1' },
            body: { name: 'Ana', phone: '841234567' },
        });
        strict_1.default.equal(captured.status, 403, `${method} ${route} let a non-owner through`);
        strict_1.default.equal(body(captured).code, 'forbidden_role');
        // Refused before any storage call: the 500 path was never reached.
        strict_1.default.deepEqual(captured.serverErrors, []);
    }
});
(0, node_test_1.default)('every mutating merchant route is owner-only, except validating a code', async () => {
    const { merchant } = harness();
    const mutating = merchant
        .filter((entry) => entry.method !== 'get')
        .map((entry) => `${entry.method} ${entry.route}`)
        .sort();
    const guarded = OWNER_ONLY.map(([method, route]) => `${method} ${route}`).sort();
    strict_1.default.deepEqual(mutating, [...guarded, 'post /referrals/validate-code'].sort());
});
(0, node_test_1.default)('reading is open to any member of the business', async () => {
    // A read refused for a cashier would make the affiliate list useless at the
    // till. These reach storage instead, which has no Firebase app in a test —
    // that they get there at all is the point.
    for (const [method, route] of MERCHANT_ROUTES) {
        if (method !== 'get')
            continue;
        const { merchant, captured, call } = harness({
            isOwnerOrAdminRequest: () => false,
        });
        await call(merchant, method, route, {
            params: { affiliateId: 'af_1', codeId: 'ac_1', rewardId: 'ar_1', attributionId: 'aa_1' },
        });
        strict_1.default.notEqual(captured.status, 403, `${route} refused a cashier`);
    }
});
(0, node_test_1.default)('validating a code is open to any member of the business', async () => {
    const { merchant, captured, call } = harness({ isOwnerOrAdminRequest: () => false });
    await call(merchant, 'post', '/referrals/validate-code', {
        body: { code: 'AFI-ANA-7K2P' },
    });
    strict_1.default.notEqual(captured.status, 403);
});
/* --------------------------------------------------------- field validation */
(0, node_test_1.default)('a create refuses each bad field with its own stable code', async () => {
    const cases = [
        [{}, 'invalid_name'],
        [{ name: 'A' }, 'invalid_name'],
        [{ name: 'Ana', phone: '12345' }, 'invalid_phone'],
        [{ name: 'Ana', phone: '841234567' }, 'invalid_benefit_type'],
        [
            { name: 'Ana', phone: '841234567', benefit_type: 'PERCENTAGE', benefit_value: 80 },
            'invalid_percentage',
        ],
        [
            { name: 'Ana', phone: '841234567', benefit_type: 'POINTS', benefit_value: 0 },
            'invalid_benefit_value',
        ],
        [
            {
                name: 'Ana',
                phone: '841234567',
                benefit_type: 'POINTS',
                benefit_value: 100,
                usage_limit: 0,
            },
            'invalid_usage_limit',
        ],
        [
            {
                name: 'Ana',
                phone: '841234567',
                benefit_type: 'POINTS',
                benefit_value: 100,
                starts_at: 1800000000000,
                expires_at: 1700000000000,
            },
            'invalid_dates',
        ],
    ];
    for (const [payload, code] of cases) {
        const { merchant, captured, call } = harness();
        await call(merchant, 'post', '/affiliates', { body: payload });
        strict_1.default.equal(captured.status, 400, `${JSON.stringify(payload)} was not refused`);
        strict_1.default.equal(body(captured).code, code);
        strict_1.default.equal(typeof body(captured).message, 'string');
        // Nothing reached storage, so nothing half-created an affiliate.
        strict_1.default.deepEqual(captured.serverErrors, []);
    }
});
(0, node_test_1.default)('a body that is not an object is refused before any field is read', async () => {
    const { merchant, captured, call } = harness();
    await call(merchant, 'post', '/affiliates', { body: 'name=Ana' });
    strict_1.default.equal(captured.status, 400);
    strict_1.default.equal(body(captured).code, 'invalid_body');
});
(0, node_test_1.default)('validate-code refuses a missing or implausible code', async () => {
    for (const payload of [{}, { code: 'ab' }, { code: 42 }]) {
        const { merchant, captured, call } = harness();
        await call(merchant, 'post', '/referrals/validate-code', { body: payload });
        // The rate limiter is reached first and has no Firestore behind it here,
        // so either the limiter's 500 or the field refusal is acceptable — what is
        // not acceptable is a 200 with a validation result.
        strict_1.default.notEqual(captured.status, 200);
    }
});
/* ------------------------------------------------------------- rate limiting */
(0, node_test_1.default)('the validate-code budget refuses once the window is spent', () => {
    const now = 1800000000000;
    let bucket = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(null, affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY, now).bucket;
    for (let attempt = 2; attempt <= affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY.limit; attempt++) {
        const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(bucket, affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY, now);
        strict_1.default.equal(decision.allowed, true, `attempt ${attempt} was refused early`);
        bucket = decision.bucket;
    }
    const refused = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(bucket, affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY, now);
    strict_1.default.equal(refused.allowed, false);
    strict_1.default.equal(refused.remaining, 0);
    strict_1.default.ok(refused.retryAfterMs > 0);
});
(0, node_test_1.default)('validate-code spends the budget before it reads the body', () => {
    const handler = handlerSource('merchantRouter', 'post', '/referrals/validate-code');
    const limitAt = handler.indexOf('consumeRateLimit(');
    const bodyAt = handler.indexOf('parseBodyObject(');
    strict_1.default.ok(limitAt > 0, 'validate-code no longer rate limits');
    strict_1.default.ok(bodyAt > 0);
    strict_1.default.ok(limitAt < bodyAt, 'a malformed body now costs nothing, which makes the limit walkable');
    strict_1.default.ok(handler.includes('rateLimitedResponse('), 'the 429 is no longer the shared, reason-free refusal');
});
(0, node_test_1.default)('no other route spends a rate-limit budget', () => {
    // A limit on a management route would lock an owner out of their own list.
    const occurrences = ROUTES_SOURCE.split('consumeRateLimit({').length - 1;
    strict_1.default.equal(occurrences, 1, 'consumeRateLimit is used somewhere new');
});
/* ------------------------------------------------- source-level obligations */
/** The body of one registered handler, up to the next registration. */
function handlerSource(router, method, route) {
    const escaped = route.replace(/[/:\-]/g, (c) => `\\${c}`);
    const marker = new RegExp(`${router}\\.${method}\\(\\s*\\n?\\s*'${escaped}'`);
    const match = marker.exec(ROUTES_SOURCE);
    strict_1.default.ok(match, `${router}.${method} ${route} is not declared`);
    const start = match.index;
    const next = /(?:merchantRouter|adminRouter)\.(?:get|post|put|patch|delete)\(/.exec(ROUTES_SOURCE.slice(start + match[0].length));
    const end = next === null
        ? ROUTES_SOURCE.length
        : start + match[0].length + (next.index ?? 0);
    return ROUTES_SOURCE.slice(start, end);
}
(0, node_test_1.default)('every change to a code, a status or a reward reaches the audit trail', () => {
    const audited = [
        ['merchantRouter', 'post', '/affiliates'],
        ['merchantRouter', 'patch', '/affiliates/:affiliateId'],
        ['merchantRouter', 'post', '/affiliates/:affiliateId/activate'],
        ['merchantRouter', 'post', '/affiliates/:affiliateId/deactivate'],
        ['merchantRouter', 'post', '/affiliate-codes'],
        ['merchantRouter', 'patch', '/affiliate-codes/:codeId'],
        ['merchantRouter', 'post', '/affiliate-codes/:codeId/enable'],
        ['merchantRouter', 'post', '/affiliate-codes/:codeId/disable'],
        ['merchantRouter', 'post', '/affiliate-rewards/:rewardId/approve'],
        ['merchantRouter', 'post', '/affiliate-rewards/:rewardId/cancel'],
        ['adminRouter', 'post', '/affiliates'],
        ['adminRouter', 'patch', '/affiliates/:affiliateId'],
        ['adminRouter', 'post', '/affiliates/:affiliateId/status'],
        ['adminRouter', 'post', '/affiliates/:affiliateId/merchants/:merchantId'],
        ['adminRouter', 'delete', '/affiliates/:affiliateId/merchants/:merchantId'],
    ];
    for (const [router, method, route] of audited) {
        strict_1.default.ok(handlerSource(router, method, route).includes('recordAuditEvent('), `${router}.${method} ${route} changes something without recording who did it`);
    }
});
(0, node_test_1.default)('the facts a merchant sees on the metrics screen are written as events', () => {
    for (const route of [
        '/affiliates',
        '/affiliate-codes',
        '/referrals/validate-code',
        '/affiliate-rewards/:rewardId/approve',
        '/affiliate-rewards/:rewardId/cancel',
    ]) {
        strict_1.default.ok(handlerSource('merchantRouter', 'post', route).includes('appendAffiliateEvent('), `${route} writes no event, so the history and the metrics will not agree`);
    }
});
(0, node_test_1.default)('a rejected validation is recorded as plainly as an accepted one', () => {
    const handler = handlerSource('merchantRouter', 'post', '/referrals/validate-code');
    strict_1.default.ok(handler.includes("'REFERRAL_CODE_VALIDATED'"));
    strict_1.default.ok(handler.includes("'REFERRAL_REJECTED'"));
    strict_1.default.ok(handler.includes('dedupeKey'), 'replays would be counted as attempts');
});
(0, node_test_1.default)('a reward decision reads no amount and no ownership from the request', () => {
    for (const route of [
        '/affiliate-rewards/:rewardId/approve',
        '/affiliate-rewards/:rewardId/cancel',
    ]) {
        const handler = handlerSource('merchantRouter', 'post', route);
        strict_1.default.ok(!handler.includes('parseBodyObject('), `${route} reads a request body; an approval must carry no value`);
        strict_1.default.ok(!/req\.body|payload\./.test(handler), `${route} reads a field the caller chose`);
        // Everything it reports comes back out of the stored reward.
        strict_1.default.ok(handler.includes('change.after.value'));
        strict_1.default.ok(handler.includes('change.after.affiliate_id'));
    }
});
(0, node_test_1.default)('no handler puts a phone number anywhere but a mask', () => {
    const allowed = [
        // The import block, where the names appear on their own or on one line.
        /^\s*(parsePhone|maskPhone),$/,
        /^import \{ maskPhone \}/,
        /function affiliateIdFor\(/,
        /affiliateIdFor\(deps, phoneE164\)/,
        /const phoneE164 = parsePhone\(/,
        /affiliateIdForPhone/,
        /maskPhone\(phoneE164\)/,
        /^\s*phoneE164,$/,
        /customerPhoneE164/,
        /payload\.customer_phone/,
        /had_customer_phone:/,
        /normalizePhone/,
    ];
    for (const rawLine of ROUTES_SOURCE.split('\n')) {
        // Windows checkouts carry the carriage return into the line.
        const raw = rawLine.replace(/\r$/, '');
        const line = raw.trim();
        if (line.startsWith('*') || line.startsWith('//') || line.startsWith('/*'))
            continue;
        if (!/phone/i.test(line))
            continue;
        strict_1.default.ok(allowed.some((pattern) => pattern.test(raw)), `a phone is used in an unreviewed way: ${line}`);
    }
});
(0, node_test_1.default)('admin routes for one business check that the business exists', () => {
    for (const route of [
        '/merchants/:merchantId/affiliates',
        '/merchants/:merchantId/affiliate-rewards',
        '/merchants/:merchantId/affiliate-metrics',
        '/affiliates/:affiliateId/merchants/:merchantId',
    ]) {
        strict_1.default.ok(handlerSource('adminRouter', route.startsWith('/merchants') ? 'get' : 'post', route).includes('merchantExists('), `${route} acts on a business without checking it is one`);
    }
    // The link and unlink handlers share a path, so the loop above only reaches
    // the first of them; both are meant to check.
    strict_1.default.equal(ROUTES_SOURCE.split('await merchantExists(').length - 1, 5, 'an admin route acting on one business no longer checks it exists');
});
(0, node_test_1.default)('every merchant-scoped store read is scoped by the merchant it was given', () => {
    // The path already scopes a subcollection; the filter is what keeps a
    // collection-group query written later from reading every business at once.
    const scoped = STORE_SOURCE.split("where('merchant_id', '==', merchantId)").length - 1;
    strict_1.default.ok(scoped >= 1, 'the scoped read helper no longer filters by merchant');
    strict_1.default.ok(STORE_SOURCE.includes('dto.merchant_id === merchantId') ||
        STORE_SOURCE.includes('before.merchant_id !== input.merchantId'), 'a row whose own merchant id disagrees with its path is now trusted');
});
(0, node_test_1.default)('affiliate events are only ever created, never updated or removed', () => {
    const eventsUses = [...STORE_SOURCE.matchAll(/\.events\([^)]*\)\s*([\s\S]{0,40})/g)];
    strict_1.default.ok(eventsUses.length >= 2, 'the events collection is no longer used here');
    for (const use of eventsUses) {
        strict_1.default.ok(!/\.(update|delete|set)\(/.test(use[1]), `an event is written with something other than create: ${use[1].trim()}`);
    }
    strict_1.default.ok(STORE_SOURCE.includes('await ref.create({'), 'appendAffiliateEvent no longer uses create, so an id clash would overwrite history');
});
(0, node_test_1.default)('identity, code and reward changes each happen in a transaction', () => {
    for (const fragment of [
        'export async function createAffiliateForMerchant',
        'export async function transitionReward',
        'export async function setLinkStatus',
        'export async function updateCode',
    ]) {
        const at = STORE_SOURCE.indexOf(fragment);
        strict_1.default.ok(at > 0, `${fragment} is gone`);
        const body = STORE_SOURCE.slice(at, at + 1200);
        strict_1.default.ok(body.includes('runTransaction('), `${fragment} no longer reads and writes atomically`);
    }
    // Claiming a code is a transaction too, and it is the one already written.
    strict_1.default.ok(STORE_SOURCE.includes('claimAffiliateCode('));
});
(0, node_test_1.default)('a merchant rename stays on its business link', () => {
    const handler = handlerSource('merchantRouter', 'patch', '/affiliates/:affiliateId');
    strict_1.default.ok(handler.includes('updateMerchantAffiliateName('));
    strict_1.default.ok(!handler.includes('updateAffiliateName('));
    const at = STORE_SOURCE.indexOf('export async function updateMerchantAffiliateName');
    strict_1.default.ok(at > 0, 'the merchant-scoped rename helper is gone');
    const body = STORE_SOURCE.slice(at, at + 2200);
    strict_1.default.match(body, /transaction\.set\(\s*linkRef,/);
    strict_1.default.ok(!/transaction\.set\(\s*identityRef,/.test(body), 'a merchant rename writes the platform-wide identity');
});
(0, node_test_1.default)('a failed code claim rolls back against the latest shared identity', () => {
    const at = STORE_SOURCE.indexOf('async function undoAffiliateClaim');
    strict_1.default.ok(at > 0, 'the affiliate claim rollback is gone');
    const body = STORE_SOURCE.slice(at, at + 2200);
    strict_1.default.ok(body.includes('runTransaction('));
    strict_1.default.ok(body.includes('transaction.get(identityRef)'));
    strict_1.default.ok(body.includes('merchantIds.length === 0'));
    strict_1.default.ok(body.includes('arrayRemove(input.merchantId)'));
});
(0, node_test_1.default)('a preview with no sale describes the code, not a discount of zero', () => {
    const at = STORE_SOURCE.indexOf('function advisoryBenefit');
    strict_1.default.ok(at > 0, 'the advisory benefit is no longer computed in one place');
    const body = STORE_SOURCE.slice(at, at + 1400);
    strict_1.default.ok(body.includes('calculateBenefit(code, saleAmount)'), 'a preview with an amount no longer runs the real calculation');
    strict_1.default.ok(/% de desconto`/.test(body) && !/calculateBenefit\(code, 0\)/.test(body), 'a percentage with no sale is rendered against an amount of zero');
});
(0, node_test_1.default)('code validation uses the name this business assigned to the affiliate', () => {
    const at = STORE_SOURCE.indexOf('export async function validateReferralCode');
    strict_1.default.ok(at > 0, 'the referral validation store function is gone');
    const body = STORE_SOURCE.slice(at, at + 5200);
    strict_1.default.ok(body.includes('affiliateWithLinkName(affiliate, linkData ?? {})'), 'validation bypasses the merchant-scoped affiliate name');
    strict_1.default.ok(body.includes('affiliateName: merchantAffiliate.first_name'), 'the till receives the platform-wide name');
});
(0, node_test_1.default)('a code that belongs to another business is not even fetched', () => {
    const at = STORE_SOURCE.indexOf('export async function validateReferralCode');
    strict_1.default.ok(at > 0);
    const body = STORE_SOURCE.slice(at, at + 2000);
    const lookupAt = body.indexOf('resolveCodeLookup(');
    const guardAt = body.indexOf('lookup.merchantId !== input.merchantId');
    const fetchAt = body.indexOf('affiliateRefs.code(');
    strict_1.default.ok(lookupAt > 0 && guardAt > lookupAt, 'the lookup is no longer checked');
    strict_1.default.ok(guardAt < fetchAt, 'a code from another business is read before it is refused');
    strict_1.default.ok(body.includes("reason: 'CODE_NOT_FOUND'"), 'a cross-business code answers something other than not found');
});
(0, node_test_1.default)('every message this API can raise is actually reachable from a route', () => {
    // A message nobody raises is a promise to the reader that is not kept, and
    // the next person copies it into a new route expecting it to mean something.
    const sources = ROUTES_SOURCE +
        STORE_SOURCE +
        (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_api_contracts.ts'), 'utf8').replace(/export const AFFILIATE_API_MESSAGE[\s\S]*?\n} as const;/, '');
    for (const key of Object.keys(affiliate_api_contracts_js_1.AFFILIATE_API_MESSAGE)) {
        if (key === 'forbidden_role')
            continue; // raised by ownerOnlyError()
        strict_1.default.ok(sources.includes(`'${key}'`), `${key} is declared but never raised`);
    }
    strict_1.default.ok(ROUTES_SOURCE.includes('ownerOnlyError()'));
});
/* ------------------------------------------------------------ business config */
(0, node_test_1.default)('affiliate settings fall back to the defaults the plan fixes', () => {
    const config = (0, affiliate_store_js_1.affiliateConfigFrom)({});
    strict_1.default.deepEqual(config, affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG);
});
(0, node_test_1.default)('affiliate settings are read from the business document, not guessed', () => {
    const config = (0, affiliate_store_js_1.affiliateConfigFrom)({
        affiliate_config: {
            enabled: true,
            first_sale_reward_points: 100,
            return_reward_enabled: true,
            return_reward_points: 50,
            return_window_days: 45,
            reward_approval_required: false,
            notifications_enabled: false,
        },
    });
    strict_1.default.equal(config.enabled, true);
    strict_1.default.equal(config.firstSaleRewardPoints, 100);
    strict_1.default.equal(config.returnRewardEnabled, true);
    strict_1.default.equal(config.returnRewardPoints, 50);
    strict_1.default.equal(config.returnWindowDays, 45);
    strict_1.default.equal(config.rewardApprovalRequired, false);
    strict_1.default.equal(config.notificationsEnabled, false);
});
(0, node_test_1.default)('an unreadable setting keeps the safe default rather than becoming zero', () => {
    const config = (0, affiliate_store_js_1.affiliateConfigFrom)({
        affiliate_config: {
            enabled: 'yes',
            first_sale_reward_points: -5,
            reward_approval_required: 'no',
            return_window_days: 'thirty',
        },
    });
    // A truthy string must not turn the feature on, and "approval required"
    // must not fall to false because somebody stored the word "no".
    strict_1.default.equal(config.enabled, false);
    strict_1.default.equal(config.firstSaleRewardPoints, 0);
    strict_1.default.equal(config.rewardApprovalRequired, true);
    strict_1.default.equal(config.returnWindowDays, 30);
});
