import 'server-only';

import { AdminApiError, statusMessage } from './admin-api-error';
import { serverConfig } from './env';
import { getPortalSession } from './session';

/**
 * The business owner's own view, over the same API the console uses.
 *
 * The portal still never talks to Firestore directly — `/merchant/*` resolves
 * which business the caller may act as from their token, server-side, and
 * serves only that one. The caller cannot name a business they do not hold:
 * `merchant_access.ts` in the Functions is the authority, mirroring
 * `firestore.rules`.
 */

export type MerchantBusiness = {
  id: string;
  name: string | null;
};

export type MerchantProfile = {
  id: string;
  name: string | null;
  phone: string | null;
  city?: string | null;
  created_at: number | null;
  updated_at: number | null;
  plan_code: string | null;
  plan_name: string | null;
  subscription_status: string | null;
  staff_count: number;
  active_staff_count: number;
  entitlement_count?: number;
  last_operational_update_at: number | null;
};

export type MerchantEntitlement = {
  id?: string;
  feature_key: string | null;
  is_enabled: boolean | null;
  limit_value: number | null;
  unit: string | null;
  updated_at: number | null;
};

type Envelope<T> = {
  success?: boolean;
  message?: string;
  data?: T;
};

/**
 * `idToken` is passed explicitly only by the sign-in exchange, which has to ask
 * "is this person a merchant" before there is a cookie to read it from.
 * Everything else reads the session.
 */
async function call<T>(path: string, idToken?: string): Promise<Envelope<T>> {
  let token = idToken;
  if (!token) {
    const session = await getPortalSession();
    token = session?.idToken;
  }
  if (!token) {
    throw new AdminApiError(
      401,
      path,
      'A sessão expirou. Entre novamente para continuar.',
    );
  }

  const config = serverConfig();

  let response: Response;
  try {
    response = await fetch(`${config.adminApiBaseUrl}${path}`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
      cache: 'no-store',
    });
  } catch {
    console.error(`[merchant-api] unreachable: ${config.adminApiBaseUrl}${path}`);
    throw new AdminApiError(
      503,
      path,
      'O serviço não respondeu. Verifique a ligação e tente de novo.',
    );
  }

  let body: Envelope<T> | null = null;
  try {
    body = (await response.json()) as Envelope<T>;
  } catch {
    body = null;
  }

  if (!response.ok) {
    console.error(`[merchant-api] ${response.status} ${path}`, body?.message);
    // 403 here means "this account runs no business", which is a state the
    // portal explains rather than an error the operator can act on.
    throw new AdminApiError(
      response.status,
      path,
      response.status === 403
        ? 'Esta conta não está associada a nenhum negócio.'
        : (body?.message ?? statusMessage(response.status)),
    );
  }

  if (body === null) {
    throw new AdminApiError(
      502,
      path,
      'A resposta não pôde ser lida. Tente de novo.',
    );
  }

  return body;
}

/** Every business this account may act as. Empty means "not a merchant". */
export async function fetchMyBusinesses(
  idToken?: string,
): Promise<MerchantBusiness[]> {
  try {
    const body = await call<MerchantBusiness[]>('/merchant/businesses', idToken);
    return body.data ?? [];
  } catch (caught) {
    // The guard asks this question before deciding whether to let someone in,
    // so "no" has to be an answer rather than a crash.
    if (caught instanceof AdminApiError && caught.status === 403) return [];
    throw caught;
  }
}

export async function fetchMyProfile(): Promise<MerchantProfile | null> {
  const body = await call<MerchantProfile>('/merchant/profile');
  return body.data ?? null;
}

export async function fetchMyEntitlements(): Promise<MerchantEntitlement[]> {
  const body = await call<MerchantEntitlement[]>('/merchant/entitlements');
  return body.data ?? [];
}
