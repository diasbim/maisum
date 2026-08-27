import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizeCustomerPushToken } from './customer_push_tokens.js';

const token = 'a'.repeat(140);

test('normalizes a supported FCM registration token', () => {
  assert.deepEqual(
    normalizeCustomerPushToken({ platform: 'android', token: ` ${token} ` }),
    { platform: 'android', token },
  );
});

test('rejects unknown platforms, malformed tokens, and client identifiers', () => {
  for (const payload of [
    { platform: 'ANDROID', token },
    { platform: 'android', token: 'short' },
    { platform: 'ios', token: `${token}!` },
    { platform: 'web', token, firebase_uid: 'attacker' },
    { platform: 'web', token, canonical_customer_id: 'attacker' },
  ]) {
    assert.throws(
      () => normalizeCustomerPushToken(payload),
      { message: 'invalid_push_token_payload' },
    );
  }
});
