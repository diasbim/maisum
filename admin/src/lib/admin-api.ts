import 'server-only';

import type {
  AdminAuditEventDto,
  AdminCustomerLookupDto,
  AdminDirectoryEntryDto,
  AdminEntitlementDto,
  AdminLedgerDto,
  AdminNfcCardDto,
  AdminStaffUserDto,
  AdminMerchantDetailDto,
  AdminMerchantSummaryDto,
  AdminOperationsSummaryDto,
  AdminPagingDto,
  AdminPlanDto,
} from '@contracts/admin_api_contracts';

import { serverConfig } from './env';
import { getAdminSession } from './session';

export type {
  AdminAuditEventDto,
  AdminCustomerLookupDto,
  AdminDirectoryEntryDto,
  AdminEntitlementDto,
  AdminLedgerDto,
  AdminNfcCardDto,
  AdminStaffUserDto,
  AdminMerchantDetailDto,
  AdminMerchantSummaryDto,
  AdminOperationsSummaryDto,
  AdminPagingDto,
  AdminPlanDto,
};

/**
 * Why the portal calls this API instead of reading the databases directly:
 *
 *  - Authorization stays in one place, already hardened (admin claim parity,
 *    scoped ADMIN_API_KEY).
 *  - The response contracts are defined and tested there.
 *  - It is independent of the open question about the PostgreSQL data (Q2 in
 *    docs/web_admin_portal_code_plan.md). When those queries are rewritten, the
 *    portal does not change.
 *
 * The caller's own ID token is forwarded, so every action stays attributable to
 * a person in the admin audit trail. The portal has no ambient credential of
 * its own. That matters most for the write endpoints below: the API records an
 * audit event naming the operator, and it can only do so because the token
 * travelling with the request is theirs.
 */

export class AdminApiError extends Error {
  constructor(
    readonly status: number,
    readonly path: string,
    message: string,
  ) {
    super(message);
    this.name = 'AdminApiError';
  }

  /** The caller is signed in but the API rejected the claim. */
  get isForbidden(): boolean {
    return this.status === 401 || this.status === 403;
  }
}

type Envelope<T> = {
  success?: boolean;
  message?: string;
  data?: T;
  paging?: AdminPagingDto;
};

export type Page<T> = {
  items: T[];
  paging: AdminPagingDto | null;
};

async function call<T>(
  path: string,
  init: {
    method?: 'GET' | 'POST';
    params?: Record<string, string | number | undefined>;
    body?: unknown;
  } = {},
): Promise<Envelope<T>> {
  const session = await getAdminSession();
  if (!session) {
    throw new AdminApiError(401, path, 'Sessao expirada. Entre novamente.');
  }

  const config = serverConfig();
  const url = new URL(`${config.adminApiBaseUrl}${path}`);
  for (const [key, value] of Object.entries(init.params ?? {})) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }

  let response: Response;
  try {
    response = await fetch(url, {
      method: init.method ?? 'GET',
      headers: {
        Authorization: `Bearer ${session.idToken}`,
        Accept: 'application/json',
        ...(init.body !== undefined
          ? { 'Content-Type': 'application/json' }
          : {}),
      },
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      // Operations data; never serve it from a cache.
      cache: 'no-store',
    });
  } catch {
    throw new AdminApiError(
      503,
      path,
      `Nao foi possivel contactar a API em ${config.adminApiBaseUrl}.`,
    );
  }

  // The API answers failures with a JSON envelope carrying `message`. Reading
  // it turns "returned 400" into the reason an operator can act on.
  let body: Envelope<T> | null = null;
  try {
    body = (await response.json()) as Envelope<T>;
  } catch {
    body = null;
  }

  if (!response.ok) {
    throw new AdminApiError(
      response.status,
      path,
      body?.message ?? `A API respondeu ${response.status} em ${path}.`,
    );
  }

  if (body === null) {
    throw new AdminApiError(502, path, 'A API devolveu JSON invalido.');
  }

  return body;
}

/* -------------------------------------------------------------------- reads */

export async function fetchOperationsSummary(): Promise<AdminOperationsSummaryDto> {
  const body = await call<AdminOperationsSummaryDto>(
    '/admin/operations/summary',
  );
  if (!body.data) {
    throw new AdminApiError(502, '/admin/operations/summary', 'Resposta vazia.');
  }
  return body.data;
}

export async function fetchMerchants(options?: {
  search?: string;
  status?: string;
  planCode?: string;
  limit?: number;
  offset?: number;
}): Promise<Page<AdminMerchantSummaryDto>> {
  const body = await call<AdminMerchantSummaryDto[]>('/admin/merchants', {
    params: {
      search: options?.search,
      status: options?.status,
      plan_code: options?.planCode,
      limit: options?.limit ?? 50,
      offset: options?.offset ?? 0,
    },
  });
  return { items: body.data ?? [], paging: body.paging ?? null };
}

export async function fetchMerchantDetail(
  merchantId: string,
): Promise<AdminMerchantDetailDto | null> {
  try {
    const body = await call<AdminMerchantDetailDto>(
      `/admin/merchants/${encodeURIComponent(merchantId)}`,
    );
    return body.data ?? null;
  } catch (caught) {
    // A missing merchant is a 404 from the API and is not an error condition
    // for the page; every other failure still propagates.
    if (caught instanceof AdminApiError && caught.status === 404) return null;
    throw caught;
  }
}

export async function fetchAuditEvents(options?: {
  merchantId?: string;
  targetType?: string;
  action?: string;
  limit?: number;
  offset?: number;
}): Promise<Page<AdminAuditEventDto>> {
  const body = await call<AdminAuditEventDto[]>('/admin/audit-events', {
    params: {
      merchant_id: options?.merchantId,
      target_type: options?.targetType,
      action: options?.action,
      limit: options?.limit ?? 20,
      offset: options?.offset ?? 0,
    },
  });
  return { items: body.data ?? [], paging: body.paging ?? null };
}

export async function fetchPlans(): Promise<AdminPlanDto[]> {
  const body = await call<AdminPlanDto[]>('/admin/plans');
  return body.data ?? [];
}

/* ------------------------------------------------------------------- writes */

/**
 * Snake_case keys throughout. The API accepts both conventions, but the audit
 * trail records whatever it received, so staying on one keeps those payloads
 * greppable later.
 */

export async function upsertEntitlement(input: {
  merchantId: string;
  featureKey: string;
  isEnabled: boolean;
  limitValue: number | null;
  unit: string | null;
}): Promise<void> {
  await call(
    `/admin/merchants/${encodeURIComponent(input.merchantId)}/entitlements`,
    {
      method: 'POST',
      body: {
        feature_key: input.featureKey,
        is_enabled: input.isEnabled,
        limit_value: input.limitValue,
        unit: input.unit,
      },
    },
  );
}

export async function upsertPlan(input: {
  planCode: string;
  version: number;
  name: string;
  isActive: boolean;
}): Promise<void> {
  await call('/admin/plans', {
    method: 'POST',
    body: {
      plan_code: input.planCode,
      version: input.version,
      name: input.name,
      is_active: input.isActive,
    },
  });
}

export async function upsertPrice(input: {
  planCode: string;
  pricingVersion: number;
  currency: string;
  amount: number;
  billingPeriod: string;
  isActive: boolean;
}): Promise<void> {
  await call('/admin/prices', {
    method: 'POST',
    body: {
      plan_code: input.planCode,
      pricing_version: input.pricingVersion,
      currency: input.currency,
      amount: input.amount,
      billing_period: input.billingPeriod,
      is_active: input.isActive,
    },
  });
}

export async function upsertPlanFeature(input: {
  planCode: string;
  planVersion: number;
  featureKey: string;
  isEnabled: boolean;
  limitValue: number | null;
  unit: string | null;
}): Promise<void> {
  await call(`/admin/plans/${encodeURIComponent(input.planCode)}/features`, {
    method: 'POST',
    body: {
      plan_version: input.planVersion,
      feature_key: input.featureKey,
      is_enabled: input.isEnabled,
      limit_value: input.limitValue,
      unit: input.unit,
    },
  });
}

/**
 * The maintenance jobs.
 *
 * Each walks Firestore in pages and returns a cursor. The raw result object is
 * surfaced as-is because the shapes differ per job, and an operator running a
 * backfill needs to see exactly what it reported — a summarised view would hide
 * the per-item errors that are the point of running it.
 */
export type JobResult = Record<string, unknown>;

export const JOB_PATHS = {
  merchantsBackfill: '/admin/merchants/backfill',
  businessCustomersBackfill: '/admin/customer-core/business-customers/backfill',
  nfcCardsBackfill: '/admin/customer-core/nfc-cards/backfill',
  loyaltyLedgerBackfill: '/admin/loyalty/ledger/backfill',
  loyaltyLedgerReconcile: '/admin/loyalty/ledger/reconcile',
  retentionPolicyUpsert: '/admin/retention/policies',
  retentionClassificationScan: '/admin/retention/classifications/scan',
} as const;

export type JobPath = (typeof JOB_PATHS)[keyof typeof JOB_PATHS];

export async function runJob(
  path: JobPath,
  body: Record<string, unknown>,
): Promise<JobResult> {
  const result = await call<JobResult>(path, { method: 'POST', body });
  return result.data ?? {};
}

/* ------------------------------------------------- entitlements and access */

export async function fetchMerchantEntitlements(
  merchantId: string,
): Promise<AdminEntitlementDto[]> {
  const body = await call<AdminEntitlementDto[]>(
    `/admin/merchants/${encodeURIComponent(merchantId)}/entitlements`,
  );
  return body.data ?? [];
}

export async function fetchStaff(options?: {
  search?: string;
  merchantId?: string;
  status?: string;
  role?: string;
  limit?: number;
  offset?: number;
}): Promise<Page<AdminStaffUserDto>> {
  const body = await call<AdminStaffUserDto[]>('/admin/access/staff', {
    params: {
      search: options?.search,
      merchant_id: options?.merchantId,
      status: options?.status,
      role: options?.role,
      limit: options?.limit ?? 25,
      offset: options?.offset ?? 0,
    },
  });
  return { items: body.data ?? [], paging: body.paging ?? null };
}

export type AdminDirectory = {
  entries: AdminDirectoryEntryDto[];
  /** True when the Auth directory was larger than the scan cap. */
  truncated: boolean;
  scanned: number;
};

export async function fetchAdminDirectory(): Promise<AdminDirectory> {
  const body = await call<AdminDirectoryEntryDto[]>('/admin/access/admins');
  const envelope = body as typeof body & {
    truncated?: boolean;
    scanned?: number;
  };
  return {
    entries: body.data ?? [],
    truncated: envelope.truncated === true,
    scanned: typeof envelope.scanned === 'number' ? envelope.scanned : 0,
  };
}

/* ----------------------------------------------------- customer support */

/**
 * Finds one customer by phone, card, or canonical id.
 *
 * `null` means not found, which is an ordinary outcome of a support lookup and
 * not an error; every other failure still throws.
 */
export async function lookupCustomer(options: {
  phone?: string;
  cardUid?: string;
  canonicalCustomerId?: string;
}): Promise<AdminCustomerLookupDto | null> {
  try {
    const body = await call<AdminCustomerLookupDto>('/admin/customers/lookup', {
      params: {
        phone: options.phone,
        card_uid: options.cardUid,
        canonical_customer_id: options.canonicalCustomerId,
      },
    });
    return body.data ?? null;
  } catch (caught) {
    if (caught instanceof AdminApiError && caught.status === 404) return null;
    throw caught;
  }
}

export async function fetchCustomerLedger(input: {
  canonicalCustomerId: string;
  merchantId: string;
  businessCustomerId?: string;
  limit?: number;
}): Promise<AdminLedgerDto | null> {
  const body = await call<AdminLedgerDto>(
    `/admin/customers/${encodeURIComponent(input.canonicalCustomerId)}/ledger`,
    {
      params: {
        merchant_id: input.merchantId,
        customer_id: input.businessCustomerId,
        limit: input.limit ?? 100,
      },
    },
  );
  return body.data ?? null;
}

export async function fetchNfcCards(options: {
  cardUid?: string;
  canonicalCustomerId?: string;
}): Promise<AdminNfcCardDto[]> {
  const body = await call<AdminNfcCardDto[]>('/admin/nfc-cards', {
    params: {
      card_uid: options.cardUid,
      canonical_customer_id: options.canonicalCustomerId,
    },
  });
  return body.data ?? [];
}
