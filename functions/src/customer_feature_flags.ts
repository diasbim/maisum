export type CustomerFeatureFlags = {
  customerAppEnabled: boolean;
  customerRedemptionEnabled: boolean;
  customerQrEnabled: boolean;
  customerPushEnabled: boolean;
  customerDeepLinksEnabled: boolean;
};

export type CustomerFeatureFlagEnvironment = Record<string, string | undefined>;

function isEnabled(value: string | undefined): boolean {
  return value === 'true';
}

function isIdentifierAllowed(
  configured: string | undefined,
  identifier: string | undefined,
): boolean {
  if (configured == null || configured.trim().length === 0) return true;
  if (identifier == null || identifier.length === 0) return false;
  return configured
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
    .includes(identifier);
}

export function resolveCustomerFeatureFlags(
  environment: CustomerFeatureFlagEnvironment,
): CustomerFeatureFlags {
  return {
    customerAppEnabled: isEnabled(environment.CUSTOMER_APP_ENABLED),
    customerRedemptionEnabled: isEnabled(environment.CUSTOMER_REDEMPTION_ENABLED),
    customerQrEnabled: isEnabled(environment.CUSTOMER_QR_ENABLED),
    customerPushEnabled: isEnabled(environment.CUSTOMER_PUSH_ENABLED),
    customerDeepLinksEnabled: isEnabled(
      environment.CUSTOMER_DEEP_LINKS_ENABLED,
    ),
  };
}

export function isCustomerUidAllowed(
  environment: CustomerFeatureFlagEnvironment,
  firebaseUid: string,
): boolean {
  return isIdentifierAllowed(
    environment.CUSTOMER_APP_ALLOWED_UIDS,
    firebaseUid,
  );
}

export function isCustomerRedemptionUidAllowed(
  environment: CustomerFeatureFlagEnvironment,
  firebaseUid: string | undefined,
): boolean {
  return isIdentifierAllowed(
    environment.CUSTOMER_REDEMPTION_ALLOWED_UIDS,
    firebaseUid,
  );
}

export function isCustomerRedemptionMerchantAllowed(
  environment: CustomerFeatureFlagEnvironment,
  merchantId: string | undefined,
): boolean {
  return isIdentifierAllowed(
    environment.CUSTOMER_REDEMPTION_ALLOWED_MERCHANT_IDS,
    merchantId,
  );
}

export function isCustomerRedemptionAvailable(
  environment: CustomerFeatureFlagEnvironment,
  firebaseUid: string | undefined,
  merchantIds: string[],
): boolean {
  return (
    isCustomerRedemptionUidAllowed(environment, firebaseUid) &&
    merchantIds.some((merchantId) =>
      isCustomerRedemptionMerchantAllowed(environment, merchantId))
  );
}
