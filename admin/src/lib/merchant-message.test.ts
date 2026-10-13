import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

/**
 * What a business owner reads when a request to the API fails.
 *
 * `merchantMessage` is not exported — it is an implementation detail of one
 * `call()` — and importing `merchant-api.ts` here would drag in `server-only`
 * and firebase-admin for the sake of one string. So this reads the source,
 * the way `admin_access.test.ts` reads `firestore.rules`: what is asserted is
 * the rule, not a copy of it.
 *
 * The rule is that the API's own `message` never reaches this screen. Every
 * string the `/merchant/*` routes can send is an internal English one, and
 * this half of the portal has a single Portuguese-speaking audience. The
 * console keeps the opposite rule on purpose, so that is asserted too.
 */

// `__dirname` is `.test-build` at run time, not `src/lib` — the same hop the
// neighbouring test makes to reach the app's Dart sources.
const read = (name: string) =>
  readFileSync(path.join(__dirname, '..', 'src', 'lib', name), 'utf8');

const MERCHANT_API = read('merchant-api.ts');
const ADMIN_API = read('admin-api.ts');

test('the business side never shows the API its own words', () => {
  // `body?.message` may still be logged; what must not happen is it being
  // handed to AdminApiError, which is what the screen prints.
  const thrown = [
    ...MERCHANT_API.matchAll(
      /throw new AdminApiError\(\s*response\.status,[\s\S]*?\);/g,
    ),
  ];
  assert.ok(thrown.length >= 2, 'the failure paths in merchant-api.ts moved');
  for (const match of thrown) {
    assert.doesNotMatch(
      match[0],
      /body\?\.message/,
      'a /merchant/* failure would print the API’s English message',
    );
  }
});

/**
 * The one exception, and what keeps it narrow.
 *
 * The `/merchant/affiliate*` routes answer a refusal with a stable `code` and
 * a sentence from `AFFILIATE_API_MESSAGE` — Portuguese by construction, and
 * written for the person reading it. Those are worth showing, and "Este
 * afiliado já está ligado a este negócio" is worth far more than "reveja os
 * campos". The gate is the presence of the code: without one, nothing the API
 * wrote reaches the screen.
 */
test('a refusal is only spoken when the API named it with a code', () => {
  const guard = /function codedFailure\([\s\S]*?\n\}/.exec(MERCHANT_API);
  assert.ok(guard, 'codedFailure moved in merchant-api.ts');
  assert.match(guard[0], /if \(code === '' \|\| message === ''\) return null;/);

  // And it is used as a gate rather than a preference: every use is guarded by
  // the null check.
  const uses = [...MERCHANT_API.matchAll(/const coded = codedFailure\(body\);/g)];
  assert.equal(uses.length, 2, 'the read and write paths no longer agree');
  assert.equal(
    [...MERCHANT_API.matchAll(/if \(coded !== null\) \{/g)].length,
    2,
  );
});

test('the affiliate routes really do send a code beside every message', () => {
  // Guards the guard above: if the API stopped sending one, the portal would
  // quietly fall back to generic wording on every affiliate failure.
  const routes = readFileSync(
    path.join(__dirname, '..', '..', 'functions', 'src', 'affiliate_routes.ts'),
    'utf8',
  );
  assert.match(
    routes,
    /\.json\(\{ success: false, code: error\.code, message: error\.message \}\)/,
  );
});

test('the console still does, because internal staff match those strings', () => {
  // Guards the guard: if this stopped being true the test above would be
  // asserting a difference that no longer exists.
  assert.match(ADMIN_API, /body\?\.message/);
});

test('the 5xx sentence names no internal system', () => {
  const sentence = /if \(status >= 500\) return '([^']+)';/.exec(MERCHANT_API);
  assert.ok(sentence, 'merchantMessage no longer special-cases 5xx');
  const message = sentence[1];

  // "A API de administração falhou" is the console's wording. A business owner
  // has never heard of it and can do nothing about it.
  assert.doesNotMatch(message, /API|administra/i);
  assert.match(message, /\.$/, 'not a full sentence');
});
