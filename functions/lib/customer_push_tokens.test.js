"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_push_tokens_js_1 = require("./customer_push_tokens.js");
const token = 'a'.repeat(140);
(0, node_test_1.default)('normalizes a supported FCM registration token', () => {
    strict_1.default.deepEqual((0, customer_push_tokens_js_1.normalizeCustomerPushToken)({ platform: 'android', token: ` ${token} ` }), { platform: 'android', token });
});
(0, node_test_1.default)('rejects unknown platforms, malformed tokens, and client identifiers', () => {
    for (const payload of [
        { platform: 'ANDROID', token },
        { platform: 'android', token: 'short' },
        { platform: 'ios', token: `${token}!` },
        { platform: 'web', token, firebase_uid: 'attacker' },
        { platform: 'web', token, canonical_customer_id: 'attacker' },
    ]) {
        strict_1.default.throws(() => (0, customer_push_tokens_js_1.normalizeCustomerPushToken)(payload), { message: 'invalid_push_token_payload' });
    }
});
