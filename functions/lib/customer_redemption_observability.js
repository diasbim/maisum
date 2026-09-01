"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.customerRedemptionLogRecord = customerRedemptionLogRecord;
exports.logCustomerRedemptionEvent = logCustomerRedemptionEvent;
function customerRedemptionLogRecord(input) {
    const record = {
        event: 'customer_redemption_lifecycle',
        lifecycle_event: input.event,
        surface: input.surface,
    };
    if (input.merchantId)
        record.merchant_id = input.merchantId;
    if (input.redemptionId)
        record.redemption_id = input.redemptionId;
    if (input.fulfillmentStatus) {
        record.fulfillment_status = input.fulfillmentStatus;
    }
    if (input.reason)
        record.reason = input.reason;
    return record;
}
function logCustomerRedemptionEvent(input) {
    console.info(customerRedemptionLogRecord(input));
}
