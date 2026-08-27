import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyCustomerAccountBinding,
  findCustomerAccountBindingConflict,
} from './customer_account_binding.js';

test('allows a new customer account binding', () => {
  assert.equal(
    findCustomerAccountBindingConflict({
      firebaseUid: 'uid-a',
      canonicalCustomerId: 'canonical-a',
      existingAccountCanonicalCustomerId: null,
      existingIdentityFirebaseUid: null,
    }),
    null,
  );
});

test('allows an idempotent customer account binding', () => {
  assert.equal(
    findCustomerAccountBindingConflict({
      firebaseUid: 'uid-a',
      canonicalCustomerId: 'canonical-a',
      existingAccountCanonicalCustomerId: 'canonical-a',
      existingIdentityFirebaseUid: 'uid-a',
    }),
    null,
  );
});

test('rejects an account already bound to another canonical identity', () => {
  assert.equal(
    findCustomerAccountBindingConflict({
      firebaseUid: 'uid-a',
      canonicalCustomerId: 'canonical-a',
      existingAccountCanonicalCustomerId: 'canonical-b',
      existingIdentityFirebaseUid: null,
    }),
    'account_identity_mismatch',
  );
});

test('rejects a canonical identity already owned by another account', () => {
  assert.equal(
    findCustomerAccountBindingConflict({
      firebaseUid: 'uid-a',
      canonicalCustomerId: 'canonical-a',
      existingAccountCanonicalCustomerId: null,
      existingIdentityFirebaseUid: 'uid-b',
    }),
    'identity_account_mismatch',
  );
});

test('deterministic transaction retry preserves the first canonical owner', () => {
  const first = applyCustomerAccountBinding({
    firebaseUid: 'uid-a',
    canonicalCustomerId: 'canonical-a',
    existingAccountCanonicalCustomerId: null,
    existingIdentityFirebaseUid: null,
  });
  assert.deepEqual(first, {
    accountCanonicalCustomerId: 'canonical-a',
    identityFirebaseUid: 'uid-a',
  });

  assert.throws(
    () =>
      applyCustomerAccountBinding({
        firebaseUid: 'uid-b',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: null,
        existingIdentityFirebaseUid: first.identityFirebaseUid,
      }),
    { message: 'identity_account_mismatch' },
  );
});
