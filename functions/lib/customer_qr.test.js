"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_qr_js_1 = require("./customer_qr.js");
const secret = 'test-secret-that-is-long-enough';
const now = 1700000000000;
(0, node_test_1.default)('creates a signed opaque customer QR token', () => {
    const token = (0, customer_qr_js_1.createCustomerQrToken)({
        subject: 'YjA5eDFlM2Y0ZzVoNmk3',
        issuedAt: now,
        expiresAt: now + 60000,
        secret,
    });
    strict_1.default.deepEqual((0, customer_qr_js_1.verifyCustomerQrToken)({ token, secret, now }), {
        subject: 'YjA5eDFlM2Y0ZzVoNmk3',
        issuedAt: now,
        expiresAt: now + 60000,
    });
});
(0, node_test_1.default)('rejects forged and expired customer QR tokens', () => {
    const token = (0, customer_qr_js_1.createCustomerQrToken)({
        subject: 'YjA5eDFlM2Y0ZzVoNmk3',
        issuedAt: now,
        expiresAt: now + 60000,
        secret,
    });
    const lastCharacter = token[token.length - 1];
    const forged = `${token.slice(0, -1)}${lastCharacter === 'A' ? 'B' : 'A'}`;
    strict_1.default.equal((0, customer_qr_js_1.verifyCustomerQrToken)({
        token: forged,
        secret,
        now,
    }), null);
    strict_1.default.equal((0, customer_qr_js_1.verifyCustomerQrToken)({ token, secret, now: now + 60000 }), null);
});
