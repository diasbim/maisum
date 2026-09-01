import assert from 'node:assert/strict';
import test from 'node:test';
import {
  InvalidNfcCardUidError,
  isValidNfcCardUid,
  normalizeNfcCardUid,
  nfcCardLogRecord,
  tryNormalizeNfcCardUid,
} from './customer_nfc.js';

test('normalizes UIDs with separators and mixed case', () => {
  assert.equal(normalizeNfcCardUid('04:a2:2c:9b'), '04A22C9B');
  assert.equal(normalizeNfcCardUid('04-a2-2c-9b-7e-11-80'), '04A22C9B7E1180');
  assert.equal(normalizeNfcCardUid(' 04a22c9b '), '04A22C9B');
});

test('accepts the three common UID byte lengths (4, 7, 10 bytes)', () => {
  assert.ok(isValidNfcCardUid('04A22C9B'));
  assert.ok(isValidNfcCardUid('04A22C9B7E1180'));
  assert.ok(isValidNfcCardUid('04A22C9B7E11803344'.padEnd(20, '0')));
});

test('rejects invalid UIDs', () => {
  assert.throws(() => normalizeNfcCardUid(''), InvalidNfcCardUidError);
  assert.throws(() => normalizeNfcCardUid('ZZZZZZZZ'), InvalidNfcCardUidError);
  assert.throws(() => normalizeNfcCardUid('04A22C'), InvalidNfcCardUidError);
  assert.throws(
    () => normalizeNfcCardUid('04A22C9B0'),
    InvalidNfcCardUidError,
  );
  assert.equal(tryNormalizeNfcCardUid(123 as unknown as string), null);
  assert.equal(tryNormalizeNfcCardUid('not-hex'), null);
});

test('builds structured log records without leaking full UID', () => {
  const record = nfcCardLogRecord({
    event: 'linked',
    surface: 'merchant',
    merchantId: 'biz_1',
    cardUidLast4: '9B7E',
  });
  assert.equal(record.event, 'customer_nfc_card_lifecycle');
  assert.equal(record.lifecycle_event, 'linked');
  assert.equal(record.surface, 'merchant');
  assert.equal(record.merchant_id, 'biz_1');
  assert.equal(record.card_uid_last4, '9B7E');
});
