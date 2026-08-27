"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveCustomerFeatureFlags = resolveCustomerFeatureFlags;
exports.isCustomerUidAllowed = isCustomerUidAllowed;
function isEnabled(value) {
    return value === 'true';
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
    const configured = environment.CUSTOMER_APP_ALLOWED_UIDS;
    if (configured == null || configured.trim().length === 0)
        return true;
    return configured
        .split(',')
        .map((value) => value.trim())
        .filter((value) => value.length > 0)
        .includes(firebaseUid);
}
