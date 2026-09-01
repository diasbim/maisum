"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.customerRedemptionCodeExpiresAt = customerRedemptionCodeExpiresAt;
exports.customerRedemptionFulfillmentState = customerRedemptionFulfillmentState;
exports.supportsCustomerRedemptionReissue = supportsCustomerRedemptionReissue;
function customerRedemptionCodeExpiresAt(redemption, defaultTtlMs) {
    const explicit = redemption.redemption_code_expires_at;
    if (typeof explicit === 'number' && Number.isFinite(explicit) && explicit > 0) {
        return explicit;
    }
    const redeemedAt = redemption.redeemed_at ?? redemption.created_at;
    const issuedAt = typeof redeemedAt === 'number' && Number.isFinite(redeemedAt)
        ? redeemedAt
        : 0;
    return issuedAt + defaultTtlMs;
}
function customerRedemptionFulfillmentState(redemption, now, defaultTtlMs) {
    if (redemption.fulfillment_status === 'CONSUMED')
        return 'CONSUMED';
    if (redemption.fulfillment_status === 'EXPIRED' ||
        customerRedemptionCodeExpiresAt(redemption, defaultTtlMs) <= now) {
        return 'EXPIRED';
    }
    return 'PENDING';
}
function supportsCustomerRedemptionReissue(redemption) {
    return (typeof redemption.redemption_code === 'string' &&
        redemption.redemption_code.startsWith('r1_'));
}
