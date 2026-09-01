"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const customer_redemption_observability_js_1 = require("./customer_redemption_observability.js");
(0, node_test_1.default)('redemption telemetry contains only approved operational fields', () => {
    const record = (0, customer_redemption_observability_js_1.customerRedemptionLogRecord)({
        event: 'consumed',
        merchantId: 'merchant-1',
        redemptionId: 'redemption-1',
        fulfillmentStatus: 'CONSUMED',
        surface: 'merchant',
    });
    strict_1.default.deepEqual(record, {
        event: 'customer_redemption_lifecycle',
        lifecycle_event: 'consumed',
        surface: 'merchant',
        merchant_id: 'merchant-1',
        redemption_id: 'redemption-1',
        fulfillment_status: 'CONSUMED',
    });
    strict_1.default.equal(JSON.stringify(record).includes('redemption_code'), false);
    strict_1.default.equal(JSON.stringify(record).includes('phone'), false);
    strict_1.default.equal(JSON.stringify(record).includes('name'), false);
});
