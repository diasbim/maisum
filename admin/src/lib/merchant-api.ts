import 'server-only';

import type {
  AffiliateCodeDto,
  AffiliateMetricsDto,
  AffiliateRewardDto,
  MerchantAffiliateDto,
} from '@contracts/affiliate_api_contracts';

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
 * The affiliate wire types, re-exported rather than restated.
 *
 * `affiliate_api_contracts.ts` is where these shapes are decided and tested;
 * a second copy in the portal would drift the moment a field is added, and the
 * screens would keep compiling while showing nothing. Type-only, so nothing
 * from the Functions package is bundled into the app.
 */
export type {
  AffiliateCodeDto,
  AffiliateMetricsDto,
  AffiliateRewardDto,
  MerchantAffiliateDto,
};

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
  /** Sent only by the affiliate routes; see `codedFailure` below. */
  code?: string;
  data?: T;
  paging?: { limit?: number; offset?: number; has_more?: boolean };
  total?: number;
  truncated?: boolean;
};

/**
 * A refusal the API wrote for this audience, or nothing.
 *
 * The rule on this side of the portal is that the API's own `message` never
 * reaches a business owner: every string the older `/merchant/*` routes can
 * send is an internal English one. The `/merchant/affiliate*` routes are the
 * exception and are built to be: each refusal carries a stable `code` and a
 * sentence taken from `AFFILIATE_API_MESSAGE` in
 * `functions/src/affiliate_api_contracts.ts`, which is Portuguese by
 * construction and written for the person reading it — "Este afiliado já está
 * ligado a este negócio" is worth far more than "reveja os campos".
 *
 * The presence of `code` is what tells the two apart, so an English message
 * from an older route can never be mistaken for one of these.
 */
function codedFailure(
  body: { code?: unknown; message?: unknown } | null,
): { code: string; message: string } | null {
  const code = typeof body?.code === 'string' ? body.code.trim() : '';
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  if (code === '' || message === '') return null;
  return { code, message };
}

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
    // `admin-api.ts`. Every string the older /merchant/* routes can send is an
    // internal English one — 'Server error', 'Business not found',
    // 'Unauthorized' — and this is the Portuguese-only side of the portal, so
    // a business owner whose page failed was reading "Server error". The line
    // above still logs it, which is where it was useful in the first place.
    // The one exception is a refusal that names itself; see `codedFailure`.
    //
    // 403 means "this account runs no business", which is a state the portal
    // explains rather than an error the operator can act on.
    const coded = codedFailure(body);
    if (coded !== null) {
      throw new AdminApiError(response.status, path, coded.message, coded.code);
    }
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

/**
 * The write path, kept deliberately separate from `call`.
 *
 * `call` is GET-only and stays that way: every read on these screens goes
 * through it, and a shared helper that could also POST would make "does this
 * page change anything?" a question you answer by reading the call site.
 *
 * A 404 here is not "missing page" — the API answers it for a record that is
 * unknown, belongs to another business, or is already closed, on purpose, so
 * that probing an id tells you nothing. `notFound` is the sentence for the one
 * of those the caller can act on, and differs by what was being written.
 */
async function callWrite<T>(
  path: string,
  init: {
    method?: 'POST' | 'PATCH';
    body?: Record<string, unknown>;
    notFound?: string;
  } = {},
): Promise<T | null> {
  const session = await getPortalSession();
  const token = session?.idToken;
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
      method: init.method ?? 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
        ...(init.body !== undefined
          ? { 'Content-Type': 'application/json' }
          : {}),
      },
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
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
    const coded = codedFailure(body);
    if (coded !== null) {
      throw new AdminApiError(response.status, path, coded.message, coded.code);
    }
    throw new AdminApiError(
      response.status,
      path,
      response.status === 404
        ? (init.notFound ?? 'Esta tarefa já não está pendente. Atualize a página.')
        : merchantMessage(response.status),
    );
  }

  return body?.data ?? null;
}

/**
 * Closes one recovery task.
 *
 * The only write the business side of the portal performs. See the route in
 * functions/src/index.ts for why this one and not the others.
 */
export function completeMyRecoveryTask(taskId: string) {
  return callWrite<MerchantRecoveryTask>(
    `/merchant/recovery-tasks/${encodeURIComponent(taskId)}/complete`,
  );
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

/** One answer, already paired with the question it answers. */
export type MerchantSurveyAnswer = {
  question_id: string | null;
  question_text: string | null;
  question_type: string | null;
  sort_order: number;
  answer: string | null;
};

export type MerchantSurveyResponse = {
  id: string;
  survey_id: string | null;
  survey_title: string | null;
  customer_id: string | null;
  customer_name: string | null;
  channel: string | null;
  submitted_at: number | null;
  answers: MerchantSurveyAnswer[];
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

/** `status` here filters by survey id, not by a state. */
export function fetchMySurveyResponses(params: ListQuery = {}) {
  return callList<MerchantSurveyResponse>('/merchant/survey-responses', params);
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

/* --------------------------------------------------------------- afiliados */

/**
 * The business's own affiliates, their codes, their rewards and their numbers.
 *
 * Every one of these is `/merchant/affiliate*`, which resolves the business
 * from the caller's token: no id is sent, and none could be honoured. Reads
 * are open to anybody the business has authenticated — a manager who cannot
 * change a code still has to be able to see who is referring customers — while
 * every write below is refused by the API for anyone but the owner. The portal
 * hides those controls too, but the API is the authority and says so in
 * Portuguese when it refuses.
 */

const AFFILIATE_NOT_FOUND =
  'Este afiliado já não está disponível. Atualize a página.';
const CODE_NOT_FOUND = 'Este código já não está disponível. Atualize a página.';
const REWARD_NOT_FOUND =
  'Esta recompensa já não está pendente. Atualize a página.';

export function fetchMyAffiliates(params: ListQuery = {}) {
  return callList<MerchantAffiliateDto>('/merchant/affiliates', params);
}

/** One affiliate with the code attached. `null` when this business has none. */
export async function fetchMyAffiliate(
  affiliateId: string,
): Promise<MerchantAffiliateDto | null> {
  try {
    const body = await call<MerchantAffiliateDto>(
      `/merchant/affiliates/${encodeURIComponent(affiliateId)}`,
    );
    return body.data ?? null;
  } catch (caught) {
    // An id that belongs to another business answers 404 as well, on purpose:
    // the link is the isolation boundary and probing an id says nothing.
    if (caught instanceof AdminApiError && caught.status === 404) return null;
    throw caught;
  }
}

export function fetchMyAffiliateRewards(params: ListQuery = {}) {
  return callList<AffiliateRewardDto>('/merchant/affiliate-rewards', params);
}

/**
 * The counts behind the cards, for the business or for one affiliate.
 *
 * `truncated` rides along on the same record and is shown rather than hidden:
 * a rate computed over a capped read is still useful, and silently rounding a
 * partial count into a percentage is not.
 */
export async function fetchMyAffiliateMetrics(
  affiliateId?: string,
): Promise<AffiliateMetricsDto | null> {
  const path =
    affiliateId === undefined
      ? '/merchant/affiliates/metrics'
      : `/merchant/affiliates/${encodeURIComponent(affiliateId)}/metrics`;
  try {
    const body = await call<AffiliateMetricsDto>(path);
    return body.data ?? null;
  } catch (caught) {
    if (caught instanceof AdminApiError && caught.status === 404) return null;
    throw caught;
  }
}

export type AffiliateDraft = {
  name: string;
  phone: string;
  benefitType: string;
  benefitValue: number;
  /** `null` is unlimited, which is how the API spells it too. */
  usageLimit: number | null;
  firstVisitOnly: boolean;
  expiresAt: number;
};

/**
 * Adds an affiliate and mints their code in one call.
 *
 * The code is not sent: the server builds it from the first name and its own
 * uniqueness check, which is the only place that can guarantee it. So the
 * response is what the screen shows, and there is nothing to share until it
 * has arrived.
 */
export async function createMyAffiliate(
  draft: AffiliateDraft,
): Promise<MerchantAffiliateDto | null> {
  return callWrite<MerchantAffiliateDto>('/merchant/affiliates', {
    body: {
      name: draft.name,
      phone: draft.phone,
      benefit_type: draft.benefitType,
      benefit_value: draft.benefitValue,
      usage_limit: draft.usageLimit,
      first_visit_only: draft.firstVisitOnly,
      expires_at: draft.expiresAt,
    },
  });
}

/** Turns this business's link to an affiliate on or off. Nothing is erased. */
export function setMyAffiliateActive(input: {
  affiliateId: string;
  active: boolean;
}): Promise<MerchantAffiliateDto | null> {
  const action = input.active ? 'activate' : 'deactivate';
  return callWrite<MerchantAffiliateDto>(
    `/merchant/affiliates/${encodeURIComponent(input.affiliateId)}/${action}`,
    { notFound: AFFILIATE_NOT_FOUND },
  );
}

export type CodeEdit = {
  codeId: string;
  benefitType: string;
  benefitValue: number;
  usageLimit: number | null;
  firstVisitOnly: boolean;
  /** Both ends, or neither: a lone expiry would move a code's start silently. */
  validity: { startsAt: number; expiresAt: number } | null;
};

export function updateMyAffiliateCode(
  edit: CodeEdit,
): Promise<AffiliateCodeDto | null> {
  return callWrite<AffiliateCodeDto>(
    `/merchant/affiliate-codes/${encodeURIComponent(edit.codeId)}`,
    {
      method: 'PATCH',
      notFound: CODE_NOT_FOUND,
      body: {
        benefit_type: edit.benefitType,
        benefit_value: edit.benefitValue,
        // Sent explicitly even when null: on this form a cleared limit means
        // "unlimited", and an omitted key would mean "leave it as it was".
        usage_limit: edit.usageLimit,
        first_visit_only: edit.firstVisitOnly,
        ...(edit.validity === null
          ? {}
          : {
              starts_at: edit.validity.startsAt,
              expires_at: edit.validity.expiresAt,
            }),
      },
    },
  );
}

export function setMyAffiliateCodeEnabled(input: {
  codeId: string;
  enabled: boolean;
}): Promise<AffiliateCodeDto | null> {
  const action = input.enabled ? 'enable' : 'disable';
  return callWrite<AffiliateCodeDto>(
    `/merchant/affiliate-codes/${encodeURIComponent(input.codeId)}/${action}`,
    { notFound: CODE_NOT_FOUND },
  );
}

/**
 * Approves or cancels one reward.
 *
 * No amount travels with either: what a reward is worth was decided when it
 * was created, from the business's own settings, and a request that could
 * state it could award itself points. Paying is not one of the choices — the
 * API has no such transition from here, and the plan leaves payment to a
 * person.
 */
export function decideMyAffiliateReward(input: {
  rewardId: string;
  decision: 'approve' | 'cancel';
}): Promise<AffiliateRewardDto | null> {
  return callWrite<AffiliateRewardDto>(
    `/merchant/affiliate-rewards/${encodeURIComponent(input.rewardId)}/${input.decision}`,
    { notFound: REWARD_NOT_FOUND },
  );
}
