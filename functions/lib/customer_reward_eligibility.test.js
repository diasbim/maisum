"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_reward_eligibility_js_1 = require("./customer_reward_eligibility.js");
(0, node_test_1.default)('recognizes expired rewards in both supported timestamp fields', () => {
    strict_1.default.equal((0, customer_reward_eligibility_js_1.isCustomerRewardExpired)({ expires_at: 999 }, 1000), true);
    strict_1.default.equal((0, customer_reward_eligibility_js_1.isCustomerRewardExpired)({ expiresAt: 1000 }, 1000), true);
});
(0, node_test_1.default)('keeps future and missing expiration values active', () => {
    strict_1.default.equal((0, customer_reward_eligibility_js_1.isCustomerRewardExpired)({ expires_at: 1001 }, 1000), false);
    strict_1.default.equal((0, customer_reward_eligibility_js_1.isCustomerRewardExpired)({}, 1000), false);
    strict_1.default.equal((0, customer_reward_eligibility_js_1.isCustomerRewardExpired)({ expires_at: 0 }, 1000), false);
});
