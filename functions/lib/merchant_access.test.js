"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const merchant_access_1 = require("./merchant_access");
const USER = { uid: 'user-1', phoneNumber: '+258840000123' };
/* ------------------------------------------------------------------- claims */
(0, node_test_1.default)('both singular claim spellings are honoured', () => {
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_id: 'm-1' }), ['m-1']);
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchantId: 'm-1' }), ['m-1']);
});
(0, node_test_1.default)('both list claim spellings are honoured', () => {
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_ids: ['m-1', 'm-2'] }), [
        'm-1',
        'm-2',
    ]);
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchantIds: ['m-3'] }), ['m-3']);
});
(0, node_test_1.default)('the singular claim leads, and duplicates collapse', () => {
    // The first id is the business the portal opens on, so order matters.
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_id: 'm-1', merchant_ids: ['m-2', 'm-1'] }), ['m-1', 'm-2']);
});
(0, node_test_1.default)('blank and non-string claims yield nothing', () => {
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_id: '   ' }), []);
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_id: 42 }), []);
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_ids: 'm-1' }), []);
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)({ merchant_ids: [1, null] }), []);
    for (const claims of [null, undefined, 'x', 7, []]) {
        strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)(claims), []);
    }
});
/* ------------------------------------------------------------- the document */
(0, node_test_1.default)('either owner field grants access', () => {
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ owner_user_id: 'user-1' }, USER), true);
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ firebase_uid: 'user-1' }, USER), true);
});
(0, node_test_1.default)('a different owner does not', () => {
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ owner_user_id: 'someone' }, USER), false);
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({}, USER), false);
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)(null, USER), false);
});
(0, node_test_1.default)('the phone must match exactly, as it does in the rules', () => {
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ phone: '+258840000123' }, USER), true);
    // Normalizing here but not in the rules would hand out access the rules
    // would refuse, which is worse than refusing both.
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ phone: '840000123' }, USER), false);
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ phone: ' +258840000123' }, USER), false);
});
(0, node_test_1.default)('a user with no phone is never matched by the phone path', () => {
    const noPhone = { uid: 'user-1', phoneNumber: null };
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ phone: '+258840000123' }, noPhone), false);
    strict_1.default.equal((0, merchant_access_1.businessGrantsAccess)({ phone: '' }, { uid: 'u', phoneNumber: '' }), false);
});
/* --------------------------------------------------------------- the gate */
(0, node_test_1.default)('a business bootstrapped under the uid is accessible', () => {
    // The app creates businesses/{uid}; refusing that would lock out everyone
    // who signed up before claims existed.
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('user-1', {}, null, USER), true);
});
(0, node_test_1.default)('each path opens the gate on its own', () => {
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('m-1', { merchant_id: 'm-1' }, null, USER), true);
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('m-1', {}, { owner_user_id: 'user-1' }, USER), true);
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('m-1', {}, { phone: '+258840000123' }, USER), true);
});
(0, node_test_1.default)('an unrelated business stays shut', () => {
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('m-9', { merchant_id: 'm-1' }, {}, USER), false);
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('m-9', {}, { owner_user_id: 'other' }, USER), false);
    strict_1.default.equal((0, merchant_access_1.canAccessBusiness)('', {}, {}, USER), false);
});
/* -------------------------------------------------------- parity with rules */
/**
 * The rules are the authority for direct client reads; this module is the
 * authority for /merchant/*, which bypasses them. Drift between the two means
 * the API serves what the rules would refuse.
 */
function rulesSource() {
    return (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
}
(0, node_test_1.default)('firestore.rules still honours every claim spelling this module reads', () => {
    const source = rulesSource();
    for (const claim of ['merchant_id', 'merchantId', 'merchant_ids', 'merchantIds']) {
        strict_1.default.ok(source.includes(`token.${claim}`), `firestore.rules must still honour the "${claim}" claim`);
    }
});
(0, node_test_1.default)('firestore.rules still honours every owner field this module reads', () => {
    const source = rulesSource();
    for (const field of ['owner_user_id', 'firebase_uid']) {
        strict_1.default.ok(source.includes(`data.${field}`), `firestore.rules must still read the "${field}" field`);
    }
});
(0, node_test_1.default)('firestore.rules still matches the business phone against the token', () => {
    strict_1.default.match(rulesSource(), /data\.phone == request\.auth\.token\.phone_number/);
});
/* ------------------------------------------------------- granting a claim */
(0, node_test_1.default)('granting writes both the list and the singular mirror', () => {
    // resolveMerchantId() and several rules read only merchant_id; writing the
    // list alone would grant access the app cannot see.
    const after = (0, merchant_access_1.withMerchantClaim)({}, 'm-1', true);
    strict_1.default.equal(after.merchant_id, 'm-1');
    strict_1.default.deepEqual(after.merchant_ids, ['m-1']);
});
(0, node_test_1.default)('granting a second business appends and keeps the first as primary', () => {
    const after = (0, merchant_access_1.withMerchantClaim)((0, merchant_access_1.withMerchantClaim)({}, 'm-1', true), 'm-2', true);
    strict_1.default.equal(after.merchant_id, 'm-1');
    strict_1.default.deepEqual(after.merchant_ids, ['m-1', 'm-2']);
});
(0, node_test_1.default)('granting the same business twice changes nothing', () => {
    const once = (0, merchant_access_1.withMerchantClaim)({}, 'm-1', true);
    strict_1.default.deepEqual((0, merchant_access_1.withMerchantClaim)(once, 'm-1', true), once);
});
(0, node_test_1.default)('revoking the last business clears both keys', () => {
    const after = (0, merchant_access_1.withMerchantClaim)((0, merchant_access_1.withMerchantClaim)({}, 'm-1', true), 'm-1', false);
    strict_1.default.equal('merchant_id' in after, false);
    strict_1.default.equal('merchant_ids' in after, false);
});
(0, node_test_1.default)('revoking one of two promotes the survivor', () => {
    const two = (0, merchant_access_1.withMerchantClaim)((0, merchant_access_1.withMerchantClaim)({}, 'm-1', true), 'm-2', true);
    const after = (0, merchant_access_1.withMerchantClaim)(two, 'm-1', false);
    strict_1.default.equal(after.merchant_id, 'm-2');
    strict_1.default.deepEqual(after.merchant_ids, ['m-2']);
});
(0, node_test_1.default)('stale camelCase spellings are cleared, not left to grant access', () => {
    // The rules honour merchantId/merchantIds too, so leaving one behind would
    // keep access alive after a revoke.
    const after = (0, merchant_access_1.withMerchantClaim)({ merchantId: 'm-1', merchantIds: ['m-1'] }, 'm-1', false);
    strict_1.default.equal('merchantId' in after, false);
    strict_1.default.equal('merchantIds' in after, false);
    strict_1.default.deepEqual((0, merchant_access_1.merchantIdsFromClaims)(after), []);
});
(0, node_test_1.default)('other claims survive the change', () => {
    const after = (0, merchant_access_1.withMerchantClaim)({ internal_admin: true }, 'm-1', true);
    strict_1.default.equal(after.internal_admin, true);
});
(0, node_test_1.default)('a blank business id is refused rather than written', () => {
    strict_1.default.deepEqual((0, merchant_access_1.withMerchantClaim)({ a: 1 }, '   ', true), { a: 1 });
});
