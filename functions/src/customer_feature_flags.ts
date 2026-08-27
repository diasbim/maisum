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
  const configured = environment.CUSTOMER_APP_ALLOWED_UIDS;
  if (configured == null || configured.trim().length === 0) return true;
  return configured
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
    .includes(firebaseUid);
}
