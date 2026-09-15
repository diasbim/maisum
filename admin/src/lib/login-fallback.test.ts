import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

/**
 * The sign-in form must never submit credentials as a GET.
 *
 * This was found by driving the portal in a browser, not by reading the code:
 * hydration failed on a running dev server, the form fell back to the HTML
 * default, and the address bar ended up reading
 *
 *   /login?email=dono%40teste.local&password=teste123456
 *
 * — which is then in the history, the access log, and the `Referer` of every
 * request the page makes next. The whole suite missed it because every other
 * test signs in the way the smoke script does, by calling the Firebase SDK and
 * posting the token, so nothing had ever touched the form itself.
 *
 * A browser test would guard this more broadly, and would mean a browser in
 * CI. This is the narrow, dependency-free version: the two attributes that
 * decide where an unhydrated submit sends the password.
 */

const FORM = readFileSync(
  path.join(__dirname, '..', 'src', 'app', 'login', 'LoginForm.tsx'),
  'utf8',
);

/** The opening tag of the sign-in form, attributes and all. */
function formTag(): string {
  const match = /<form\b[^>]*>/.exec(FORM);
  assert.ok(match, 'LoginForm.tsx no longer has a <form>');
  return match[0];
}

test('the sign-in form posts, so a failed hydration cannot leak the password', () => {
  assert.match(
    formTag(),
    /method="post"/,
    'without method="post" the browser submits credentials in the query string',
  );
});

test('and it posts somewhere other than the page holding the fields', () => {
  const tag = formTag();
  const action = /action=\{?([^}\s>]+)/.exec(tag);
  assert.ok(action, 'the form has no action, so it would post back to /login');

  // Posting back to /login would be safe from the query string but would land
  // on a page route that does not accept POST. The dedicated route answers.
  assert.match(
    FORM,
    /\/login\/sem-javascript/,
    'the no-script fallback route is gone',
  );
});

test('the fallback route redirects rather than echoing what was posted', () => {
  const rota = readFileSync(
    path.join(__dirname, '..', 'src', 'app', 'login', 'sem-javascript', 'route.ts'),
    'utf8',
  );

  assert.match(rota, /export async function POST/, 'the route stopped accepting POST');
  // 303 makes the browser follow with a GET, so the body goes no further.
  assert.match(rota, /NextResponse\.redirect\([\s\S]*?303\)/, 'the redirect is not a 303');
  // Only `next` may be carried across; anything else would be a credential.
  assert.ok(
    !/searchParams\.set\(\s*'(email|password)'/.test(rota),
    'the route puts a credential back in the URL',
  );
});
