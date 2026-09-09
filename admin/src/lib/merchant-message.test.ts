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
  const thrown = /throw new AdminApiError\(\s*response\.status,[\s\S]*?\);/.exec(
    MERCHANT_API,
  );
  assert.ok(thrown, 'the failure path in merchant-api.ts moved');
  assert.doesNotMatch(
    thrown[0],
    /body\?\.message/,
    'a /merchant/* failure would print the API’s English message',
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
