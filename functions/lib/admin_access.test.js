"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const admin_access_js_1 = require("./admin_access.js");
(0, node_test_1.default)('each boolean admin claim grants access when strictly true', () => {
    for (const claim of admin_access_js_1.ADMIN_BOOLEAN_CLAIMS) {
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ [claim]: true }), true, claim);
    }
});
(0, node_test_1.default)('boolean admin claims are strict about the value', () => {
    for (const claim of admin_access_js_1.ADMIN_BOOLEAN_CLAIMS) {
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ [claim]: false }), false, `${claim}=false`);
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ [claim]: 'true' }), false, `${claim}="true"`);
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ [claim]: 1 }), false, `${claim}=1`);
    }
});
(0, node_test_1.default)('admin role values grant access, normalized', () => {
    for (const role of admin_access_js_1.ADMIN_ROLE_VALUES) {
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ role }), true, role);
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ role: role.toUpperCase() }), true, role);
        strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ role: `  ${role}  ` }), true, role);
    }
});
(0, node_test_1.default)('internal_admin is honoured, which is what the Flutter app sends', () => {
    // lib/features/auth/presentation/auth_controller.dart -> isInternalAdminProvider
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ internal_admin: true }), true);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ role: 'internal_admin' }), true);
});
(0, node_test_1.default)('non-admin claims are rejected', () => {
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({}), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ role: 'OWNER' }), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ role: 'STAFF' }), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ app_user_role: 'OWNER' }), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)({ administrator: true }), false);
});
(0, node_test_1.default)('malformed claim containers are rejected rather than throwing', () => {
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)(undefined), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)(null), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)('admin'), false);
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)(42), false);
});
(0, node_test_1.default)('matchesAdminRole ignores non-string roles', () => {
    strict_1.default.equal((0, admin_access_js_1.matchesAdminRole)(undefined), false);
    strict_1.default.equal((0, admin_access_js_1.matchesAdminRole)(null), false);
    strict_1.default.equal((0, admin_access_js_1.matchesAdminRole)(true), false);
    strict_1.default.equal((0, admin_access_js_1.matchesAdminRole)(['admin']), false);
});
// --- Parity with firestore.rules -------------------------------------------
// An admin authorized by these Functions must also be able to read Firestore.
// Before this suite existed, `internal_admin` was accepted here and rejected by
// the rules, so the admin portal could call the API but not read any data.
function readFirestoreRules() {
    return (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
}
(0, node_test_1.default)('firestore.rules accepts every boolean admin claim', () => {
    const rules = readFirestoreRules();
    for (const claim of admin_access_js_1.ADMIN_BOOLEAN_CLAIMS) {
        strict_1.default.ok(rules.includes(`request.auth.token.${claim} == true`), `firestore.rules isAdmin() must accept the "${claim}" claim`);
    }
});
(0, node_test_1.default)('firestore.rules accepts every admin role value', () => {
    const rules = readFirestoreRules();
    for (const role of admin_access_js_1.ADMIN_ROLE_VALUES) {
        strict_1.default.ok(rules.includes(`== '${role}'`), `firestore.rules must accept role "${role}"`);
    }
});
(0, node_test_1.default)('firestore.rules normalizes the role claim like this module does', () => {
    const rules = readFirestoreRules();
    strict_1.default.ok(rules.includes('request.auth.token.role.trim().lower()'), 'firestore.rules must trim and lower-case the role claim, as '
        + 'matchesAdminRole() does');
});
// --- ADMIN_API_KEY scope -----------------------------------------------------
(0, node_test_1.default)('the admin key is accepted only on the batch automation paths', () => {
    for (const allowed of admin_access_js_1.ADMIN_API_KEY_PATHS) {
        strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)(allowed), true, allowed);
    }
});
(0, node_test_1.default)('the admin key is rejected on read and commercial admin paths', () => {
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
        strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)(path), false, path);
    }
});
(0, node_test_1.default)('the admin key is rejected on non-admin paths entirely', () => {
    for (const path of ['/customer-core/identities/lookup', '/sync/customer/1', '/customer/session']) {
        strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)(path), false, path);
    }
});
(0, node_test_1.default)('admin key path matching tolerates a trailing slash but not prefixes', () => {
    strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)('/admin/loyalty/ledger/backfill/'), true);
    strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)('/admin/loyalty/ledger/backfill/extra'), false);
    strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)('/admin/loyalty/ledger'), false);
    strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)(undefined), false);
    strict_1.default.equal((0, admin_access_js_1.isAdminApiKeyPath)(null), false);
});
(0, node_test_1.default)('admin key comparison requires an exact match', () => {
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', 's3cret'), true);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', 's3creT'), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', 's3cret '), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', 's3'), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', 's3cret-longer'), false);
});
(0, node_test_1.default)('an unset or empty admin key never authenticates anything', () => {
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)(undefined, 'anything'), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('', ''), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('', 'anything'), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', ''), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)('s3cret', undefined), false);
    strict_1.default.equal((0, admin_access_js_1.adminApiKeyMatches)(42, 42), false);
});
// --- Claim mutation (used by scripts/admin_claims.js) ------------------------
(0, node_test_1.default)('granting adds only the primary admin claim', () => {
    strict_1.default.deepEqual((0, admin_access_js_1.withAdminClaim)({}, true), { internal_admin: true });
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)((0, admin_access_js_1.withAdminClaim)({}, true)), true);
});
(0, node_test_1.default)('granting preserves unrelated claims', () => {
    const before = { merchant_id: 'm1', app_user_role: 'OWNER' };
    strict_1.default.deepEqual((0, admin_access_js_1.withAdminClaim)(before, true), {
        merchant_id: 'm1',
        app_user_role: 'OWNER',
        internal_admin: true,
    });
});
(0, node_test_1.default)('revoking strips every accepted admin spelling, not just one', () => {
    const before = {
        admin: true,
        is_admin: true,
        internal_admin: true,
        role: 'internal_admin',
        merchant_id: 'm1',
    };
    const after = (0, admin_access_js_1.withAdminClaim)(before, false);
    strict_1.default.deepEqual(after, { merchant_id: 'm1' });
    strict_1.default.equal((0, admin_access_js_1.hasAdminClaims)(after), false);
});
(0, node_test_1.default)('revoking keeps a non-admin role claim intact', () => {
    strict_1.default.deepEqual((0, admin_access_js_1.withAdminClaim)({ role: 'OWNER' }, false), { role: 'OWNER' });
});
(0, node_test_1.default)('revoking tolerates a user with no claims at all', () => {
    strict_1.default.deepEqual((0, admin_access_js_1.withAdminClaim)(undefined, false), {});
    strict_1.default.deepEqual((0, admin_access_js_1.withAdminClaim)(null, false), {});
});
(0, node_test_1.default)('granting does not mutate the caller object', () => {
    const before = { merchant_id: 'm1' };
    (0, admin_access_js_1.withAdminClaim)(before, true);
    strict_1.default.deepEqual(before, { merchant_id: 'm1' });
});
// --- Parity with the Next.js portal -----------------------------------------
// admin/src/lib/admin-claims.ts duplicates this predicate because Next's
// bundler will not resolve a runtime import from outside its app root. The
// duplication is only acceptable while this test guards it.
function readPortalClaims() {
    return (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', '..', 'admin', 'src', 'lib', 'admin-claims.ts'), 'utf8');
}
(0, node_test_1.default)('the portal predicate accepts every boolean admin claim', () => {
    const source = readPortalClaims();
    for (const claim of admin_access_js_1.ADMIN_BOOLEAN_CLAIMS) {
        strict_1.default.ok(source.includes(`'${claim}'`), `admin/src/lib/admin-claims.ts must accept the "${claim}" claim`);
    }
});
(0, node_test_1.default)('the portal predicate accepts every admin role value', () => {
    const source = readPortalClaims();
    for (const role of admin_access_js_1.ADMIN_ROLE_VALUES) {
        strict_1.default.ok(source.includes(`'${role}'`), `admin/src/lib/admin-claims.ts must accept role "${role}"`);
    }
});
(0, node_test_1.default)('the portal predicate normalizes the role claim the same way', () => {
    const source = readPortalClaims();
    strict_1.default.ok(source.includes('.trim().toLowerCase()'), 'admin/src/lib/admin-claims.ts must trim and lower-case the role claim');
});
(0, node_test_1.default)('adminClaimNames reports which claim grants access, not just whether one does', () => {
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)({ internal_admin: true }), ['internal_admin']);
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)({ role: '  Internal_Admin  ' }), [
        'role=internal_admin',
    ]);
    // Two grants at once is the case that matters when revoking: clearing only
    // one of them leaves the access in place.
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)({ admin: true, role: 'admin' }), [
        'admin',
        'role=admin',
    ]);
});
(0, node_test_1.default)('adminClaimNames stays empty for anything that does not grant access', () => {
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)(null), []);
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)({}), []);
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)({ admin: 'true' }), []);
    strict_1.default.deepEqual((0, admin_access_js_1.adminClaimNames)({ role: 'merchant_owner' }), []);
});
(0, node_test_1.default)('adminClaimNames agrees with hasAdminClaims on every input', () => {
    const cases = [
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
        strict_1.default.equal((0, admin_access_js_1.adminClaimNames)(claims).length > 0, (0, admin_access_js_1.hasAdminClaims)(claims), `disagreement for ${JSON.stringify(claims)}`);
    }
});
