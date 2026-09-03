import 'server-only';

import { AdminApiError, statusMessage } from './admin-api-error';
import { serverConfig } from './env';
import {
  buildListQuery,
  toMerchantList,
  type ListQuery,
  type MerchantList,
} from './merchant-list';
import { getPortalSession } from './session';

export {
  MERCHANT_PAGE_SIZE,
  type ListQuery,
  type MerchantList,
} from './merchant-list';

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

export type MerchantCustomer = {
  id: string;
  name: string | null;
  phone: string | null;
  total_points: number;
  total_visits: number;
  total_spent: number;
  average_spend: number | null;
  lifecycle_stage: string | null;
  retention_status: string | null;
  relationship_status: string | null;
  first_visit_at: number | null;
  last_visit_at: number | null;
  created_at: number | null;
  updated_at: number | null;
  archived_at: number | null;
};

export type MerchantSale = {
  id: string;
  amount: number | null;
  points: number | null;
  created_at: number | null;
  cancellation_status: string | null;
  confirmation_status: string | null;
};

export type MerchantCustomerDetail = MerchantCustomer & {
  sales: MerchantSale[];
};

export type MerchantCatalogItem = {
  id: string;
  name: string | null;
  type: string | null;
  default_price: number | null;
  is_active: boolean | null;
  display_order: number;
  created_at: number | null;
  updated_at: number | null;
};

export type MerchantReward = {
  id: string;
  name: string | null;
  description: string | null;
  points_required: number | null;
  is_active: boolean | null;
  created_at: number | null;
  updated_at: number | null;
};

export type MerchantStaff = {
  id: string;
  phone: string | null;
  role: string | null;
  status: string | null;
  created_at: number | null;
  updated_at: number | null;
  last_login_at: number | null;
};

type Envelope<T> = {
  success?: boolean;
  message?: string;
  data?: T;
  paging?: { limit?: number; offset?: number; has_more?: boolean };
  total?: number;
  truncated?: boolean;
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

/* -------------------------------------------------------------- the records */

async function callList<T>(
  path: string,
  params: ListQuery,
): Promise<MerchantList<T>> {
  return toMerchantList(await call<T[]>(`${path}${buildListQuery(params)}`));
}

/**
 * The business's own customers.
 *
 * The console has no equivalent, on purpose — internal staff can look a
 * customer up by phone and no further, so nobody inside can enumerate the
 * customer base. A business listing the customers it serves is a different
 * question: the till already holds this list offline, and the rules have
 * always allowed the owner to read it.
 */
export function fetchMyCustomers(params: ListQuery = {}) {
  return callList<MerchantCustomer>('/merchant/customers', params);
}

/** One customer with their recent visits. `null` when no such customer. */
export async function fetchMyCustomer(
  customerId: string,
): Promise<MerchantCustomerDetail | null> {
  try {
    const body = await call<MerchantCustomerDetail>(
      `/merchant/customers/${encodeURIComponent(customerId)}`,
    );
    return body.data ?? null;
  } catch (caught) {
    if (caught instanceof AdminApiError && caught.status === 404) return null;
    throw caught;
  }
}

export function fetchMyCatalog(params: ListQuery = {}) {
  return callList<MerchantCatalogItem>('/merchant/catalog', params);
}

export function fetchMyRewards(params: ListQuery = {}) {
  return callList<MerchantReward>('/merchant/rewards', params);
}

export function fetchMyTeam(params: ListQuery = {}) {
  return callList<MerchantStaff>('/merchant/team', params);
}
