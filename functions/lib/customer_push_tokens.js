"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeCustomerPushToken = normalizeCustomerPushToken;
const supportedPlatforms = new Set([
    'android',
    'ios',
    'web',
]);
const fcmTokenPattern = /^[A-Za-z0-9_:-]+$/;
function normalizeCustomerPushToken(value) {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('invalid_push_token_payload');
    }
    const payload = value;
    const keys = Object.keys(payload);
    if (keys.length !== 2 ||
        !keys.includes('platform') ||
        !keys.includes('token')) {
        throw new Error('invalid_push_token_payload');
    }
    const platform = typeof payload.platform === 'string' ? payload.platform.trim() : '';
    const token = typeof payload.token === 'string' ? payload.token.trim() : '';
    if (!supportedPlatforms.has(platform) ||
        token.length < 20 ||
        token.length > 4096 ||
        !fcmTokenPattern.test(token)) {
        throw new Error('invalid_push_token_payload');
    }
    return { platform: platform, token };
}
