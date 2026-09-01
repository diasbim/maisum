"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_nfc_js_1 = require("./customer_nfc.js");
(0, node_test_1.default)('normalizes UIDs with separators and mixed case', () => {
    strict_1.default.equal((0, customer_nfc_js_1.normalizeNfcCardUid)('04:a2:2c:9b'), '04A22C9B');
    strict_1.default.equal((0, customer_nfc_js_1.normalizeNfcCardUid)('04-a2-2c-9b-7e-11-80'), '04A22C9B7E1180');
    strict_1.default.equal((0, customer_nfc_js_1.normalizeNfcCardUid)(' 04a22c9b '), '04A22C9B');
});
(0, node_test_1.default)('accepts the three common UID byte lengths (4, 7, 10 bytes)', () => {
    strict_1.default.ok((0, customer_nfc_js_1.isValidNfcCardUid)('04A22C9B'));
    strict_1.default.ok((0, customer_nfc_js_1.isValidNfcCardUid)('04A22C9B7E1180'));
    strict_1.default.ok((0, customer_nfc_js_1.isValidNfcCardUid)('04A22C9B7E11803344'.padEnd(20, '0')));
});
(0, node_test_1.default)('rejects invalid UIDs', () => {
    strict_1.default.throws(() => (0, customer_nfc_js_1.normalizeNfcCardUid)(''), customer_nfc_js_1.InvalidNfcCardUidError);
    strict_1.default.throws(() => (0, customer_nfc_js_1.normalizeNfcCardUid)('ZZZZZZZZ'), customer_nfc_js_1.InvalidNfcCardUidError);
    strict_1.default.throws(() => (0, customer_nfc_js_1.normalizeNfcCardUid)('04A22C'), customer_nfc_js_1.InvalidNfcCardUidError);
    strict_1.default.throws(() => (0, customer_nfc_js_1.normalizeNfcCardUid)('04A22C9B0'), customer_nfc_js_1.InvalidNfcCardUidError);
    strict_1.default.equal((0, customer_nfc_js_1.tryNormalizeNfcCardUid)(123), null);
    strict_1.default.equal((0, customer_nfc_js_1.tryNormalizeNfcCardUid)('not-hex'), null);
});
(0, node_test_1.default)('builds structured log records without leaking full UID', () => {
    const record = (0, customer_nfc_js_1.nfcCardLogRecord)({
        event: 'linked',
        surface: 'merchant',
        merchantId: 'biz_1',
        cardUidLast4: '9B7E',
    });
    strict_1.default.equal(record.event, 'customer_nfc_card_lifecycle');
    strict_1.default.equal(record.lifecycle_event, 'linked');
    strict_1.default.equal(record.surface, 'merchant');
    strict_1.default.equal(record.merchant_id, 'biz_1');
    strict_1.default.equal(record.card_uid_last4, '9B7E');
});
