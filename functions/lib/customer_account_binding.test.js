"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_account_binding_js_1 = require("./customer_account_binding.js");
(0, node_test_1.default)('allows a new customer account binding', () => {
    strict_1.default.equal((0, customer_account_binding_js_1.findCustomerAccountBindingConflict)({
        firebaseUid: 'uid-a',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: null,
        existingIdentityFirebaseUid: null,
    }), null);
});
(0, node_test_1.default)('allows an idempotent customer account binding', () => {
    strict_1.default.equal((0, customer_account_binding_js_1.findCustomerAccountBindingConflict)({
        firebaseUid: 'uid-a',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: 'canonical-a',
        existingIdentityFirebaseUid: 'uid-a',
    }), null);
});
(0, node_test_1.default)('rejects an account already bound to another canonical identity', () => {
    strict_1.default.equal((0, customer_account_binding_js_1.findCustomerAccountBindingConflict)({
        firebaseUid: 'uid-a',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: 'canonical-b',
        existingIdentityFirebaseUid: null,
    }), 'account_identity_mismatch');
});
(0, node_test_1.default)('rejects a canonical identity already owned by another account', () => {
    strict_1.default.equal((0, customer_account_binding_js_1.findCustomerAccountBindingConflict)({
        firebaseUid: 'uid-a',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: null,
        existingIdentityFirebaseUid: 'uid-b',
    }), 'identity_account_mismatch');
});
(0, node_test_1.default)('deterministic transaction retry preserves the first canonical owner', () => {
    const first = (0, customer_account_binding_js_1.applyCustomerAccountBinding)({
        firebaseUid: 'uid-a',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: null,
        existingIdentityFirebaseUid: null,
    });
    strict_1.default.deepEqual(first, {
        accountCanonicalCustomerId: 'canonical-a',
        identityFirebaseUid: 'uid-a',
    });
    strict_1.default.throws(() => (0, customer_account_binding_js_1.applyCustomerAccountBinding)({
        firebaseUid: 'uid-b',
        canonicalCustomerId: 'canonical-a',
        existingAccountCanonicalCustomerId: null,
        existingIdentityFirebaseUid: first.identityFirebaseUid,
    }), { message: 'identity_account_mismatch' });
});
