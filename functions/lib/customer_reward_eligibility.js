"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isCustomerRewardExpired = isCustomerRewardExpired;
function isCustomerRewardExpired(reward, now = Date.now()) {
    const raw = reward.expires_at ?? reward.expiresAt;
    return typeof raw === 'number' &&
        Number.isFinite(raw) &&
        raw > 0 &&
        raw <= now;
}
