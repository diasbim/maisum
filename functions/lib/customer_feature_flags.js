"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveCustomerFeatureFlags = resolveCustomerFeatureFlags;
exports.isCustomerUidAllowed = isCustomerUidAllowed;
exports.isCustomerRedemptionUidAllowed = isCustomerRedemptionUidAllowed;
exports.isCustomerRedemptionMerchantAllowed = isCustomerRedemptionMerchantAllowed;
exports.isCustomerRedemptionAvailable = isCustomerRedemptionAvailable;
function isEnabled(value) {
    return value === 'true';
}
function isIdentifierAllowed(configured, identifier) {
    if (configured == null || configured.trim().length === 0)
        return true;
    if (identifier == null || identifier.length === 0)
        return false;
    return configured
        .split(',')
        .map((value) => value.trim())
        .filter((value) => value.length > 0)
        .includes(identifier);
}
function resolveCustomerFeatureFlags(environment) {
    return {
        customerAppEnabled: isEnabled(environment.CUSTOMER_APP_ENABLED),
        customerRedemptionEnabled: isEnabled(environment.CUSTOMER_REDEMPTION_ENABLED),
        customerQrEnabled: isEnabled(environment.CUSTOMER_QR_ENABLED),
        customerPushEnabled: isEnabled(environment.CUSTOMER_PUSH_ENABLED),
        customerDeepLinksEnabled: isEnabled(environment.CUSTOMER_DEEP_LINKS_ENABLED),
    };
}
function isCustomerUidAllowed(environment, firebaseUid) {
    return isIdentifierAllowed(environment.CUSTOMER_APP_ALLOWED_UIDS, firebaseUid);
}
function isCustomerRedemptionUidAllowed(environment, firebaseUid) {
    return isIdentifierAllowed(environment.CUSTOMER_REDEMPTION_ALLOWED_UIDS, firebaseUid);
}
function isCustomerRedemptionMerchantAllowed(environment, merchantId) {
    return isIdentifierAllowed(environment.CUSTOMER_REDEMPTION_ALLOWED_MERCHANT_IDS, merchantId);
}
function isCustomerRedemptionAvailable(environment, firebaseUid, merchantIds) {
    return (isCustomerRedemptionUidAllowed(environment, firebaseUid) &&
        merchantIds.some((merchantId) => isCustomerRedemptionMerchantAllowed(environment, merchantId)));
}
