export type CustomerRedemptionFulfillmentState =
  | 'PENDING'
  | 'CONSUMED'
  | 'EXPIRED';

export function customerRedemptionCodeExpiresAt(
  redemption: Record<string, unknown>,
  defaultTtlMs: number,
): number {
  const explicit = redemption.redemption_code_expires_at;
  if (typeof explicit === 'number' && Number.isFinite(explicit) && explicit > 0) {
    return explicit;
  }
  const redeemedAt = redemption.redeemed_at ?? redemption.created_at;
  const issuedAt =
    typeof redeemedAt === 'number' && Number.isFinite(redeemedAt)
      ? redeemedAt
      : 0;
  return issuedAt + defaultTtlMs;
}

export function customerRedemptionFulfillmentState(
  redemption: Record<string, unknown>,
  now: number,
  defaultTtlMs: number,
): CustomerRedemptionFulfillmentState {
  if (redemption.fulfillment_status === 'CONSUMED') return 'CONSUMED';
  if (
    redemption.fulfillment_status === 'EXPIRED' ||
    customerRedemptionCodeExpiresAt(redemption, defaultTtlMs) <= now
  ) {
    return 'EXPIRED';
  }
  return 'PENDING';
}

export function supportsCustomerRedemptionReissue(
  redemption: Record<string, unknown>,
): boolean {
  return (
    typeof redemption.redemption_code === 'string' &&
    redemption.redemption_code.startsWith('r1_')
  );
}
