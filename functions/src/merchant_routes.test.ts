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
