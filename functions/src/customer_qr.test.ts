import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createCustomerQrToken,
  verifyCustomerQrToken,
} from './customer_qr.js';

const secret = 'test-secret-that-is-long-enough';
const now = 1_700_000_000_000;

test('creates a signed opaque customer QR token', () => {
  const token = createCustomerQrToken({
    subject: 'YjA5eDFlM2Y0ZzVoNmk3',
    issuedAt: now,
    expiresAt: now + 60_000,
    secret,
  });

  assert.deepEqual(verifyCustomerQrToken({ token, secret, now }), {
    subject: 'YjA5eDFlM2Y0ZzVoNmk3',
    issuedAt: now,
    expiresAt: now + 60_000,
  });
});

test('rejects forged and expired customer QR tokens', () => {
  const token = createCustomerQrToken({
    subject: 'YjA5eDFlM2Y0ZzVoNmk3',
    issuedAt: now,
    expiresAt: now + 60_000,
    secret,
  });
  const lastCharacter = token[token.length - 1];
  const forged = `${token.slice(0, -1)}${lastCharacter === 'A' ? 'B' : 'A'}`;

  assert.equal(
    verifyCustomerQrToken({
      token: forged,
      secret,
      now,
    }),
    null,
  );
  assert.equal(verifyCustomerQrToken({ token, secret, now: now + 60_000 }), null);
});
