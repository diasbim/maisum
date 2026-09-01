export type CustomerRedemptionEvent =
  | 'issued'
  | 'issue_replayed'
  | 'code_expired_observed'
  | 'reissued'
  | 'reissue_replayed'
  | 'reissue_skipped_pending'
  | 'merchant_resolved'
  | 'consumed'
  | 'consume_replayed'
  | 'request_rejected';

export type CustomerRedemptionLogInput = {
  event: CustomerRedemptionEvent;
  merchantId?: string | null;
  redemptionId?: string | null;
  fulfillmentStatus?: string | null;
  reason?: string | null;
  surface: 'customer' | 'merchant';
};

export function customerRedemptionLogRecord(
  input: CustomerRedemptionLogInput,
): Record<string, string> {
  const record: Record<string, string> = {
    event: 'customer_redemption_lifecycle',
    lifecycle_event: input.event,
    surface: input.surface,
  };
  if (input.merchantId) record.merchant_id = input.merchantId;
  if (input.redemptionId) record.redemption_id = input.redemptionId;
  if (input.fulfillmentStatus) {
    record.fulfillment_status = input.fulfillmentStatus;
  }
  if (input.reason) record.reason = input.reason;
  return record;
}

export function logCustomerRedemptionEvent(
  input: CustomerRedemptionLogInput,
): void {
  console.info(customerRedemptionLogRecord(input));
}
