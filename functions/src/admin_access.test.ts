import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  adminClaimNames,
  ADMIN_API_KEY_PATHS,
  ADMIN_BOOLEAN_CLAIMS,
  ADMIN_ROLE_VALUES,
  adminApiKeyMatches,
  hasAdminClaims,
  isAdminApiKeyPath,
  matchesAdminRole,
  withAdminClaim,
} from './admin_access.js';

test('each boolean admin claim grants access when strictly true', () => {
  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    assert.equal(hasAdminClaims({ [claim]: true }), true, claim);
  }
});

test('boolean admin claims are strict about the value', () => {
  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    assert.equal(hasAdminClaims({ [claim]: false }), false, `${claim}=false`);
    assert.equal(hasAdminClaims({ [claim]: 'true' }), false, `${claim}="true"`);
    assert.equal(hasAdminClaims({ [claim]: 1 }), false, `${claim}=1`);
  }
});

test('admin role values grant access, normalized', () => {
  for (const role of ADMIN_ROLE_VALUES) {
    assert.equal(hasAdminClaims({ role }), true, role);
    assert.equal(hasAdminClaims({ role: role.toUpperCase() }), true, role);
    assert.equal(hasAdminClaims({ role: `  ${role}  ` }), true, role);
  }
});

test('internal_admin is honoured, which is what the Flutter app sends', () => {
  // lib/features/auth/presentation/auth_controller.dart -> isInternalAdminProvider
  assert.equal(hasAdminClaims({ internal_admin: true }), true);
  assert.equal(hasAdminClaims({ role: 'internal_admin' }), true);
});

test('non-admin claims are rejected', () => {
  assert.equal(hasAdminClaims({}), false);
  assert.equal(hasAdminClaims({ role: 'OWNER' }), false);
  assert.equal(hasAdminClaims({ role: 'STAFF' }), false);
  assert.equal(hasAdminClaims({ app_user_role: 'OWNER' }), false);
  assert.equal(hasAdminClaims({ administrator: true }), false);
});

test('malformed claim containers are rejected rather than throwing', () => {
  assert.equal(hasAdminClaims(undefined), false);
  assert.equal(hasAdminClaims(null), false);
  assert.equal(hasAdminClaims('admin'), false);
  assert.equal(hasAdminClaims(42), false);
});

test('matchesAdminRole ignores non-string roles', () => {
  assert.equal(matchesAdminRole(undefined), false);
  assert.equal(matchesAdminRole(null), false);
  assert.equal(matchesAdminRole(true), false);
  assert.equal(matchesAdminRole(['admin']), false);
});

// --- Parity with firestore.rules -------------------------------------------
// An admin authorized by these Functions must also be able to read Firestore.
// Before this suite existed, `internal_admin` was accepted here and rejected by
// the rules, so the admin portal could call the API but not read any data.

function readFirestoreRules(): string {
  return readFileSync(
    path.join(__dirname, '..', '..', 'firestore.rules'),
    'utf8',
  );
}

test('firestore.rules accepts every boolean admin claim', () => {
  const rules = readFirestoreRules();
  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    assert.ok(
      rules.includes(`request.auth.token.${claim} == true`),
      `firestore.rules isAdmin() must accept the "${claim}" claim`,
    );
  }
});

test('firestore.rules accepts every admin role value', () => {
  const rules = readFirestoreRules();
  for (const role of ADMIN_ROLE_VALUES) {
    assert.ok(
      rules.includes(`== '${role}'`),
      `firestore.rules must accept role "${role}"`,
    );
  }
});

test('firestore.rules normalizes the role claim like this module does', () => {
  const rules = readFirestoreRules();
  assert.ok(
    rules.includes('request.auth.token.role.trim().lower()'),
    'firestore.rules must trim and lower-case the role claim, as '
      + 'matchesAdminRole() does',
  );
});

// --- ADMIN_API_KEY scope -----------------------------------------------------

test('the admin key is accepted only on the batch automation paths', () => {
  for (const allowed of ADMIN_API_KEY_PATHS) {
    assert.equal(isAdminApiKeyPath(allowed), true, allowed);
  }
});

test('the admin key is rejected on read and commercial admin paths', () => {
  // These carry identity-bearing decisions and must not be reachable with a
  // shared secret that no audit entry can attribute to a person.
  const denied = [
    '/admin',
    '/admin/merchants',
    '/admin/merchants/abc',
    '/admin/audit-events',
    '/admin/operations/summary',
    '/admin/plans',
    '/admin/prices',
    '/admin/plans/pro/features',
    '/admin/merchants/abc/entitlements',
    '/admin/retention/policies',
  ];
  for (const path of denied) {
    assert.equal(isAdminApiKeyPath(path), false, path);
  }
});

test('the admin key is rejected on non-admin paths entirely', () => {
  for (const path of ['/customer-core/identities/lookup', '/sync/customer/1', '/customer/session']) {
    assert.equal(isAdminApiKeyPath(path), false, path);
  }
});

test('admin key path matching tolerates a trailing slash but not prefixes', () => {
  assert.equal(isAdminApiKeyPath('/admin/loyalty/ledger/backfill/'), true);
  assert.equal(isAdminApiKeyPath('/admin/loyalty/ledger/backfill/extra'), false);
  assert.equal(isAdminApiKeyPath('/admin/loyalty/ledger'), false);
  assert.equal(isAdminApiKeyPath(undefined), false);
  assert.equal(isAdminApiKeyPath(null), false);
});

test('admin key comparison requires an exact match', () => {
  assert.equal(adminApiKeyMatches('s3cret', 's3cret'), true);
  assert.equal(adminApiKeyMatches('s3cret', 's3creT'), false);
  assert.equal(adminApiKeyMatches('s3cret', 's3cret '), false);
  assert.equal(adminApiKeyMatches('s3cret', 's3'), false);
  assert.equal(adminApiKeyMatches('s3cret', 's3cret-longer'), false);
});

test('an unset or empty admin key never authenticates anything', () => {
  assert.equal(adminApiKeyMatches(undefined, 'anything'), false);
  assert.equal(adminApiKeyMatches('', ''), false);
  assert.equal(adminApiKeyMatches('', 'anything'), false);
  assert.equal(adminApiKeyMatches('s3cret', ''), false);
  assert.equal(adminApiKeyMatches('s3cret', undefined), false);
  assert.equal(adminApiKeyMatches(42, 42), false);
});

// --- Claim mutation (used by scripts/admin_claims.js) ------------------------

test('granting adds only the primary admin claim', () => {
  assert.deepEqual(withAdminClaim({}, true), { internal_admin: true });
  assert.equal(hasAdminClaims(withAdminClaim({}, true)), true);
});

test('granting preserves unrelated claims', () => {
  const before = { merchant_id: 'm1', app_user_role: 'OWNER' };
  assert.deepEqual(withAdminClaim(before, true), {
    merchant_id: 'm1',
    app_user_role: 'OWNER',
    internal_admin: true,
  });
});

test('revoking strips every accepted admin spelling, not just one', () => {
  const before = {
    admin: true,
    is_admin: true,
    internal_admin: true,
    role: 'internal_admin',
    merchant_id: 'm1',
  };
  const after = withAdminClaim(before, false);
  assert.deepEqual(after, { merchant_id: 'm1' });
  assert.equal(hasAdminClaims(after), false);
});

test('revoking keeps a non-admin role claim intact', () => {
  assert.deepEqual(withAdminClaim({ role: 'OWNER' }, false), { role: 'OWNER' });
});

test('revoking tolerates a user with no claims at all', () => {
  assert.deepEqual(withAdminClaim(undefined, false), {});
  assert.deepEqual(withAdminClaim(null, false), {});
});

test('granting does not mutate the caller object', () => {
  const before = { merchant_id: 'm1' };
  withAdminClaim(before, true);
  assert.deepEqual(before, { merchant_id: 'm1' });
});

// --- Parity with the Next.js portal -----------------------------------------
// admin/src/lib/admin-claims.ts duplicates this predicate because Next's
// bundler will not resolve a runtime import from outside its app root. The
// duplication is only acceptable while this test guards it.

function readPortalClaims(): string {
  return readFileSync(
    path.join(__dirname, '..', '..', 'admin', 'src', 'lib', 'admin-claims.ts'),
    'utf8',
  );
}

test('the portal predicate accepts every boolean admin claim', () => {
  const source = readPortalClaims();
  for (const claim of ADMIN_BOOLEAN_CLAIMS) {
    assert.ok(
      source.includes(`'${claim}'`),
      `admin/src/lib/admin-claims.ts must accept the "${claim}" claim`,
    );
  }
});

test('the portal predicate accepts every admin role value', () => {
  const source = readPortalClaims();
  for (const role of ADMIN_ROLE_VALUES) {
    assert.ok(
      source.includes(`'${role}'`),
      `admin/src/lib/admin-claims.ts must accept role "${role}"`,
    );
  }
});

test('the portal predicate normalizes the role claim the same way', () => {
  const source = readPortalClaims();
  assert.ok(
    source.includes('.trim().toLowerCase()'),
    'admin/src/lib/admin-claims.ts must trim and lower-case the role claim',
  );
});

test('adminClaimNames reports which claim grants access, not just whether one does', () => {
  assert.deepEqual(adminClaimNames({ internal_admin: true }), ['internal_admin']);
  assert.deepEqual(adminClaimNames({ role: '  Internal_Admin  ' }), [
    'role=internal_admin',
  ]);

  // Two grants at once is the case that matters when revoking: clearing only
  // one of them leaves the access in place.
  assert.deepEqual(adminClaimNames({ admin: true, role: 'admin' }), [
    'admin',
    'role=admin',
  ]);
});

test('adminClaimNames stays empty for anything that does not grant access', () => {
  assert.deepEqual(adminClaimNames(null), []);
  assert.deepEqual(adminClaimNames({}), []);
  assert.deepEqual(adminClaimNames({ admin: 'true' }), []);
  assert.deepEqual(adminClaimNames({ role: 'merchant_owner' }), []);
});

test('adminClaimNames agrees with hasAdminClaims on every input', () => {
  const cases: unknown[] = [
    null,
    {},
    { admin: true },
    { is_admin: true },
    { internal_admin: true },
    { role: 'admin' },
    { role: 'INTERNAL_ADMIN' },
    { admin: 'true' },
    { role: 'staff' },
  ];

  // The two predicates read the same claims, so a disagreement would mean the
  // console lists someone it cannot explain, or explains someone it does not
  // list.
  for (const claims of cases) {
    assert.equal(
      adminClaimNames(claims).length > 0,
      hasAdminClaims(claims),
      `disagreement for ${JSON.stringify(claims)}`,
    );
  }
});
