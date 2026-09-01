import assert from 'node:assert/strict';
import test from 'node:test';

import {
  allowedOrigins,
  DEFAULT_ALLOWED_ORIGINS,
  LOCAL_ORIGIN_PATTERN,
  PRIMARY_SITE_ORIGIN,
  runningInEmulator,
} from './cors_origins.js';

test('defaults to the known production origins', () => {
  const origins = allowedOrigins({}, false);
  assert.deepEqual(origins, [...DEFAULT_ALLOWED_ORIGINS]);
  assert.ok(origins.includes(PRIMARY_SITE_ORIGIN));
});

test('localhost is never allowed off the emulator', () => {
  // The whole point of the lockdown. localhost is an origin an attacker can
  // serve from the victim's own machine, so it must not survive into a deploy.
  const deployed = allowedOrigins({}, false);
  assert.equal(deployed.some((origin) => origin instanceof RegExp), false);

  const local = allowedOrigins({}, true);
  assert.ok(local.some((origin) => origin instanceof RegExp));
});

test('the local pattern matches dev servers and nothing that merely looks like one', () => {
  for (const origin of [
    'http://localhost',
    'http://localhost:3200',
    'http://127.0.0.1:5099',
  ]) {
    assert.ok(LOCAL_ORIGIN_PATTERN.test(origin), origin);
  }

  for (const origin of [
    'http://localhost.evil.com',
    'https://localhost.attacker.io',
    'http://127.0.0.1.evil.com',
    'http://notlocalhost',
  ]) {
    assert.equal(LOCAL_ORIGIN_PATTERN.test(origin), false, origin);
  }
});

test('configuration replaces the defaults instead of adding to them', () => {
  // Adding would leave a deployment on another hostname still trusting this
  // one, which is the opposite of what configuring it is for.
  const origins = allowedOrigins(
    { CORS_ALLOWED_ORIGINS: 'https://outro.example' },
    false,
  );
  assert.deepEqual(origins, ['https://outro.example']);
  assert.equal(origins.includes(PRIMARY_SITE_ORIGIN), false);
});

test('configuration accepts a list and normalizes it', () => {
  const origins = allowedOrigins(
    {
      CORS_ALLOWED_ORIGINS:
        ' https://a.example/ , https://b.example ,, https://c.example//  ',
    },
    false,
  );
  assert.deepEqual(origins, [
    'https://a.example',
    'https://b.example',
    'https://c.example',
  ]);
});

test('a blank or malformed setting falls back to the defaults rather than to nothing', () => {
  // An empty allowlist would reject every browser request, which reads as an
  // outage rather than as a configuration mistake.
  for (const raw of ['', '   ', ',,,', undefined]) {
    assert.deepEqual(
      allowedOrigins({ CORS_ALLOWED_ORIGINS: raw }, false),
      [...DEFAULT_ALLOWED_ORIGINS],
      JSON.stringify(raw),
    );
  }
});

test('emulator detection covers both signals the suite sets', () => {
  assert.equal(runningInEmulator({}), false);
  assert.equal(runningInEmulator({ FUNCTIONS_EMULATOR: 'true' }), true);
  assert.equal(
    runningInEmulator({ FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' }),
    true,
  );
  assert.equal(runningInEmulator({ FUNCTIONS_EMULATOR: 'false' }), false);
});
