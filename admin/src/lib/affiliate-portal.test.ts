import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

/**
 * The affiliate screens, asserted against their own source.
 *
 * None of what matters most here can be imported into `node --test`:
 * `merchant-api.ts` pulls in `server-only`, the actions are `'use server'`, and
 * the pages are React. What they get wrong, though, is not logic — it is a URL
 * that does not exist, a body key the API ignores, a cache that is never
 * invalidated, and a token that leaves the server. Every one of those is
 * visible in the text, and every one of them fails silently at runtime: a
 * wrong key is simply not read, and a missing `revalidatePath` shows yesterday's
 * answer to a question somebody just changed.
 *
 * So this reads the portal's source and the Functions' routes, the way
 * `merchant-message.test.ts` and `admin_access.test.ts` already do, and
 * asserts they still describe the same product.
 */

// `__dirname` is `.test-build` at run time, not `src/lib`.
const root = path.join(__dirname, '..');
const read = (...segments: string[]) =>
  readFileSync(path.join(root, ...segments), 'utf8');

const MERCHANT_API = read('src', 'lib', 'merchant-api.ts');
const ADMIN_API = read('src', 'lib', 'admin-api.ts');
const MERCHANT_ACTIONS = read('src', 'lib', 'merchant-actions.ts');
const ADMIN_ACTIONS = read('src', 'lib', 'actions.ts');
const ROUTES_TS = read('..', 'functions', 'src', 'affiliate_routes.ts');

/* --------------------------------------------------------------- the URLs */

/** Every path the Functions actually mount, by router and method. */
function mounted(router: 'merchantRouter' | 'adminRouter'): Set<string> {
  // The paths are written relative to where the router is mounted, so
  // `adminRouter.get('/affiliates')` answers `/admin/affiliates`.
  const prefix = router === 'adminRouter' ? '/admin' : '/merchant';
  const pattern = new RegExp(
    `${router}\\.(get|post|patch|delete)\\(\\s*'([^']+)'`,
    'g',
  );
  return new Set(
    [...ROUTES_TS.matchAll(pattern)].map(
      (match) => `${match[1].toUpperCase()} ${prefix}${match[2]}`,
    ),
  );
}

/**
 * A portal path with its ids replaced by the express parameter they fill.
 *
 * `/merchant/affiliates/${encodeURIComponent(id)}/activate` becomes
 * `/merchant/affiliates/:x/activate`, which is what the route table holds.
 */
function shape(template: string): string {
  return template.replace(/\$\{[^}]*\}/g, ':x').replace(/\?.*$/, '');
}

const MERCHANT_ROUTES = mounted('merchantRouter');
const ADMIN_ROUTES = mounted('adminRouter');

function assertMounted(routes: Set<string>, method: string, template: string) {
  const wanted = shape(template);
  const found = [...routes].some((route) => {
    const [routeMethod, routePath] = route.split(' ');
    if (routeMethod !== method) return false;
    return routePath.replace(/:\w+/g, ':x') === wanted;
  });
  assert.ok(found, `${method} ${wanted} is not a route the Functions mount`);
}

test('the routes are mounted, so the parse cannot be vacuous', () => {
  assert.ok(MERCHANT_ROUTES.size >= 15, `found ${MERCHANT_ROUTES.size} merchant routes`);
  assert.ok(ADMIN_ROUTES.size >= 8, `found ${ADMIN_ROUTES.size} admin routes`);
});

test('every merchant affiliate call names a route the API answers', () => {
  const calls: Array<[string, string]> = [
    ['GET', '/merchant/affiliates'],
    ['GET', '/merchant/affiliates/${x}'],
    ['GET', '/merchant/affiliates/metrics'],
    ['GET', '/merchant/affiliates/${x}/metrics'],
    ['GET', '/merchant/affiliate-rewards'],
    ['POST', '/merchant/affiliates'],
    ['POST', '/merchant/affiliates/${x}/activate'],
    ['POST', '/merchant/affiliates/${x}/deactivate'],
    ['PATCH', '/merchant/affiliate-codes/${x}'],
    ['POST', '/merchant/affiliate-codes/${x}/enable'],
    ['POST', '/merchant/affiliate-codes/${x}/disable'],
    ['POST', '/merchant/affiliate-rewards/${x}/approve'],
    ['POST', '/merchant/affiliate-rewards/${x}/cancel'],
  ];
  for (const [method, template] of calls) {
    assertMounted(MERCHANT_ROUTES, method, template);
  }

  // And the portal really does call them: a route table agreeing with itself
  // proves nothing.
  for (const fragment of [
    "'/merchant/affiliates'",
    "'/merchant/affiliate-rewards'",
    '/merchant/affiliates/${encodeURIComponent(affiliateId)}',
    '/merchant/affiliate-codes/${encodeURIComponent(edit.codeId)}',
    '/merchant/affiliate-rewards/${encodeURIComponent(input.rewardId)}/${input.decision}',
  ]) {
    assert.ok(MERCHANT_API.includes(fragment), `merchant-api.ts no longer calls ${fragment}`);
  }
});

test('every console affiliate call names a route the API answers', () => {
  const calls: Array<[string, string]> = [
    ['GET', '/admin/affiliates'],
    ['GET', '/admin/affiliates/${x}'],
    ['POST', '/admin/affiliates'],
    ['PATCH', '/admin/affiliates/${x}'],
    ['POST', '/admin/affiliates/${x}/status'],
    ['POST', '/admin/affiliates/${x}/merchants/${y}'],
    ['DELETE', '/admin/affiliates/${x}/merchants/${y}'],
    ['GET', '/admin/merchants/${x}/affiliates'],
    ['GET', '/admin/merchants/${x}/affiliate-rewards'],
    ['GET', '/admin/merchants/${x}/affiliate-metrics'],
  ];
  for (const [method, template] of calls) {
    assertMounted(ADMIN_ROUTES, method, template);
  }

  for (const fragment of [
    "'/admin/affiliates'",
    '/admin/affiliates/${encodeURIComponent(input.affiliateId)}/status',
    '/admin/merchants/${encodeURIComponent(merchantId)}/affiliate-metrics',
  ]) {
    assert.ok(ADMIN_API.includes(fragment), `admin-api.ts no longer calls ${fragment}`);
  }
});

test('every id in a path is encoded before it becomes one', () => {
  // An id with a slash in it would otherwise address a route the caller chose
  // rather than the one the function means. A query string is the one
  // interpolation that is not an id: `buildListQuery` escapes its own values.
  for (const [file, source] of [
    ['merchant-api.ts', MERCHANT_API],
    ['admin-api.ts', ADMIN_API],
  ] as const) {
    const interpolations = [...source.matchAll(/\/affiliate[^`'"]*?\$\{([^}]+)\}/g)];
    assert.ok(interpolations.length >= 3, `${file}: found ${interpolations.length}`);
    for (const match of interpolations) {
      assert.match(
        match[1],
        /encodeURIComponent|buildListQuery|input\.decision/,
        `${file}: ${match[1]} reaches a URL unencoded`,
      );
    }
  }
});

/* --------------------------------------------------------------- the bodies */

test('a created affiliate sends the keys the API reads, in its spelling', () => {
  // `parseCodeDefaults` and `parseAffiliateName` read snake_case. A camelCase
  // key is not an error: it is simply not read, and the code is created with
  // the default benefit instead of the one that was typed.
  for (const key of [
    'name:',
    'phone:',
    'benefit_type:',
    'benefit_value:',
    'usage_limit:',
    'first_visit_only:',
    'expires_at:',
  ]) {
    assert.ok(
      MERCHANT_API.includes(key),
      `the create body no longer sends ${key}`,
    );
  }
});

test('the code edit sends both ends of a window or neither', () => {
  // `parseValidityPair` refuses one without the other on purpose: an expiry
  // alone would move a code that has not started yet to today.
  const block = /export function updateMyAffiliateCode\([\s\S]*?\n\}/.exec(
    MERCHANT_API,
  );
  assert.ok(block, 'updateMyAffiliateCode moved');
  assert.match(block[0], /starts_at: edit\.validity\.startsAt/);
  assert.match(block[0], /expires_at: edit\.validity\.expiresAt/);
  assert.match(block[0], /edit\.validity === null[\s\S]*?\{\}/);
});

test('a reward decision carries no amount', () => {
  // What a reward is worth was decided from the business's own settings when
  // the sale committed. A request that could state it could award itself
  // points, which is why `parseRewardDecision` reads nothing at all.
  const block = /export function decideMyAffiliateReward\([\s\S]*?\n\}/.exec(
    MERCHANT_API,
  );
  assert.ok(block, 'decideMyAffiliateReward moved');
  assert.doesNotMatch(block[0], /value|points|body:/);
});

test('the console never sends a business id it was handed as a body field', () => {
  // The merchant endpoints resolve the business from the token; only the
  // console names one, and it does so in the path.
  assert.doesNotMatch(MERCHANT_API, /merchant_id:/);
});

/* ------------------------------------------------------------------- auth */

test('the ID token is read from the session and never leaves the server', () => {
  for (const [file, source] of [
    ['merchant-api.ts', MERCHANT_API],
    ['admin-api.ts', ADMIN_API],
  ] as const) {
    assert.ok(source.startsWith("import 'server-only';"), `${file} is importable by the browser`);
    assert.match(source, /Authorization: `Bearer \$\{/, `${file} stopped forwarding the token`);
  }

  // The pages and actions never touch it: everything goes through the two
  // modules above, which cannot be imported into a client component.
  for (const file of ['merchant-actions.ts', 'actions.ts']) {
    assert.doesNotMatch(read('src', 'lib', file), /idToken|Bearer/, file);
  }
});

test('every affiliate screen is a server component', () => {
  for (const page of [
    ['negocio', 'afiliados', 'page.tsx'],
    ['negocio', 'afiliados', 'novo', 'page.tsx'],
    ['negocio', 'afiliados', '[affiliateId]', 'page.tsx'],
    ['negocio', 'afiliados', '[affiliateId]', 'codigo', 'page.tsx'],
    ['negocio', 'afiliados', 'recompensas', 'page.tsx'],
    ['admin', 'afiliados', 'page.tsx'],
    ['admin', 'afiliados', '[affiliateId]', 'page.tsx'],
    ['admin', 'merchants', '[merchantId]', 'afiliados', 'page.tsx'],
  ]) {
    const source = read('src', 'app', ...page);
    assert.doesNotMatch(
      source,
      /^'use client'/m,
      `${page.join('/')} became a client component`,
    );
    assert.match(
      source,
      /export const dynamic = 'force-dynamic'/,
      `${page.join('/')} may now be served from a build-time cache`,
    );
  }
});

/* ------------------------------------------------------------ the routes */

test('every route the plan names exists', () => {
  for (const route of [
    ['negocio', 'afiliados', 'page.tsx'],
    ['negocio', 'afiliados', 'novo', 'page.tsx'],
    ['negocio', 'afiliados', '[affiliateId]', 'page.tsx'],
    ['negocio', 'afiliados', '[affiliateId]', 'loading.tsx'],
    ['negocio', 'afiliados', '[affiliateId]', 'codigo', 'page.tsx'],
    ['negocio', 'afiliados', 'recompensas', 'page.tsx'],
    ['admin', 'afiliados', 'page.tsx'],
    ['admin', 'afiliados', '[affiliateId]', 'page.tsx'],
    ['admin', 'afiliados', '[affiliateId]', 'loading.tsx'],
    ['admin', 'merchants', '[merchantId]', 'afiliados', 'page.tsx'],
  ]) {
    assert.ok(
      existsSync(path.join(root, 'src', 'app', ...route)),
      `${route.join('/')} is missing`,
    );
  }
});

test('both areas can be navigated to, and the merchant has a tab', () => {
  assert.match(
    read('src', 'app', 'negocio', 'MerchantNav.tsx'),
    /href: '\/negocio\/afiliados', label: 'Afiliados'/,
  );
  assert.match(
    read('src', 'app', 'admin', 'AdminNav.tsx'),
    /href: '\/admin\/afiliados', label: 'Afiliados'/,
  );
  assert.match(
    read('src', 'app', 'admin', 'merchants', '[merchantId]', 'MerchantTabs.tsx'),
    /\$\{base\}\/afiliados`, label: 'Afiliados'/,
  );
});

/* ------------------------------------------------------- what a write refreshes */

/**
 * Which pages each mutation invalidates.
 *
 * These screens are server rendered and cached per request. A write that
 * forgets one leaves the operator looking at the state they just changed —
 * the failure mode is a page that is quietly, confidently wrong.
 */
function revalidated(source: string, action: string): string[] {
  const block = new RegExp(
    `export async function ${action}\\([\\s\\S]*?\\n\\}`,
  ).exec(source);
  assert.ok(block, `${action} moved`);

  // The paths are written as constants as often as literals, so the constants
  // are resolved rather than the test being written to match one style.
  const constants = [...source.matchAll(/^const ([A-Z_]+) = '([^']+)';/gm)];
  const direct = [...block[0].matchAll(/revalidatePath\(\s*([^)]*)\)/g)].map(
    (match) => {
      let argument = match[1].trim();
      for (const [, name, value] of constants) {
        argument = argument.split(name).join(value);
      }
      return argument.replace(/[`'"]/g, '');
    },
  );

  // Several actions delegate to one helper; its paths count as theirs.
  const helpers = /revalidateAffiliate\(/.test(block[0])
    ? ['/negocio/afiliados', '/negocio/afiliados/recompensas']
    : [];
  return [...direct, ...helpers];
}

test('every merchant write refreshes the list it came from', () => {
  for (const action of [
    'createAffiliateAction',
    'setAffiliateActiveAction',
    'saveAffiliateCodeAction',
    'setAffiliateCodeEnabledAction',
  ]) {
    const paths = revalidated(MERCHANT_ACTIONS, action);
    assert.ok(
      paths.some((value) => value.includes('/negocio/afiliados')),
      `${action} leaves the affiliate list stale`,
    );
  }

  // The shared helper is what carries the detail and the code page.
  const helper = /function revalidateAffiliate\([\s\S]*?\n\}/.exec(MERCHANT_ACTIONS);
  assert.ok(helper, 'revalidateAffiliate moved');
  assert.match(helper[0], /revalidatePath\(AFFILIATES\)/);
  assert.match(helper[0], /recompensas/);
  assert.match(helper[0], /codigo/);
});

test('a reward decision refreshes the rewards screen and the affiliate', () => {
  const block = /async function decideReward\([\s\S]*?\n\}/.exec(MERCHANT_ACTIONS);
  assert.ok(block, 'decideReward moved');
  assert.match(block[0], /revalidatePath\(`\$\{AFFILIATES\}\/recompensas`\)/);
  assert.match(block[0], /revalidatePath\(affiliatePath\(affiliateId\)\)/);
  // Whose page to refresh comes off the API's answer, not off the form.
  assert.match(block[0], /reward\?\.affiliate_id/);
});

test('linking from the console refreshes both sides of the link', () => {
  for (const action of ['linkAffiliateAction', 'unlinkAffiliateAction']) {
    const paths = revalidated(ADMIN_ACTIONS, action);
    assert.ok(paths.includes('/admin/afiliados'), `${action}: console list stale`);
    assert.ok(
      paths.some((value) => value.includes('/admin/merchants/')),
      `${action}: the business drilldown stays stale`,
    );
    assert.ok(
      paths.includes('/negocio/afiliados'),
      `${action}: the owner keeps seeing the old link`,
    );
  }
});

/* ----------------------------------------------------- who may change what */

test('every merchant mutation asks the token before it asks the API', () => {
  const owners = [
    ...MERCHANT_ACTIONS.matchAll(/await requireOwner\(form\)/g),
  ].length;
  // Five entry points: create, activate, save code, enable code, and the
  // shared reward decision.
  assert.ok(owners >= 5, `only ${owners} affiliate mutations check the role`);
  assert.match(MERCHANT_ACTIONS, /getMerchantPermissions/);
});

test('a destructive decision is refused without its confirmation', () => {
  assert.match(
    MERCHANT_ACTIONS,
    /cancelAffiliateRewardAction[\s\S]*?checkbox\(form, 'confirm'\)/,
  );
  assert.match(
    ADMIN_ACTIONS,
    /status === 'SUSPENDED' && !checkbox\(form, 'confirm'\)/,
  );
  assert.match(
    ADMIN_ACTIONS,
    /unlinkAffiliateAction[\s\S]*?checkbox\(form, 'confirm'\)/,
  );
});

test('the portal offers no way to pay a reward', () => {
  // `REWARD_TRANSITIONS` allows APPROVED -> PAID, and the plan leaves handing
  // the points over to a person. A button here would put the ledger out of
  // step with what was actually given.
  assert.doesNotMatch(MERCHANT_ACTIONS, /'PAID'|\/pay\b/);
  assert.doesNotMatch(MERCHANT_API, /\/pay\b/);
});

test('sharing is offered only for a code the till would accept', () => {
  const shared = read('src', 'app', 'negocio', 'afiliados', 'afiliados.tsx');
  assert.match(shared, /canShareAffiliateCode\(affiliate\)/);
  // No provisional code is ever shared: the create form has no share control
  // at all, because until the server answers there is no code.
  assert.doesNotMatch(
    read('src', 'app', 'negocio', 'afiliados', 'novo', 'page.tsx'),
    /wa\.me|ShareCode/,
  );
});

test('the console shows a mask, never a number it could call', () => {
  const page = read('src', 'app', 'admin', 'afiliados', 'page.tsx');
  const detail = read('src', 'app', 'admin', 'afiliados', '[affiliateId]', 'page.tsx');
  for (const [name, source] of [
    ['list', page],
    ['detail', detail],
  ] as const) {
    assert.match(source, /phone_masked/, `the console ${name} stopped masking`);
    assert.doesNotMatch(
      source,
      /affiliate\.phone[^_]/,
      `the console ${name} prints a reachable number`,
    );
  }
});
