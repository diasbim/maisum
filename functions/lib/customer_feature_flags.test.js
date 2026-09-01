"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_feature_flags_js_1 = require("./customer_feature_flags.js");
(0, node_test_1.default)('customer feature flags default to disabled', () => {
    strict_1.default.deepEqual((0, customer_feature_flags_js_1.resolveCustomerFeatureFlags)({}), {
        customerAppEnabled: false,
        customerRedemptionEnabled: false,
        customerQrEnabled: false,
        customerNfcEnabled: false,
        customerPushEnabled: false,
        customerDeepLinksEnabled: false,
    });
});
(0, node_test_1.default)('customer feature flags only enable literal true values', () => {
    const flags = (0, customer_feature_flags_js_1.resolveCustomerFeatureFlags)({
        CUSTOMER_APP_ENABLED: 'true',
        CUSTOMER_REDEMPTION_ENABLED: 'TRUE',
        CUSTOMER_QR_ENABLED: 'true',
        CUSTOMER_NFC_ENABLED: 'true',
        CUSTOMER_PUSH_ENABLED: 'false',
        CUSTOMER_DEEP_LINKS_ENABLED: '1',
    });
    strict_1.default.equal(flags.customerAppEnabled, true);
    strict_1.default.equal(flags.customerRedemptionEnabled, false);
    strict_1.default.equal(flags.customerQrEnabled, true);
    strict_1.default.equal(flags.customerNfcEnabled, true);
    strict_1.default.equal(flags.customerPushEnabled, false);
    strict_1.default.equal(flags.customerDeepLinksEnabled, false);
});
(0, node_test_1.default)('customer rollout allow-list is optional and matches exact Firebase UIDs', () => {
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerUidAllowed)({}, 'uid-a'), true);
    const environment = { CUSTOMER_APP_ALLOWED_UIDS: 'uid-a, uid-b' };
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerUidAllowed)(environment, 'uid-a'), true);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerUidAllowed)(environment, 'uid-b'), true);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerUidAllowed)(environment, 'uid-c'), false);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerUidAllowed)(environment, 'uid'), false);
});
(0, node_test_1.default)('redemption rollout independently restricts customers and merchants', () => {
    const environment = {
        CUSTOMER_REDEMPTION_ALLOWED_UIDS: 'uid-pilot',
        CUSTOMER_REDEMPTION_ALLOWED_MERCHANT_IDS: 'merchant-pilot',
    };
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerRedemptionUidAllowed)(environment, 'uid-pilot'), true);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerRedemptionMerchantAllowed)(environment, 'merchant-pilot'), true);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerRedemptionAvailable)(environment, 'uid-pilot', ['merchant-other', 'merchant-pilot']), true);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerRedemptionAvailable)(environment, 'uid-pilot', ['merchant-other']), false);
    strict_1.default.equal((0, customer_feature_flags_js_1.isCustomerRedemptionAvailable)(environment, 'uid-other', ['merchant-pilot']), false);
});
