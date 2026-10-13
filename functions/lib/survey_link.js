"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SURVEY_LINK_TTL_MS = void 0;
exports.createSurveyLinkToken = createSurveyLinkToken;
exports.verifySurveyLinkToken = verifySurveyLinkToken;
const crypto_1 = require("crypto");
/** Long enough to survive a slow reply, short enough that a leaked link dies. */
exports.SURVEY_LINK_TTL_MS = 30 * 24 * 60 * 60 * 1000;
function sign(encodedPayload, secret) {
    return (0, crypto_1.createHmac)('sha256', secret)
        .update(`survey-link-v1.${encodedPayload}`)
        .digest('base64url');
}
/** Ids are uuids as the app writes them; anything else is not ours. */
const ID = /^[A-Za-z0-9_-]{8,128}$/;
function createSurveyLinkToken(input) {
    const payload = {
        v: 1,
        m: input.merchantId,
        s: input.surveyId,
        c: input.customerId ?? null,
        iat: input.issuedAt,
        exp: input.expiresAt,
    };
    const encodedPayload = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
    return `sl1.${encodedPayload}.${sign(encodedPayload, input.secret)}`;
}
function verifySurveyLinkToken(input) {
    const parts = input.token.split('.');
    if (parts.length !== 3 || parts[0] !== 'sl1' || !parts[1] || !parts[2]) {
        return null;
    }
    // Signature before parse: an unsigned payload is never JSON we deserialize.
    const expected = Buffer.from(sign(parts[1], input.secret));
    const received = Buffer.from(parts[2]);
    if (expected.length !== received.length ||
        !(0, crypto_1.timingSafeEqual)(expected, received)) {
        return null;
    }
    let payload;
    try {
        payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    }
    catch {
        return null;
    }
    if (payload.v !== 1 ||
        typeof payload.m !== 'string' ||
        typeof payload.s !== 'string' ||
        !ID.test(payload.m) ||
        !ID.test(payload.s) ||
        (payload.c !== null && (typeof payload.c !== 'string' || !ID.test(payload.c))) ||
        !Number.isSafeInteger(payload.iat) ||
        !Number.isSafeInteger(payload.exp) ||
        payload.iat > input.now ||
        payload.exp <= input.now ||
        payload.exp <= payload.iat) {
        return null;
    }
    return {
        merchantId: payload.m,
        surveyId: payload.s,
        customerId: payload.c,
        issuedAt: payload.iat,
        expiresAt: payload.exp,
    };
}
