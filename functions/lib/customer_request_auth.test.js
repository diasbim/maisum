"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_request_auth_js_1 = require("./customer_request_auth.js");
(0, node_test_1.default)('customer API uses customer actor without merchant scope', () => {
    strict_1.default.deepEqual((0, customer_request_auth_js_1.resolveAuthenticatedRequestScope)({
        path: '/customer/session',
        resolvedMerchantId: 'firebase-uid-fallback',
        hasAdminAccess: false,
        supportsBodyMerchantScope: false,
    }), {
        actor: 'CUSTOMER',
        merchantId: '',
        hasRequiredScope: true,
    });
});
(0, node_test_1.default)('customer core remains a merchant-scoped API', () => {
    strict_1.default.deepEqual((0, customer_request_auth_js_1.resolveAuthenticatedRequestScope)({
        path: '/customer-core/identities',
        resolvedMerchantId: 'merchant-a',
        hasAdminAccess: false,
        supportsBodyMerchantScope: true,
    }), {
        actor: 'MERCHANT',
        merchantId: 'merchant-a',
        hasRequiredScope: true,
    });
});
(0, node_test_1.default)('merchant API still rejects a missing scope', () => {
    strict_1.default.deepEqual((0, customer_request_auth_js_1.resolveAuthenticatedRequestScope)({
        path: '/sync/push',
        resolvedMerchantId: null,
        hasAdminAccess: false,
        supportsBodyMerchantScope: false,
    }), {
        actor: 'MERCHANT',
        merchantId: '',
        hasRequiredScope: false,
    });
});
