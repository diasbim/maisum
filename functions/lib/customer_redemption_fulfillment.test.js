"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_redemption_fulfillment_js_1 = require("./customer_redemption_fulfillment.js");
const ttl = 15 * 60 * 1000;
(0, node_test_1.default)('resolves pending, consumed, and expired redemption states', () => {
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.customerRedemptionFulfillmentState)({ redeemed_at: 1000, fulfillment_status: 'PENDING' }, 1001, ttl), 'PENDING');
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.customerRedemptionFulfillmentState)({ redeemed_at: 1000, fulfillment_status: 'CONSUMED' }, 1000 + ttl + 1, ttl), 'CONSUMED');
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.customerRedemptionFulfillmentState)({ redemption_code_expires_at: 2000 }, 2000, ttl), 'EXPIRED');
});
(0, node_test_1.default)('derives legacy expiration from the redemption timestamp', () => {
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.customerRedemptionCodeExpiresAt)({ redeemed_at: 5000 }, ttl), 5000 + ttl);
});
(0, node_test_1.default)('only customer-issued redemption codes support reissue', () => {
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.supportsCustomerRedemptionReissue)({
        redemption_code: 'r1_abcdefghijklmnopqrstuvwx',
    }), true);
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.supportsCustomerRedemptionReissue)({}), false);
    strict_1.default.equal((0, customer_redemption_fulfillment_js_1.supportsCustomerRedemptionReissue)({ redemption_code: 'merchant-code' }), false);
});
