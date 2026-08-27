export type AuthenticatedRequestActor = 'MERCHANT' | 'CUSTOMER';

type AuthenticatedRequestScopeInput = {
  path: string;
  resolvedMerchantId: string | null;
  hasAdminAccess: boolean;
  supportsBodyMerchantScope: boolean;
};

type AuthenticatedRequestScope = {
  actor: AuthenticatedRequestActor;
  merchantId: string;
  hasRequiredScope: boolean;
};

export function resolveAuthenticatedRequestScope(
  input: AuthenticatedRequestScopeInput,
): AuthenticatedRequestScope {
  const isCustomerPath =
    input.path === '/customer' || input.path.startsWith('/customer/');
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
    hasRequiredScope:
      input.resolvedMerchantId != null ||
      input.hasAdminAccess ||
      input.supportsBodyMerchantScope,
  };
}
