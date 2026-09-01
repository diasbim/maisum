"use strict";
/**
 * Physical NFC card identification.
 *
 * Cards are identified by their factory UID (NTAG21x / Mifare, 4, 7 or 10
 * bytes). The UID is not a secret and is not cryptographically bound to the
 * card (a UID can, in principle, be cloned), so linking/resolution routes
 * must always re-check authorization (merchant access, account ownership)
 * on every call instead of trusting the UID alone. See customer_qr.ts for
 * the equivalent rotating-token flow used by QR codes.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.InvalidNfcCardUidError = void 0;
exports.normalizeNfcCardUid = normalizeNfcCardUid;
exports.isValidNfcCardUid = isValidNfcCardUid;
exports.tryNormalizeNfcCardUid = tryNormalizeNfcCardUid;
exports.nfcCardLogRecord = nfcCardLogRecord;
exports.logCustomerNfcEvent = logCustomerNfcEvent;
const NFC_CARD_UID_HEX_LENGTHS = new Set([8, 14, 20]);
class InvalidNfcCardUidError extends Error {
    constructor(message = 'Invalid NFC card UID.') {
        super(message);
        this.name = 'InvalidNfcCardUidError';
    }
}
exports.InvalidNfcCardUidError = InvalidNfcCardUidError;
/**
 * Normalizes a raw UID as read from an NFC tag (which may contain
 * separators such as ':' or '-' and mixed case) into a canonical
 * upper-case hex string suitable for use as a Firestore document id.
 */
function normalizeNfcCardUid(raw) {
    if (typeof raw !== 'string') {
        throw new InvalidNfcCardUidError();
    }
    const cleaned = raw.trim().replace(/[\s:-]/g, '').toUpperCase();
    if (!isValidNfcCardUid(cleaned)) {
        throw new InvalidNfcCardUidError();
    }
    return cleaned;
}
function isValidNfcCardUid(value) {
    return (/^[0-9A-F]+$/.test(value) && NFC_CARD_UID_HEX_LENGTHS.has(value.length));
}
function tryNormalizeNfcCardUid(raw) {
    if (typeof raw !== 'string')
        return null;
    try {
        return normalizeNfcCardUid(raw);
    }
    catch {
        return null;
    }
}
function nfcCardLogRecord(input) {
    const record = {
        event: 'customer_nfc_card_lifecycle',
        lifecycle_event: input.event,
        surface: input.surface,
    };
    if (input.merchantId)
        record.merchant_id = input.merchantId;
    if (input.cardUidLast4)
        record.card_uid_last4 = input.cardUidLast4;
    if (input.reason)
        record.reason = input.reason;
    return record;
}
function logCustomerNfcEvent(input) {
    console.info(nfcCardLogRecord(input));
}
