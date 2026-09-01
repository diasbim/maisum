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

const NFC_CARD_UID_HEX_LENGTHS = new Set([8, 14, 20]);

export class InvalidNfcCardUidError extends Error {
  constructor(message = 'Invalid NFC card UID.') {
    super(message);
    this.name = 'InvalidNfcCardUidError';
  }
}

/**
 * Normalizes a raw UID as read from an NFC tag (which may contain
 * separators such as ':' or '-' and mixed case) into a canonical
 * upper-case hex string suitable for use as a Firestore document id.
 */
export function normalizeNfcCardUid(raw: string): string {
  if (typeof raw !== 'string') {
    throw new InvalidNfcCardUidError();
  }
  const cleaned = raw.trim().replace(/[\s:-]/g, '').toUpperCase();
  if (!isValidNfcCardUid(cleaned)) {
    throw new InvalidNfcCardUidError();
  }
  return cleaned;
}

export function isValidNfcCardUid(value: string): boolean {
  return (
    /^[0-9A-F]+$/.test(value) && NFC_CARD_UID_HEX_LENGTHS.has(value.length)
  );
}

export function tryNormalizeNfcCardUid(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  try {
    return normalizeNfcCardUid(raw);
  } catch {
    return null;
  }
}

export type NfcCardLinkSource =
  | 'self_service'
  | 'merchant_assisted'
  | 'legacy_import';

export type NfcCardEvent =
  | 'linked'
  | 'link_replayed'
  | 'link_conflict'
  | 'resolved'
  | 'resolve_not_found'
  | 'revoked'
  | 'revoke_denied'
  | 'request_rejected';

export type NfcCardLogInput = {
  event: NfcCardEvent;
  surface: 'customer' | 'merchant' | 'admin';
  merchantId?: string | null;
  cardUidLast4?: string | null;
  reason?: string | null;
};

export function nfcCardLogRecord(
  input: NfcCardLogInput,
): Record<string, string> {
  const record: Record<string, string> = {
    event: 'customer_nfc_card_lifecycle',
    lifecycle_event: input.event,
    surface: input.surface,
  };
  if (input.merchantId) record.merchant_id = input.merchantId;
  if (input.cardUidLast4) record.card_uid_last4 = input.cardUidLast4;
  if (input.reason) record.reason = input.reason;
  return record;
}

export function logCustomerNfcEvent(input: NfcCardLogInput): void {
  console.info(nfcCardLogRecord(input));
}
