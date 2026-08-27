"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveAuthenticatedRequestScope = resolveAuthenticatedRequestScope;
function resolveAuthenticatedRequestScope(input) {
    const isCustomerPath = input.path === '/customer' || input.path.startsWith('/customer/');
    if (isCustomerPath) {
        return {
            actor: 'CUSTOMER',
            merchantId: '',
            hasRequiredScope: true,
        };
    }
    return {
        actor: 'MERCHANT',
        merchantId: input.resolvedMerchantId ?? '',
        hasRequiredScope: input.resolvedMerchantId != null ||
            input.hasAdminAccess ||
            input.supportsBodyMerchantScope,
    };
}
