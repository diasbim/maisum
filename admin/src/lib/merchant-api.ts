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
 * What a business owner reads when a request fails.
 *
 * `statusMessage` is the console's wording, and for a 5xx it names "a API de
 * administração" — a system a bakery owner has never heard of and can do
 * nothing about. Its other sentences are phrased for anyone, so only that one
 * is replaced, in the same voice this file already uses when the service is
 * unreachable.
 */
function merchantMessage(status: number): string {
  if (status >= 500) return 'O serviço falhou. Tente de novo dentro de momentos.';
  return statusMessage(status);
}

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
    // The API's own `message` is deliberately not shown here, unlike in
    // `admin-api.ts`. Every string the /merchant/* routes can send is an
    // internal English one — 'Server error', 'Business not found',
    // 'Unauthorized' — and this is the Portuguese-only side of the portal, so
    // a business owner whose page failed was reading "Server error". The line
    // above still logs it, which is where it was useful in the first place.
    //
    // 403 means "this account runs no business", which is a state the portal
    // explains rather than an error the operator can act on.
    throw new AdminApiError(
      response.status,
      path,
      response.status === 403
        ? 'Esta conta não está associada a nenhum negócio.'
        : merchantMessage(response.status),
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

/* ------------------------------------------- what the business could not see */

/**
 * The app has synced all of this up for a while; the portal read none of it.
 *
 * A merchant could see who their customers were but not what they had bought,
 * what they had redeemed, what their plan had actually consumed, or which of
 * them the retention engine had flagged. Some of it the console could already
 * see — the points ledger and the retention board both existed there — which
 * made the asymmetry the sharper half of the problem.
 */

export type MerchantSaleListItem = MerchantSale & {
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
};

export type SalesTotals = {
  count: number;
  amount: number;
  points: number;
};

export type MerchantRedemption = {
  id: string;
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
  reward_id: string | null;
  /** Joined by the API from the rewards subcollection. */
  reward_name: string | null;
  points_spent: number | null;
  redeemed_at: number | null;
  status: string | null;
};

export type MerchantAppointment = {
  id: string;
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
  scheduled_date: number | null;
  status: string | null;
  source: string | null;
  reminder_sent: boolean | null;
  created_at: number | null;
};

export type MerchantLedgerEntry = {
  id: string;
  customer_id: string | null;
  entry_type: string | null;
  points_delta: number | null;
  source_type: string | null;
  source_id: string | null;
  balance_after: number | null;
  occurred_at: number | null;
};

export type MerchantUsageBalance = {
  id: string;
  metric_key: string | null;
  used: number;
  limit_value: number | null;
  soft_limit: boolean | null;
  window_start: number | null;
  window_end: number | null;
  updated_at: number | null;
};

export type MerchantRiskScore = {
  id: string;
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
  days_since_visit: number;
  risk_level: string | null;
  priority: number;
  updated_at: number | null;
};

export type MerchantRecoveryTask = {
  id: string;
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
  priority: string | null;
  status: string | null;
  due_at: number | null;
  notes: string | null;
  created_at: number | null;
};

export type MerchantVisitReport = {
  id: string;
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
  task_id: string | null;
  result: string | null;
  notes: string | null;
  visited_at: number | null;
};

export type MerchantSurvey = {
  id: string;
  title: string | null;
  description: string | null;
  is_active: boolean | null;
  response_count: number;
  created_at: number | null;
  updated_at: number | null;
};

export type MerchantReturnBonus = {
  id: string;
  customer_id: string | null;
  /** Joined by the API from the customers subcollection. */
  customer_name: string | null;
  type: string | null;
  value: number | null;
  status: string | null;
  issued_at: number | null;
  expires_at: number | null;
  redeemed_at: number | null;
};

/**
 * The sales list, with takings computed over every sale rather than the page.
 *
 * `totals` rides along on the same response because it is read from the same
 * documents; asking for it separately would be a second full read to answer
 * the question the screen exists for.
 */
export async function fetchMySales(
  params: ListQuery = {},
): Promise<MerchantList<MerchantSaleListItem> & { totals: SalesTotals }> {
  const body = await call<MerchantSaleListItem[]>(
    `/merchant/sales${buildListQuery(params)}`,
  );
  const totals = (body as { totals?: SalesTotals }).totals;
  return {
    ...toMerchantList(body),
    totals: totals ?? { count: 0, amount: 0, points: 0 },
  };
}

export function fetchMyRedemptions(params: ListQuery = {}) {
  return callList<MerchantRedemption>('/merchant/redemptions', params);
}

export function fetchMyAppointments(params: ListQuery = {}) {
  return callList<MerchantAppointment>('/merchant/appointments', params);
}

export function fetchMyReturnBonuses(params: ListQuery = {}) {
  return callList<MerchantReturnBonus>('/merchant/return-bonuses', params);
}

export function fetchMyRiskScores(params: ListQuery = {}) {
  return callList<MerchantRiskScore>('/merchant/risk-scores', params);
}

export function fetchMyRecoveryTasks(params: ListQuery = {}) {
  return callList<MerchantRecoveryTask>('/merchant/recovery-tasks', params);
}

export function fetchMyVisitReports(params: ListQuery = {}) {
  return callList<MerchantVisitReport>('/merchant/visit-reports', params);
}

export function fetchMySurveys(params: ListQuery = {}) {
  return callList<MerchantSurvey>('/merchant/surveys', params);
}

export async function fetchMyUsage(): Promise<MerchantUsageBalance[]> {
  const body = await call<MerchantUsageBalance[]>('/merchant/usage');
  return body.data ?? [];
}

/** One customer's points, entry by entry. */
export async function fetchMyCustomerLedger(
  customerId: string,
): Promise<MerchantLedgerEntry[]> {
  try {
    const body = await call<MerchantLedgerEntry[]>(
      `/merchant/customers/${encodeURIComponent(customerId)}/ledger`,
    );
    return body.data ?? [];
  } catch (caught) {
    // A customer with no ledger is not an error the screen should shout
    // about; it is a customer who has not earned anything yet.
    if (caught instanceof AdminApiError && caught.status === 404) return [];
    throw caught;
  }
}
