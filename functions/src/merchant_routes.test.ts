import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

/**
 * What guards `/merchant/*`, checked against the source rather than trusted.
 *
 * These endpoints run with the Admin SDK, which bypasses `firestore.rules`
 * entirely, so the only thing standing between a caller and someone else's
 * customer list is the resolve step at the top of each handler. That is a
 * property of how the routes are written, and nothing in a unit test of the
 * data layer would notice it going missing — a route added in a hurry, with
 * the `merchantId` read straight off the query string, would pass every other
 * test in this suite.
 *
 * So this reads index.ts and asserts the shape holds. It is a lint with a
 * reason, and it fails loudly the day someone adds route number six.
 */

const SOURCE = readFileSync(
  path.join(__dirname, '..', 'src', 'index.ts'),
  'utf8',
);

/** The body of every `merchantRouter.<verb>('<path>', ...)` handler. */
function merchantRoutes(): Array<{ route: string; body: string }> {
  const pattern = /merchantRouter\.(get|post|put|patch|delete)\(\s*'([^']+)'/g;
  const found: Array<{ route: string; body: string }> = [];

  for (const match of SOURCE.matchAll(pattern)) {
    const start = match.index ?? 0;
    // Up to the start of the next route, or to where the router is mounted.
    pattern.lastIndex = start + match[0].length;
    const next = new RegExp(
      /merchantRouter\.(?:get|post|put|patch|delete)\(|app\.use\('\/merchant'/,
    ).exec(SOURCE.slice(pattern.lastIndex));
    const end =
      next === null ? SOURCE.length : pattern.lastIndex + (next.index ?? 0);
    found.push({ route: match[2], body: SOURCE.slice(start, end) });
  }

  return found;
}

test('the merchant router still has routes to check', () => {
  // Guards the guard: a rename that made the pattern match nothing would turn
  // every assertion below into a vacuous pass.
  const routes = merchantRoutes();
  assert.ok(routes.length >= 5, `found only ${routes.length} merchant routes`);
  assert.ok(routes.some((route) => route.route === '/customers'));
});

test('every merchant route resolves its business before reading anything', () => {
  for (const { route, body } of merchantRoutes()) {
    const resolves =
      body.includes('requireBusiness(') ||
      body.includes('businessForRequest(') ||
      // /businesses is the one that answers "which are you" and so cannot
      // resolve a business first; it asks for the caller's identity instead.
      body.includes('merchantIdentityFrom(');
    assert.ok(
      resolves,
      `merchantRouter '${route}' does not resolve a business before reading`,
    );
  }
});

test('no merchant route reads a merchant id straight from the request', () => {
  // `businessForRequest` honours `?merchant_id=` only after `authorizeBusiness`
  // confirms it. A handler reaching for the parameter itself would skip that.
  for (const { route, body } of merchantRoutes()) {
    assert.ok(
      !/req\.query\.merchant_id/.test(body),
      `merchantRouter '${route}' reads merchant_id from the query directly`,
    );
    assert.ok(
      !/req\.params\.merchantId/.test(body),
      `merchantRouter '${route}' reads a merchant id from the path`,
    );
  }
});

test('a denied resolve returns, rather than falling through', () => {
  // `requireBusiness` answers the request and returns null. A handler that
  // ignored the null would serve the first business it could find.
  for (const { route, body } of merchantRoutes()) {
    if (!body.includes('requireBusiness(')) continue;
    assert.ok(
      /if \(!business\) return/.test(body),
      `merchantRouter '${route}' does not stop when the business is denied`,
    );
  }
});

/* ------------------------------------------------------- the bypasses above */

test('the request bypasses cannot reach merchant data', () => {
  // Two paths through the global middleware admit a request with no ID token:
  // the admin API key, and ALLOW_DEV_AUTH with an x-merchant-id header. Both
  // leave `req.auth` unset, and `merchantIdentityFrom` returns null without it
  // — so they answer 401 rather than acting as a business.
  const assignments = SOURCE.match(/authedReq\.auth = /g) ?? [];
  assert.equal(
    assignments.length,
    1,
    'req.auth is assigned in more than one place; the merchant guard assumes ' +
      'it is set only after verifyIdToken',
  );

  const identity = /function merchantIdentityFrom\(([\s\S]*?)\n}/.exec(SOURCE);
  assert.ok(identity, 'merchantIdentityFrom is no longer a named function');
  assert.ok(
    identity[1].includes('req.auth'),
    'merchantIdentityFrom no longer derives the caller from the verified token',
  );
  assert.ok(
    /if \(!decoded\?\.uid\) return null/.test(identity[1]),
    'merchantIdentityFrom no longer refuses a request with no verified uid',
  );
});

/**
 * Which merchant routes may change anything.
 *
 * The business side of the portal is a reading surface: a sale, a redemption
 * and a visit report all happen with the customer standing there, and belong
 * to the app. Closing a recovery task is bookkeeping about work already done,
 * which is why it is the exception.
 *
 * "The portal writes when it needs to" is a real decision, and this list is
 * where it is recorded. Adding a route here should be a deliberate act with a
 * reason, not something that arrives with a feature — so a new write fails
 * this test until someone writes it down.
 */
const ESCRITAS_PERMITIDAS = new Set(['/recovery-tasks/:taskId/complete']);

function mutatingMerchantRoutes(): string[] {
  const pattern = /merchantRouter\.(post|put|patch|delete)\(\s*'([^']+)'/g;
  return [...SOURCE.matchAll(pattern)].map((match) => match[2]);
}

test('the only merchant writes are the ones we decided on', () => {
  for (const route of mutatingMerchantRoutes()) {
    assert.ok(
      ESCRITAS_PERMITIDAS.has(route),
      `${route} changes business data. Add it to ESCRITAS_PERMITIDAS with a reason, or make it a GET.`,
    );
  }
});

test('every allowed write is actually still there', () => {
  // Guards the guard the other way: a route removed or renamed leaves a stale
  // entry above, and the next reader would trust a list that describes nothing.
  const found = new Set(mutatingMerchantRoutes());
  for (const route of ESCRITAS_PERMITIDAS) {
    assert.ok(found.has(route), `${route} is in the allow-list but no longer exists`);
  }
});

test('a write scopes itself by the resolved business, not by its own path', () => {
  // A read that forgets the scope shows the wrong data; a write that forgets it
  // changes someone else's.
  for (const { route, body } of merchantRoutes()) {
    if (!/merchantRouter\.(post|put|patch|delete)/.test(body)) continue;
    assert.ok(
      /business\.id/.test(body),
      `${route} writes without passing business.id`,
    );
  }
});

/**
 * What sits above the authentication middleware.
 *
 * Express runs `app.use` handlers in order, so anything mounted before the
 * auth middleware is reachable with no token at all. Exactly one thing is
 * meant to be: the survey links a customer opens, which have no account behind
 * them and are authorised by their own signature instead.
 *
 * A second mount added above that line would be an open door, and it would
 * look like an ordinary line of setup code. This is the test that notices.
 */
test('only the public survey router sits above authentication', () => {
  const authAt = SOURCE.indexOf('app.use(async (req, res, next) => {');
  assert.ok(authAt > 0, 'the auth middleware is no longer mounted with app.use');

  const before = SOURCE.slice(0, authAt);
  const mounts = [...before.matchAll(/app\.use\(([^)]*)/g)].map((m) => m[1].trim());

  assert.deepEqual(
    mounts,
    ["express.json({ limit: '1mb' }", "'/public', publicRouter"],
    'something new is mounted before authentication',
  );
});

test('the public routes read nothing the caller controls but the token', () => {
  const publicAt = SOURCE.indexOf('const publicRouter = express.Router();');
  assert.ok(publicAt > 0, 'publicRouter is gone');

  const routes = [...SOURCE.matchAll(/publicRouter\.(get|post)\(\s*'([^']+)'/g)];
  assert.ok(routes.length >= 2, `found only ${routes.length} public routes`);

  for (const match of routes) {
    const start = match.index ?? 0;
    const body = SOURCE.slice(start, start + 4000);
    assert.ok(
      /verifySurveyLinkToken\(/.test(body),
      `public route ${match[2]} does not verify a link`,
    );
    // The business must come out of the signed token. Taken from anywhere else
    // on an unauthenticated route, it is taken from anyone.
    assert.ok(
      !/req\.query\.merchant_id|req\.body\?\.merchant_id|req\.params\.merchantId/.test(body),
      `public route ${match[2]} reads a merchant id from the request`,
    );
  }
});
