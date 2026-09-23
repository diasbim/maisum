import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import type express from 'express';

import { registerAffiliateRoutes, type AffiliateRouteDeps } from './affiliate_routes.js';
import { AFFILIATE_API_MESSAGE } from './affiliate_api_contracts.js';
import { DEFAULT_AFFILIATE_CONFIG } from './affiliate_contracts.js';
import { affiliateConfigFrom } from './affiliate_store.js';
import { evaluateRateLimit, VALIDATE_CODE_POLICY } from './affiliate_rate_limit.js';

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

const ROUTES_SOURCE = readFileSync(
  path.join(__dirname, '..', 'src', 'affiliate_routes.ts'),
  'utf8',
);
const STORE_SOURCE = readFileSync(
  path.join(__dirname, '..', 'src', 'affiliate_store.ts'),
  'utf8',
);

/* ------------------------------------------------------------- the harness */

type Handler = (req: unknown, res: unknown) => Promise<unknown>;
type Registered = { method: string; route: string; handler: Handler };

function fakeRouter(sink: Registered[], _name: string): express.Router {
  const add =
    (method: string) =>
    (route: string, handler: Handler): void => {
      sink.push({ method, route, handler });
    };
  return {
    get: add('get'),
    post: add('post'),
    put: add('put'),
    patch: add('patch'),
    delete: add('delete'),
  } as unknown as express.Router;
}

type Captured = {
  status: number;
  body: unknown;
  headers: Record<string, string>;
  serverErrors: string[];
};

function fakeResponse(captured: Captured) {
  const res: Record<string, unknown> = {
    status(code: number) {
      captured.status = code;
      return res;
    },
    json(body: unknown) {
      captured.body = body;
      return res;
    },
    setHeader(key: string, value: string) {
      captured.headers[key] = value;
    },
  };
  return res;
}

type Harness = {
  merchant: Registered[];
  admin: Registered[];
  captured: Captured;
  calls: {
    requireBusiness: number;
    ownerChecks: number;
    sweeps: Array<{ merchantId: string | null; limit?: number }>;
  };
};

function harness(
  overrides: Partial<AffiliateRouteDeps> & { business?: { id: string; name: string | null } | null } = {},
): Harness & { call: (routes: Registered[], method: string, route: string, req?: Record<string, unknown>) => Promise<void> } {
  const merchant: Registered[] = [];
  const admin: Registered[] = [];
  const captured: Captured = { status: 200, body: undefined, headers: {}, serverErrors: [] };
  const calls = {
    requireBusiness: 0,
    ownerChecks: 0,
    sweeps: [] as Array<{ merchantId: string | null; limit?: number }>,
  };
  const business =
    overrides.business === undefined ? { id: 'm1', name: 'Loja' } : overrides.business;

  const deps: AffiliateRouteDeps = {
    merchantRouter: fakeRouter(merchant, 'merchant'),
    adminRouter: fakeRouter(admin, 'admin'),
    requireBusiness: async (_req, res) => {
      calls.requireBusiness++;
      if (business === null) {
        // The real one answers the request itself and returns null.
        (res as unknown as { status: (code: number) => { json: (b: unknown) => void } })
          .status(403)
          .json({ success: false, message: 'denied' });
        return null;
      }
      return business;
    },
    isOwnerOrAdminRequest: () => {
      calls.ownerChecks++;
      return overrides.isOwnerOrAdminRequest ? overrides.isOwnerOrAdminRequest({} as never) : true;
    },
    auditActorFrom: () => ({ appUserId: 'u1', firebaseUid: 'uid1', role: 'OWNER' }),
    respondServerError: (res, operation) => {
      captured.serverErrors.push(operation);
      return (res as unknown as { status: (c: number) => { json: (b: unknown) => unknown } })
        .status(500)
        .json({ success: false, message: 'Server error' }) as express.Response;
    },
    normalizePhone: (raw) =>
      raw === '841234567' || raw === '+258841234567' ? '+258841234567' : null,
    affiliateIdForPhone: () => 'af_test',
    sweepAffiliateOutbox: async (input) => {
      calls.sweeps.push(input);
      return { scanned: 2, sent: 0, not_configured: 2 };
    },
    now: () => 1_800_000_000_000,
  };

  registerAffiliateRoutes(deps);

  const call = async (
    routes: Registered[],
    method: string,
    route: string,
    req: Record<string, unknown> = {},
  ): Promise<void> => {
    const found = routes.find((entry) => entry.method === method && entry.route === route);
    assert.ok(found, `${method.toUpperCase()} ${route} is not registered`);
    captured.status = 200;
    captured.body = undefined;
    await found.handler(
      { params: {}, query: {}, body: {}, appUserId: 'u1', ...req },
      fakeResponse(captured),
    );
  };

  return { merchant, admin, captured, calls, call };
}

function body(captured: Captured): Record<string, unknown> {
  return (captured.body ?? {}) as Record<string, unknown>;
}

/* ------------------------------------------------------------ route surface */

const MERCHANT_ROUTES: Array<[string, string]> = [
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
  ['post', '/referral-sales/commit'],
  ['post', '/referral-sales/sync'],
  ['post', '/affiliates/sync'],
  ['get', '/referrals'],
  ['get', '/referrals/:attributionId'],
  ['get', '/affiliate-rewards'],
  ['post', '/affiliate-rewards/:rewardId/approve'],
  ['post', '/affiliate-rewards/:rewardId/cancel'],
];

const ADMIN_ROUTES: Array<[string, string]> = [
  ['get', '/affiliates'],
  ['post', '/affiliates'],
  ['get', '/affiliates/:affiliateId'],
  ['patch', '/affiliates/:affiliateId'],
  ['post', '/affiliates/:affiliateId/status'],
  ['post', '/affiliates/:affiliateId/merchants/:merchantId'],
  ['delete', '/affiliates/:affiliateId/merchants/:merchantId'],
  ['post', '/affiliates/outbox/sweep'],
  ['get', '/merchants/:merchantId/affiliates'],
  ['get', '/merchants/:merchantId/affiliate-rewards'],
  ['get', '/merchants/:merchantId/affiliate-metrics'],
  // The attributions themselves. Scoped to one business like every other read
  // here: a cross-merchant list would need a collection-group index on
  // `affiliate_attributions`, and the security contract allows exactly one of
  // those — the outbox sweep, which no client can reach.
  ['get', '/merchants/:merchantId/referrals'],
  ['get', '/merchants/:merchantId/referrals/:attributionId'],
];

test('every planned merchant route is registered, and nothing else is', () => {
  const { merchant } = harness();
  const actual = merchant.map((entry) => `${entry.method} ${entry.route}`).sort();
  const expected = MERCHANT_ROUTES.map(([method, route]) => `${method} ${route}`).sort();
  assert.deepEqual(actual, expected);
});

test('every planned admin route is registered, and nothing else is', () => {
  const { admin } = harness();
  const actual = admin.map((entry) => `${entry.method} ${entry.route}`).sort();
  const expected = ADMIN_ROUTES.map(([method, route]) => `${method} ${route}`).sort();
  assert.deepEqual(actual, expected);
});

test('the metrics route is declared before the one that would swallow it', () => {
  // Express matches in registration order, so `/affiliates/:affiliateId`
  // declared first would read "metrics" as an affiliate id and answer 404.
  const { merchant } = harness();
  const metrics = merchant.findIndex((entry) => entry.route === '/affiliates/metrics');
  const byId = merchant.findIndex(
    (entry) => entry.method === 'get' && entry.route === '/affiliates/:affiliateId',
  );
  assert.ok(metrics >= 0 && byId >= 0);
  assert.ok(metrics < byId, 'the id route would capture /affiliates/metrics');
});

/* ---------------------------------------------------------------- isolation */

test('a denied business stops every merchant handler before it reads anything', async () => {
  for (const [method, route] of MERCHANT_ROUTES) {
    const { merchant, captured, call, calls } = harness({ business: null });
    await call(merchant, method, route);
    assert.equal(calls.requireBusiness, 1, `${route} did not resolve a business`);
    // `requireBusiness` answered with its own 403; the handler added nothing.
    assert.equal(captured.status, 403, `${route} continued past the denial`);
    assert.deepEqual(captured.serverErrors, [], `${route} fell through to a 500`);
  }
});

test('the business is resolved before the owner check, never after', async () => {
  const { merchant, call, calls } = harness({
    business: null,
    isOwnerOrAdminRequest: () => false,
  });
  await call(merchant, 'post', '/affiliates');
  assert.equal(calls.requireBusiness, 1);
  // A handler that asked "are you an owner?" first would leak that a caller is
  // not an owner of a business they have no access to at all.
  assert.equal(calls.ownerChecks, 0);
});

/* --------------------------------------------------------------------- RBAC */

const OWNER_ONLY: Array<[string, string]> = [
  ['post', '/affiliates'],
  ['post', '/affiliates/sync'],
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

test('a cashier cannot change an affiliate, a code or a reward', async () => {
  for (const [method, route] of OWNER_ONLY) {
    const { merchant, captured, call } = harness({
      isOwnerOrAdminRequest: () => false,
    });
    await call(merchant, method, route, {
      params: { affiliateId: 'af_1', codeId: 'ac_1', rewardId: 'ar_1' },
      body: { name: 'Ana', phone: '841234567' },
    });
    assert.equal(captured.status, 403, `${method} ${route} let a non-owner through`);
    assert.equal(body(captured).code, 'forbidden_role');
    // Refused before any storage call: the 500 path was never reached.
    assert.deepEqual(captured.serverErrors, []);
  }
});

test('every mutating merchant route is owner-only, except validating a code', async () => {
  const { merchant } = harness();
  const mutating = merchant
    .filter((entry) => entry.method !== 'get')
    .map((entry) => `${entry.method} ${entry.route}`)
    .sort();
  const guarded = OWNER_ONLY.map(([method, route]) => `${method} ${route}`).sort();
  assert.deepEqual(
    mutating,
    [
      ...guarded,
      // Both belong to serving a customer at the till, not to managing
      // affiliates: a cashier validates the code and confirms the sale.
      'post /referrals/validate-code',
      'post /referral-sales/commit',
      // And reconciles one they made while the connection was down, which is
      // the same act reported late.
      'post /referral-sales/sync',
    ].sort(),
  );
});

test('reading is open to any member of the business', async () => {
  // A read refused for a cashier would make the affiliate list useless at the
  // till. These reach storage instead, which has no Firebase app in a test —
  // that they get there at all is the point.
  for (const [method, route] of MERCHANT_ROUTES) {
    if (method !== 'get') continue;
    const { merchant, captured, call } = harness({
      isOwnerOrAdminRequest: () => false,
    });
    await call(merchant, method, route, {
      params: { affiliateId: 'af_1', codeId: 'ac_1', rewardId: 'ar_1', attributionId: 'aa_1' },
    });
    assert.notEqual(captured.status, 403, `${route} refused a cashier`);
  }
});

test('validating a code is open to any member of the business', async () => {
  const { merchant, captured, call } = harness({ isOwnerOrAdminRequest: () => false });
  await call(merchant, 'post', '/referrals/validate-code', {
    body: { code: 'AFI-ANA-7K2P' },
  });
  assert.notEqual(captured.status, 403);
});

/* --------------------------------------------------------- field validation */

test('a create refuses each bad field with its own stable code', async () => {
  const cases: Array<[Record<string, unknown>, string]> = [
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
        starts_at: 1_800_000_000_000,
        expires_at: 1_700_000_000_000,
      },
      'invalid_dates',
    ],
  ];

  for (const [payload, code] of cases) {
    const { merchant, captured, call } = harness();
    await call(merchant, 'post', '/affiliates', { body: payload });
    assert.equal(captured.status, 400, `${JSON.stringify(payload)} was not refused`);
    assert.equal(body(captured).code, code);
    assert.equal(typeof body(captured).message, 'string');
    // Nothing reached storage, so nothing half-created an affiliate.
    assert.deepEqual(captured.serverErrors, []);
  }
});

test('a body that is not an object is refused before any field is read', async () => {
  const { merchant, captured, call } = harness();
  await call(merchant, 'post', '/affiliates', { body: 'name=Ana' });
  assert.equal(captured.status, 400);
  assert.equal(body(captured).code, 'invalid_body');
});

test('validate-code refuses a missing or implausible code', async () => {
  for (const payload of [{}, { code: 'ab' }, { code: 42 }]) {
    const { merchant, captured, call } = harness();
    await call(merchant, 'post', '/referrals/validate-code', { body: payload });
    // The rate limiter is reached first and has no Firestore behind it here,
    // so either the limiter's 500 or the field refusal is acceptable — what is
    // not acceptable is a 200 with a validation result.
    assert.notEqual(captured.status, 200);
  }
});

/* ------------------------------------------------- committing a referred sale */

test('committing a sale refuses each bad field with its own stable code', async () => {
  const valid = {
    device_id: 'till-1',
    local_sale_id: 'sale-local-1',
    customer_id: 'cust-1',
    customer_phone: '841234567',
    gross_amount: 500,
    code: 'AFI-ANA-7K2P',
  };
  const cases: Array<[Record<string, unknown>, string]> = [
    [{}, 'invalid_customer'],
    [{ ...valid, device_id: 42 }, 'invalid_sale_reference'],
    [{ ...valid, local_sale_id: '' }, 'invalid_sale_reference'],
    [{ ...valid, customer_id: '' }, 'invalid_customer'],
    [{ ...valid, customer_phone: '12345' }, 'invalid_phone'],
    [{ ...valid, gross_amount: 0 }, 'invalid_sale_amount'],
    [{ ...valid, gross_amount: -10 }, 'invalid_sale_amount'],
    [{ ...valid, gross_amount: '500' }, 'invalid_sale_amount'],
    [{ ...valid, gross_amount: 12.345 }, 'invalid_sale_amount'],
    [{ ...valid, code: 'ab' }, 'invalid_code'],
    [{ ...valid, items: [{ id: 'i1' }] }, 'invalid_sale_items'],
    [
      { ...valid, items: [{ id: 'a/b', merchant_item_id: 'm1', name_snapshot: 'Café', type_snapshot: 'product', quantity: 1 }] },
      'invalid_sale_items',
    ],
    [
      { ...valid, items: [{ id: 'i1', merchant_item_id: 'm1', name_snapshot: 'Café', type_snapshot: 'product', quantity: 0 }] },
      'invalid_sale_items',
    ],
  ];

  for (const [payload, code] of cases) {
    const { merchant, captured, call } = harness();
    await call(merchant, 'post', '/referral-sales/commit', { body: payload });
    assert.equal(captured.status, 400, `${JSON.stringify(payload)} was not refused`);
    assert.equal(body(captured).code, code);
    // Refused before the transaction, so no Firestore was needed to say no.
    assert.deepEqual(captured.serverErrors, []);
  }
});

test('committing a sale is open to any member of the business', async () => {
  const { merchant, captured, call } = harness({ isOwnerOrAdminRequest: () => false });
  await call(merchant, 'post', '/referral-sales/commit', { body: {} });
  // A cashier gets as far as the field validation, not a 403.
  assert.notEqual(captured.status, 403);
  assert.equal(body(captured).code, 'invalid_customer');
});

test('the commit reads nothing that would let a till price its own discount', () => {
  const handler = handlerSource('merchantRouter', 'post', '/referral-sales/commit');
  for (const forbidden of [
    'benefit_type',
    'benefit_value',
    'discount',
    'points',
    'reward',
    'affiliate_id',
    'merchant_id',
  ]) {
    assert.ok(
      !handler.includes(`payload.${forbidden}`),
      `the commit reads ${forbidden} from the request`,
    );
  }
  assert.ok(handler.includes('parseReferralSaleCommit('));
  assert.ok(
    handler.includes('merchantId: business.id'),
    'the commit takes its business from somewhere other than the session',
  );
});

test('a refused code answers with the reason, so the till can sell without one', () => {
  const handler = handlerSource('merchantRouter', 'post', '/referral-sales/commit');
  // A refusal is an answer, not an error: the same shape `validate-code` uses,
  // so the till reads a reason it can act on instead of a thrown 409.
  assert.ok(handler.includes("outcome: 'rejected'"));
  assert.ok(handler.includes("code: 'referral_rejected'"));
  assert.ok(handler.includes('reason: outcome.reason'));
  assert.ok(handler.includes("affiliateApiError(409, 'sale_conflict')"));
  assert.ok(handler.includes("affiliateApiError(404, 'customer_not_found')"));
});

test('a replay answers exactly what the first call answered', () => {
  const handler = handlerSource('merchantRouter', 'post', '/referral-sales/commit');
  const committed = handler.indexOf("case 'committed':");
  const replayed = handler.indexOf("case 'replayed':");
  assert.ok(committed > 0 && replayed > committed);
  // They fall through to one response: a retry must not be distinguishable.
  assert.ok(
    /case 'committed':\s*\n\s*case 'replayed':/.test(handler),
    'a replay is answered differently from the commit it repeats',
  );
});

/* ------------------------------------------------------------- rate limiting */
test('the validate-code budget refuses once the window is spent', () => {
  const now = 1_800_000_000_000;
  let bucket = evaluateRateLimit(null, VALIDATE_CODE_POLICY, now).bucket;
  for (let attempt = 2; attempt <= VALIDATE_CODE_POLICY.limit; attempt++) {
    const decision = evaluateRateLimit(bucket, VALIDATE_CODE_POLICY, now);
    assert.equal(decision.allowed, true, `attempt ${attempt} was refused early`);
    bucket = decision.bucket;
  }
  const refused = evaluateRateLimit(bucket, VALIDATE_CODE_POLICY, now);
  assert.equal(refused.allowed, false);
  assert.equal(refused.remaining, 0);
  assert.ok(refused.retryAfterMs > 0);
});

test('validate-code spends the budget before it reads the body', () => {
  const handler = handlerSource('merchantRouter', 'post', '/referrals/validate-code');
  const limitAt = handler.indexOf('consumeRateLimit(');
  const bodyAt = handler.indexOf('parseBodyObject(');
  assert.ok(limitAt > 0, 'validate-code no longer rate limits');
  assert.ok(bodyAt > 0);
  assert.ok(
    limitAt < bodyAt,
    'a malformed body now costs nothing, which makes the limit walkable',
  );
  assert.ok(
    handler.includes('rateLimitedResponse('),
    'the 429 is no longer the shared, reason-free refusal',
  );
});

test('no other route spends a rate-limit budget', () => {
  // A limit on a management route would lock an owner out of their own list.
  const occurrences = ROUTES_SOURCE.split('consumeRateLimit({').length - 1;
  assert.equal(occurrences, 1, 'consumeRateLimit is used somewhere new');
});

/* ------------------------------------------------------- the outbox sweep */

test('the sweep asks for the whole backlog when no business is named', async () => {
  const { admin, call, calls, captured } = harness();

  await call(admin, 'post', '/affiliates/outbox/sweep', { body: {} });

  assert.deepEqual(calls.sweeps, [{ merchantId: null, limit: undefined }]);
  assert.equal(body(captured).success, true);
});

test('the sweep can be pointed at one business with a bound', async () => {
  const { admin, call, calls } = harness();

  await call(admin, 'post', '/affiliates/outbox/sweep', {
    body: { merchant_id: ' m9 ', limit: 5 },
  });

  assert.deepEqual(calls.sweeps, [{ merchantId: 'm9', limit: 5 }]);
});

test('a nonsense bound is ignored rather than obeyed', async () => {
  const { admin, call, calls } = harness();

  await call(admin, 'post', '/affiliates/outbox/sweep', {
    body: { limit: 'all of them' },
  });

  assert.equal(calls.sweeps[0].limit, undefined);
});

test('the sweep never takes a phone number or a message from the caller', () => {
  const handler = handlerSource('adminRouter', 'post', '/affiliates/outbox/sweep');
  assert.ok(!/phone|body\.(text|message)|to_phone/i.test(handler));
});

/* ------------------------------------------------- source-level obligations */

/** The body of one registered handler, up to the next registration. */
function handlerSource(
  router: 'merchantRouter' | 'adminRouter',
  method: string,
  route: string,
): string {
  const escaped = route.replace(/[/:\-]/g, (c) => `\\${c}`);
  const marker = new RegExp(`${router}\\.${method}\\(\\s*\\n?\\s*'${escaped}'`);
  const match = marker.exec(ROUTES_SOURCE);
  assert.ok(match, `${router}.${method} ${route} is not declared`);
  const start = match.index;
  const next = /(?:merchantRouter|adminRouter)\.(?:get|post|put|patch|delete)\(/.exec(
    ROUTES_SOURCE.slice(start + match[0].length),
  );
  const end =
    next === null
      ? ROUTES_SOURCE.length
      : start + match[0].length + (next.index ?? 0);
  return ROUTES_SOURCE.slice(start, end);
}

test('every change to a code, a status or a reward reaches the audit trail', () => {
  const audited: Array<['merchantRouter' | 'adminRouter', string, string]> = [
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
    assert.ok(
      handlerSource(router, method, route).includes('recordAuditEvent('),
      `${router}.${method} ${route} changes something without recording who did it`,
    );
  }
});

test('the facts a merchant sees on the metrics screen are written as events', () => {
  for (const route of [
    '/affiliates',
    '/affiliate-codes',
    '/referrals/validate-code',
    '/affiliate-rewards/:rewardId/approve',
    '/affiliate-rewards/:rewardId/cancel',
  ]) {
    assert.ok(
      handlerSource('merchantRouter', 'post', route).includes('appendAffiliateEvent('),
      `${route} writes no event, so the history and the metrics will not agree`,
    );
  }
});

test('a rejected validation is recorded as plainly as an accepted one', () => {
  const handler = handlerSource('merchantRouter', 'post', '/referrals/validate-code');
  assert.ok(handler.includes("'REFERRAL_CODE_VALIDATED'"));
  assert.ok(handler.includes("'REFERRAL_REJECTED'"));
  assert.ok(handler.includes('dedupeKey'), 'replays would be counted as attempts');
});

test('a reward decision reads no amount and no ownership from the request', () => {
  for (const route of [
    '/affiliate-rewards/:rewardId/approve',
    '/affiliate-rewards/:rewardId/cancel',
  ]) {
    const handler = handlerSource('merchantRouter', 'post', route);
    assert.ok(
      !handler.includes('parseBodyObject('),
      `${route} reads a request body; an approval must carry no value`,
    );
    assert.ok(
      !/req\.body|payload\./.test(handler),
      `${route} reads a field the caller chose`,
    );
    // Everything it reports comes back out of the stored reward.
    assert.ok(handler.includes('change.after.value'));
    assert.ok(handler.includes('change.after.affiliate_id'));
  }
});

test('no handler puts a phone number anywhere but a mask', () => {
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
    if (line.startsWith('*') || line.startsWith('//') || line.startsWith('/*')) continue;
    if (!/phone/i.test(line)) continue;
    assert.ok(
      allowed.some((pattern) => pattern.test(raw)),
      `a phone is used in an unreviewed way: ${line}`,
    );
  }
});

test('admin routes for one business check that the business exists', () => {
  for (const route of [
    '/merchants/:merchantId/affiliates',
    '/merchants/:merchantId/affiliate-rewards',
    '/merchants/:merchantId/affiliate-metrics',
    '/merchants/:merchantId/referrals',
    '/merchants/:merchantId/referrals/:attributionId',
    '/affiliates/:affiliateId/merchants/:merchantId',
  ]) {
    assert.ok(
      handlerSource('adminRouter', route.startsWith('/merchants') ? 'get' : 'post', route).includes('merchantExists('),
      `${route} acts on a business without checking it is one`,
    );
  }
  // The link and unlink handlers share a path, so the loop above only reaches
  // the first of them; both are meant to check.
  assert.equal(
    ROUTES_SOURCE.split('await merchantExists(').length - 1,
    7,
    'an admin route acting on one business no longer checks it exists',
  );
});

test('every merchant-scoped store read is scoped by the merchant it was given', () => {
  // The path already scopes a subcollection; the filter is what keeps a
  // collection-group query written later from reading every business at once.
  const scoped = STORE_SOURCE.split("where('merchant_id', '==', merchantId)").length - 1;
  assert.ok(scoped >= 1, 'the scoped read helper no longer filters by merchant');
  assert.ok(
    STORE_SOURCE.includes('dto.merchant_id === merchantId') ||
      STORE_SOURCE.includes('before.merchant_id !== input.merchantId'),
    'a row whose own merchant id disagrees with its path is now trusted',
  );
});

test('affiliate events are only ever created, never updated or removed', () => {
  const eventsUses = [...STORE_SOURCE.matchAll(/\.events\([^)]*\)\s*([\s\S]{0,40})/g)];
  assert.ok(eventsUses.length >= 2, 'the events collection is no longer used here');
  for (const use of eventsUses) {
    assert.ok(
      !/\.(update|delete|set)\(/.test(use[1]),
      `an event is written with something other than create: ${use[1].trim()}`,
    );
  }
  assert.ok(
    STORE_SOURCE.includes('await ref.create({'),
    'appendAffiliateEvent no longer uses create, so an id clash would overwrite history',
  );
});

test('identity, code and reward changes each happen in a transaction', () => {
  for (const fragment of [
    'export async function createAffiliateForMerchant',
    'export async function transitionReward',
    'export async function setLinkStatus',
    'export async function updateCode',
  ]) {
    const at = STORE_SOURCE.indexOf(fragment);
    assert.ok(at > 0, `${fragment} is gone`);
    const body = STORE_SOURCE.slice(at, at + 1200);
    assert.ok(
      body.includes('runTransaction('),
      `${fragment} no longer reads and writes atomically`,
    );
  }
  // Claiming a code is a transaction too, and it is the one already written.
  assert.ok(STORE_SOURCE.includes('claimAffiliateCode('));
});

test('a merchant rename stays on its business link', () => {
  const handler = handlerSource(
    'merchantRouter',
    'patch',
    '/affiliates/:affiliateId',
  );
  assert.ok(handler.includes('updateMerchantAffiliateName('));
  assert.ok(!handler.includes('updateAffiliateName('));

  const at = STORE_SOURCE.indexOf(
    'export async function updateMerchantAffiliateName',
  );
  assert.ok(at > 0, 'the merchant-scoped rename helper is gone');
  const body = STORE_SOURCE.slice(at, at + 2200);
  assert.match(body, /transaction\.set\(\s*linkRef,/);
  assert.ok(
    !/transaction\.set\(\s*identityRef,/.test(body),
    'a merchant rename writes the platform-wide identity',
  );
});

test('a failed code claim rolls back against the latest shared identity', () => {
  const at = STORE_SOURCE.indexOf('async function undoAffiliateClaim');
  assert.ok(at > 0, 'the affiliate claim rollback is gone');
  const body = STORE_SOURCE.slice(at, at + 2200);
  assert.ok(body.includes('runTransaction('));
  assert.ok(body.includes('transaction.get(identityRef)'));
  assert.ok(body.includes('merchantIds.length === 0'));
  assert.ok(body.includes('arrayRemove(input.merchantId)'));
});

test('a preview with no sale describes the code, not a discount of zero', () => {
  const at = STORE_SOURCE.indexOf('function advisoryBenefit');
  assert.ok(at > 0, 'the advisory benefit is no longer computed in one place');
  const body = STORE_SOURCE.slice(at, at + 1400);
  assert.ok(
    body.includes('calculateBenefit(code, saleAmount)'),
    'a preview with an amount no longer runs the real calculation',
  );
  assert.ok(
    /% de desconto`/.test(body) && !/calculateBenefit\(code, 0\)/.test(body),
    'a percentage with no sale is rendered against an amount of zero',
  );
});

test('code validation uses the name this business assigned to the affiliate', () => {
  const at = STORE_SOURCE.indexOf('export async function validateReferralCode');
  assert.ok(at > 0, 'the referral validation store function is gone');
  const body = STORE_SOURCE.slice(at, at + 5200);
  assert.ok(
    body.includes('affiliateWithLinkName(affiliate, linkData ?? {})'),
    'validation bypasses the merchant-scoped affiliate name',
  );
  assert.ok(
    body.includes('affiliateName: merchantAffiliate.first_name'),
    'the till receives the platform-wide name',
  );
});

test('a code that belongs to another business is not even fetched', () => {
  const at = STORE_SOURCE.indexOf('export async function validateReferralCode');
  assert.ok(at > 0);
  const body = STORE_SOURCE.slice(at, at + 2000);
  const lookupAt = body.indexOf('resolveCodeLookup(');
  const guardAt = body.indexOf('lookup.merchantId !== input.merchantId');
  const fetchAt = body.indexOf('affiliateRefs.code(');
  assert.ok(lookupAt > 0 && guardAt > lookupAt, 'the lookup is no longer checked');
  assert.ok(
    guardAt < fetchAt,
    'a code from another business is read before it is refused',
  );
  assert.ok(
    body.includes("reason: 'CODE_NOT_FOUND'"),
    'a cross-business code answers something other than not found',
  );
});

test('every message this API can raise is actually reachable from a route', () => {
  // A message nobody raises is a promise to the reader that is not kept, and
  // the next person copies it into a new route expecting it to mean something.
  const sources =
    ROUTES_SOURCE +
    STORE_SOURCE +
    readFileSync(
      path.join(__dirname, '..', 'src', 'affiliate_api_contracts.ts'),
      'utf8',
    ).replace(/export const AFFILIATE_API_MESSAGE[\s\S]*?\n} as const;/, '');

  for (const key of Object.keys(AFFILIATE_API_MESSAGE)) {
    if (key === 'forbidden_role') continue; // raised by ownerOnlyError()
    assert.ok(sources.includes(`'${key}'`), `${key} is declared but never raised`);
  }
  assert.ok(ROUTES_SOURCE.includes('ownerOnlyError()'));
});

/* ------------------------------------------------------------ business config */

test('affiliate settings fall back to the defaults the plan fixes', () => {
  const config = affiliateConfigFrom({});
  assert.deepEqual(config, DEFAULT_AFFILIATE_CONFIG);
});

test('affiliate settings are read from the business document, not guessed', () => {
  const config = affiliateConfigFrom({
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
  assert.equal(config.enabled, true);
  assert.equal(config.firstSaleRewardPoints, 100);
  assert.equal(config.returnRewardEnabled, true);
  assert.equal(config.returnRewardPoints, 50);
  assert.equal(config.returnWindowDays, 45);
  assert.equal(config.rewardApprovalRequired, false);
  assert.equal(config.notificationsEnabled, false);
});

test('an unreadable setting keeps the safe default rather than becoming zero', () => {
  const config = affiliateConfigFrom({
    affiliate_config: {
      enabled: 'yes',
      first_sale_reward_points: -5,
      reward_approval_required: 'no',
      return_window_days: 'thirty',
    },
  });
  // A truthy string must not turn the feature on, and "approval required"
  // must not fall to false because somebody stored the word "no".
  assert.equal(config.enabled, false);
  assert.equal(config.firstSaleRewardPoints, 0);
  assert.equal(config.rewardApprovalRequired, true);
  assert.equal(config.returnWindowDays, 30);
});
