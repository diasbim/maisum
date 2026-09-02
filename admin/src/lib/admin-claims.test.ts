import assert from 'node:assert/strict';
import test from 'node:test';

import { adminClaimNames, hasAdminClaims } from './admin-claims';

/**
 * `functions/src/admin_access.test.ts` guards that this file still accepts the
 * same claim set, by reading its source. These tests guard the behaviour from
 * this side: that the two functions agree, and that `adminClaimNames` reports
 * every grant rather than the first one it finds.
 */

const GRANTS = [
  { admin: true },
  { is_admin: true },
  { internal_admin: true },
  { role: 'admin' },
  { role: 'internal_admin' },
  { role: '  Internal_Admin  ' },
];

const REFUSALS = [
  null,
  undefined,
  'admin',
  42,
  {},
  { admin: false },
  { admin: 'true' },
  { admin: 1 },
  { role: 'staff' },
  { role: 'administrator' },
  { role: '' },
  { role: true },
];

test('every grant opens the portal', () => {
  for (const claims of GRANTS) {
    assert.equal(hasAdminClaims(claims), true, JSON.stringify(claims));
  }
});

test('nothing else opens the portal', () => {
  for (const claims of REFUSALS) {
    assert.equal(hasAdminClaims(claims), false, JSON.stringify(claims));
  }
});

test('a boolean claim must be exactly true, not merely truthy', () => {
  // A claim set from a string would otherwise grant access by accident.
  assert.equal(hasAdminClaims({ admin: 'yes' }), false);
  assert.equal(hasAdminClaims({ is_admin: 1 }), false);
});

test('adminClaimNames names the claim, not just the fact of access', () => {
  assert.deepEqual(adminClaimNames({ internal_admin: true }), [
    'internal_admin',
  ]);
  assert.deepEqual(adminClaimNames({ role: 'admin' }), ['role=admin']);
});

test('a role is reported normalised, as it is matched', () => {
  assert.deepEqual(adminClaimNames({ role: '  Internal_Admin  ' }), [
    'role=internal_admin',
  ]);
});

test('adminClaimNames reports every grant, which is what revoking needs', () => {
  // Clearing one of two leaves the access in place, so both have to be named.
  assert.deepEqual(adminClaimNames({ admin: true, role: 'internal_admin' }), [
    'admin',
    'role=internal_admin',
  ]);
  assert.deepEqual(
    adminClaimNames({ admin: true, is_admin: true, internal_admin: true }),
    ['admin', 'is_admin', 'internal_admin'],
  );
});

test('adminClaimNames stays empty for anything that grants nothing', () => {
  for (const claims of REFUSALS) {
    assert.deepEqual(adminClaimNames(claims), [], JSON.stringify(claims));
  }
});

test('the two functions never disagree', () => {
  for (const claims of [...GRANTS, ...REFUSALS]) {
    assert.equal(
      adminClaimNames(claims).length > 0,
      hasAdminClaims(claims),
      `disagreement on ${JSON.stringify(claims)}`,
    );
  }
});
