import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  businessGrantsAccess,
  canAccessBusiness,
  merchantIdsFromClaims,
  withMerchantClaim,
} from './merchant_access';

const USER = { uid: 'user-1', phoneNumber: '+258840000123' };

/* ------------------------------------------------------------------- claims */

test('both singular claim spellings are honoured', () => {
  assert.deepEqual(merchantIdsFromClaims({ merchant_id: 'm-1' }), ['m-1']);
  assert.deepEqual(merchantIdsFromClaims({ merchantId: 'm-1' }), ['m-1']);
});

test('both list claim spellings are honoured', () => {
  assert.deepEqual(merchantIdsFromClaims({ merchant_ids: ['m-1', 'm-2'] }), [
    'm-1',
    'm-2',
  ]);
  assert.deepEqual(merchantIdsFromClaims({ merchantIds: ['m-3'] }), ['m-3']);
});

test('the singular claim leads, and duplicates collapse', () => {
  // The first id is the business the portal opens on, so order matters.
  assert.deepEqual(
    merchantIdsFromClaims({ merchant_id: 'm-1', merchant_ids: ['m-2', 'm-1'] }),
    ['m-1', 'm-2'],
  );
});

test('blank and non-string claims yield nothing', () => {
  assert.deepEqual(merchantIdsFromClaims({ merchant_id: '   ' }), []);
  assert.deepEqual(merchantIdsFromClaims({ merchant_id: 42 }), []);
  assert.deepEqual(merchantIdsFromClaims({ merchant_ids: 'm-1' }), []);
  assert.deepEqual(merchantIdsFromClaims({ merchant_ids: [1, null] }), []);
  for (const claims of [null, undefined, 'x', 7, []]) {
    assert.deepEqual(merchantIdsFromClaims(claims), []);
  }
});

/* ------------------------------------------------------------- the document */

test('either owner field grants access', () => {
  assert.equal(businessGrantsAccess({ owner_user_id: 'user-1' }, USER), true);
  assert.equal(businessGrantsAccess({ firebase_uid: 'user-1' }, USER), true);
});

test('a different owner does not', () => {
  assert.equal(businessGrantsAccess({ owner_user_id: 'someone' }, USER), false);
  assert.equal(businessGrantsAccess({}, USER), false);
  assert.equal(businessGrantsAccess(null, USER), false);
});

test('the phone must match exactly, as it does in the rules', () => {
  assert.equal(businessGrantsAccess({ phone: '+258840000123' }, USER), true);
  // Normalizing here but not in the rules would hand out access the rules
  // would refuse, which is worse than refusing both.
  assert.equal(businessGrantsAccess({ phone: '840000123' }, USER), false);
  assert.equal(businessGrantsAccess({ phone: ' +258840000123' }, USER), false);
});

test('a user with no phone is never matched by the phone path', () => {
  const noPhone = { uid: 'user-1', phoneNumber: null };
  assert.equal(businessGrantsAccess({ phone: '+258840000123' }, noPhone), false);
  assert.equal(businessGrantsAccess({ phone: '' }, { uid: 'u', phoneNumber: '' }), false);
});

/* --------------------------------------------------------------- the gate */

test('a business bootstrapped under the uid is accessible', () => {
  // The app creates businesses/{uid}; refusing that would lock out everyone
  // who signed up before claims existed.
  assert.equal(canAccessBusiness('user-1', {}, null, USER), true);
});

test('each path opens the gate on its own', () => {
  assert.equal(canAccessBusiness('m-1', { merchant_id: 'm-1' }, null, USER), true);
  assert.equal(canAccessBusiness('m-1', {}, { owner_user_id: 'user-1' }, USER), true);
  assert.equal(canAccessBusiness('m-1', {}, { phone: '+258840000123' }, USER), true);
});

test('an unrelated business stays shut', () => {
  assert.equal(canAccessBusiness('m-9', { merchant_id: 'm-1' }, {}, USER), false);
  assert.equal(canAccessBusiness('m-9', {}, { owner_user_id: 'other' }, USER), false);
  assert.equal(canAccessBusiness('', {}, {}, USER), false);
});

/* -------------------------------------------------------- parity with rules */

/**
 * The rules are the authority for direct client reads; this module is the
 * authority for /merchant/*, which bypasses them. Drift between the two means
 * the API serves what the rules would refuse.
 */
function rulesSource(): string {
  return readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
}

test('firestore.rules still honours every claim spelling this module reads', () => {
  const source = rulesSource();
  for (const claim of ['merchant_id', 'merchantId', 'merchant_ids', 'merchantIds']) {
    assert.ok(
      source.includes(`token.${claim}`),
      `firestore.rules must still honour the "${claim}" claim`,
    );
  }
});

test('firestore.rules still honours every owner field this module reads', () => {
  const source = rulesSource();
  for (const field of ['owner_user_id', 'firebase_uid']) {
    assert.ok(
      source.includes(`data.${field}`),
      `firestore.rules must still read the "${field}" field`,
    );
  }
});

test('firestore.rules still matches the business phone against the token', () => {
  assert.match(rulesSource(), /data\.phone == request\.auth\.token\.phone_number/);
});

/* ------------------------------------------------------- granting a claim */

test('granting writes both the list and the singular mirror', () => {
  // resolveMerchantId() and several rules read only merchant_id; writing the
  // list alone would grant access the app cannot see.
  const after = withMerchantClaim({}, 'm-1', true);
  assert.equal(after.merchant_id, 'm-1');
  assert.deepEqual(after.merchant_ids, ['m-1']);
});

test('granting a second business appends and keeps the first as primary', () => {
  const after = withMerchantClaim(withMerchantClaim({}, 'm-1', true), 'm-2', true);
  assert.equal(after.merchant_id, 'm-1');
  assert.deepEqual(after.merchant_ids, ['m-1', 'm-2']);
});

test('granting the same business twice changes nothing', () => {
  const once = withMerchantClaim({}, 'm-1', true);
  assert.deepEqual(withMerchantClaim(once, 'm-1', true), once);
});

test('revoking the last business clears both keys', () => {
  const after = withMerchantClaim(withMerchantClaim({}, 'm-1', true), 'm-1', false);
  assert.equal('merchant_id' in after, false);
  assert.equal('merchant_ids' in after, false);
});

test('revoking one of two promotes the survivor', () => {
  const two = withMerchantClaim(withMerchantClaim({}, 'm-1', true), 'm-2', true);
  const after = withMerchantClaim(two, 'm-1', false);
  assert.equal(after.merchant_id, 'm-2');
  assert.deepEqual(after.merchant_ids, ['m-2']);
});

test('stale camelCase spellings are cleared, not left to grant access', () => {
  // The rules honour merchantId/merchantIds too, so leaving one behind would
  // keep access alive after a revoke.
  const after = withMerchantClaim(
    { merchantId: 'm-1', merchantIds: ['m-1'] },
    'm-1',
    false,
  );
  assert.equal('merchantId' in after, false);
  assert.equal('merchantIds' in after, false);
  assert.deepEqual(merchantIdsFromClaims(after), []);
});

test('other claims survive the change', () => {
  const after = withMerchantClaim({ internal_admin: true }, 'm-1', true);
  assert.equal(after.internal_admin, true);
});

test('a blank business id is refused rather than written', () => {
  assert.deepEqual(withMerchantClaim({ a: 1 }, '   ', true), { a: 1 });
});
