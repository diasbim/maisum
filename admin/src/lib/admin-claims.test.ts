import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  adminClaimNames,
  appUserRole,
  canManageAsOwner,
  hasAdminClaims,
} from './admin-claims';

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

/* --------------------------------------------------------- who may change */

/**
 * The role, which decides whether a business screen offers a control.
 *
 * `resolveAppUserRole` in `functions/src/index.ts` is the authority and is
 * mirrored in `admin-claims.ts` for the same reason `hasAdminClaims` is: the
 * bundler will not resolve a runtime import from the Functions package. The
 * test reads that file so the mirror cannot drift.
 */
const FUNCTIONS_INDEX_TS = readFileSync(
  path.join(__dirname, '..', '..', 'functions', 'src', 'index.ts'),
  'utf8',
);

test('the role is read from the same claims the API reads', () => {
  const block = /function resolveAppUserRole\([\s\S]*?\n\}/.exec(
    FUNCTIONS_INDEX_TS,
  );
  assert.ok(block, 'resolveAppUserRole moved in index.ts');

  const names = [...block[0].matchAll(/claims\.(\w+) === 'string'/g)].map(
    (match) => match[1],
  );
  assert.ok(names.length >= 3, `found only ${names.length} claim names`);

  for (const name of names) {
    assert.equal(
      appUserRole({ [name]: 'STAFF' }),
      'STAFF',
      `${name} is read by the API and ignored here`,
    );
  }
});

test('anything that is not staff is the owner, as the API decides it', () => {
  // A business bootstrapped under the owner's own uid carries no role claim at
  // all, and the API treats that as the owner. Treating it as staff here would
  // hide every control from the person the screens are for.
  assert.equal(appUserRole(null), 'OWNER');
  assert.equal(appUserRole({}), 'OWNER');
  assert.equal(appUserRole({ role: 'owner' }), 'OWNER');
  assert.equal(appUserRole({ role: '  staff  ' }), 'STAFF');
  assert.equal(appUserRole({ app_user_role: 'staff' }), 'STAFF');
});

test('an internal admin may manage a business even as staff', () => {
  // `isOwnerOrAdminRequest` is admin OR owner, and the console's operators
  // carry a staff role on their own account often enough for this to matter.
  assert.ok(FUNCTIONS_INDEX_TS.includes('return isAdminRequest(req) || isOwnerRequest(req);'));
  assert.equal(canManageAsOwner({ role: 'staff', admin: true }), true);
  assert.equal(canManageAsOwner({ app_user_role: 'STAFF' }), false);
  assert.equal(canManageAsOwner({}), true);
});
