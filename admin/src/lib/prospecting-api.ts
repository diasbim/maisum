import 'server-only';

import { serverConfig } from './env';
import { getAdminSession } from './session';
import { AdminApiError, statusMessage } from './admin-api-error';
import { buildLeadQuery, type LeadListQuery } from './prospecting-form';

/**
 * The prospecting half of the console's API client.
 *
 * Separate from `admin-api.ts` for one reason worth stating: that file is the
 * console's operational surface and this one spends money. Keeping them apart
 * means the endpoints that can incur a bill are all in one place, and a
 * reviewer can see every one of them at once.
 *
 * Everything else is the same as `admin-api.ts`, deliberately: the caller's
 * own ID token is forwarded so every action stays attributable to a person in
 * the audit trail, the portal holds no ambient credential, and responses are
 * never cached.
 *
 * The DTO types are imported from the Functions source as types only. They are
 * erased at compile time, so nothing here resolves a runtime module across the
 * project boundary.
 */

export { AdminApiError } from './admin-api-error';

export type ProspectingPaging = {
  limit: number;
  offset: number;
  has_more: boolean;
  total: number;
  truncated: boolean;
};

type Envelope<T> = {
  success?: boolean;
  message?: string;
  code?: string;
  data?: T;
  paging?: ProspectingPaging;
};

async function call<T>(
  path: string,
  init: {
    method?: 'GET' | 'POST' | 'PUT';
    body?: unknown;
  } = {},
): Promise<Envelope<T>> {
  const session = await getAdminSession();
  if (!session) {
    throw new AdminApiError(
      401,
      path,
      'A sessão expirou. Entre novamente para continuar.',
    );
  }

  const config = serverConfig();
  const url = `${config.adminApiBaseUrl}${path}`;

  let response: Response;
  try {
    response = await fetch(url, {
      method: init.method ?? 'GET',
      headers: {
        Authorization: `Bearer ${session.idToken}`,
        Accept: 'application/json',
        ...(init.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      },
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      cache: 'no-store',
    });
  } catch {
    console.error(`[prospecting-api] unreachable: ${path}`);
    throw new AdminApiError(
      503,
      path,
      'A API de administração não respondeu. Verifique a ligação e tente de novo.',
    );
  }

  let body: Envelope<T> | null = null;
  try {
    body = (await response.json()) as Envelope<T>;
  } catch {
    body = null;
  }

  if (!response.ok) {
    console.error(`[prospecting-api] ${response.status} ${path}`, body?.code);
    throw new AdminApiError(
      response.status,
      path,
      body?.message ?? statusMessage(response.status),
      typeof body?.code === 'string' && body.code.trim() !== ''
        ? body.code.trim()
        : null,
    );
  }

  if (body === null) {
    throw new AdminApiError(
      502,
      path,
      'A API devolveu uma resposta que não foi possível ler. Tente de novo.',
    );
  }

  return body;
}

/* ------------------------------------------------------------------ types */

export type ProspectingConfig = {
  industries: Array<{ business_type: string; label: string; tier: number }>;
  sizes: Array<{ key: string; label: string }>;
  max_leads_options: number[];
  min_score_options: number[];
  statuses: Array<{ value: string; label: string }>;
  bands: string[];
  enrichment_statuses: string[];
  cities: string[];
  provinces: string[];
  country: string;
};

export type LeadSummary = {
  id: string;
  company_id: string;
  name: string;
  industry: string | null;
  industry_label: string | null;
  city: string | null;
  province: string | null;
  lead_score: number | null;
  band: string | null;
  band_label: string | null;
  retention_potential_score: number | null;
  decision_maker_count: number;
  has_reachable_contact: boolean;
  status: string;
  status_label: string;
  source: string;
  enrichment_status: string;
  enrichment_status_label: string;
  suspected_merchant_id: string | null;
  spend_usd: number;
  last_activity_at: number | null;
  created_at: number;
};

export type LeadContact = {
  id: string;
  first_name: string | null;
  last_name: string | null;
  job_title: string | null;
  seniority: string;
  email: string | null;
  email_status: string;
  email_status_label: string;
  email_usable: boolean;
  phone: string | null;
  linkedin_url: string | null;
  is_decision_maker: boolean;
  confidence_score: number | null;
};

export type LeadCompany = {
  id: string;
  name: string;
  legal_name: string | null;
  domain: string | null;
  website: string | null;
  industry: string | null;
  industry_label: string | null;
  employee_count: number | null;
  city: string | null;
  province: string | null;
  country: string | null;
  address: string | null;
  phone: string | null;
  email: string | null;
  whatsapp: string | null;
  linkedin_url: string | null;
  instagram_url: string | null;
  facebook_url: string | null;
  source: string;
};

export type LeadActivity = {
  id: string;
  type: string;
  channel: string | null;
  description: string;
  metadata: Record<string, unknown>;
  created_at: number;
  created_by: string | null;
};

export type LeadAnalysisDto = {
  model: string;
  prompt_version: number;
  summary: string;
  retention_opportunity: string;
  recommended_product: string;
  recommended_pitch: string;
  recommended_channel: string;
  evidence: Array<{ claim: string; type: string; source: string }>;
  unknowns: string[];
  ai_fit_score: number;
  engine_score: number | null;
  score_divergence: number | null;
  created_at: number;
};

export type LeadDetail = {
  prospect: LeadSummary;
  company: LeadCompany | null;
  contacts: LeadContact[];
  activities: LeadActivity[];
  analysis: LeadAnalysisDto | null;
  available_channels: string[];
  outreach_blocked: boolean;
};

export type ProspectingJobDto = {
  id: string;
  type: string;
  status: string;
  status_label: string;
  progress_label: string;
  progress: number;
  target: number;
  discovered: number;
  duplicates: number;
  qualified: number;
  disqualified: number;
  enriched: number;
  failed: number;
  estimated_cost_usd: number;
  spent_usd: number;
  error_code: string | null;
  created_at: number;
  finished_at: number | null;
};

export type SearchEstimateDto = {
  min_usd: number;
  max_usd: number;
  likely_usd: number;
  assumed_qualify_rate: number;
  verified: boolean;
  monthly_budget_usd: number;
  remaining_this_month_usd: number;
};

export type UsageDto = {
  id: string;
  provider: string;
  operation: string;
  prospect_id: string | null;
  estimated_cost: number;
  actual_cost: number | null;
  success: boolean;
  error_code: string | null;
  created_at: number;
};

export type SpendDto = {
  month_key: string;
  month_usd: number;
  day_usd: number;
  monthly_budget_usd: number;
  daily_budget_usd: number;
  remaining_month_usd: number;
  remaining_day_usd: number;
  estimated: boolean;
  paused: boolean;
};

export type ProspectingSettingsDto = {
  monthly_budget_usd: number;
  daily_budget_usd: number;
  max_enrichment_cost_per_lead_usd: number;
  min_score_for_enrichment: number;
  max_prospects_per_search: number;
  provider_priority: string[];
  cities: string[];
  provinces: string[];
  country: string;
  flags: {
    prospecting_enabled: boolean;
    auto_enrichment_enabled: boolean;
    outreach_enabled: boolean;
    apollo_enabled: boolean;
    aisa_enabled: boolean;
  };
};

export type OutreachDraftDto = {
  channel: string;
  locale: string;
  subject: string | null;
  body: string;
  addressedTo: string | null;
  truncated: boolean;
  /** Which template wrote it. Reply rates are grouped by this. */
  templateId: string;
};

export type FunnelStageDto = {
  status: string;
  label: string;
  reached: number;
  /** Null where there is no previous stage, or nobody reached it. */
  conversion_from_previous: number | null;
  conversion_from_start: number | null;
};

export type FunnelDto = {
  total: number;
  stages: FunnelStageDto[];
  exits: Array<{ status: string; label: string; count: number }>;
  bands: {
    priority: { total: number; customers: number };
    nurture: { total: number; customers: number };
  };
  /** The two numbers that decide whether AI is ever worth adding back. */
  signals: { replyRate: number | null; bandSeparation: number | null };
};

/* ------------------------------------------------------------------ reads */

export async function fetchProspectingConfig(): Promise<ProspectingConfig> {
  const body = await call<ProspectingConfig>('/admin/prospecting/config');
  if (body.data === undefined) {
    throw new AdminApiError(502, '/admin/prospecting/config', 'Configuração indisponível.');
  }
  return body.data;
}

export async function fetchLeads(
  query: LeadListQuery,
): Promise<{ items: LeadSummary[]; paging: ProspectingPaging | null }> {
  const body = await call<LeadSummary[]>(
    `/admin/prospecting/leads${buildLeadQuery(query)}`,
  );
  return { items: body.data ?? [], paging: body.paging ?? null };
}

export async function fetchLead(prospectId: string): Promise<LeadDetail> {
  const body = await call<LeadDetail>(
    `/admin/prospecting/leads/${encodeURIComponent(prospectId)}`,
  );
  if (body.data === undefined) {
    throw new AdminApiError(404, 'lead', 'Lead não encontrado.');
  }
  return body.data;
}

export async function fetchEstimate(input: {
  maxLeads: number;
  minScore: number;
}): Promise<SearchEstimateDto> {
  const body = await call<SearchEstimateDto>(
    `/admin/prospecting/estimate?maxLeads=${input.maxLeads}&minScore=${input.minScore}`,
  );
  if (body.data === undefined) {
    throw new AdminApiError(502, 'estimate', 'Estimativa indisponível.');
  }
  return body.data;
}

export async function fetchJob(jobId: string): Promise<ProspectingJobDto> {
  const body = await call<ProspectingJobDto>(
    `/admin/prospecting/jobs/${encodeURIComponent(jobId)}`,
  );
  if (body.data === undefined) {
    throw new AdminApiError(404, 'job', 'Trabalho não encontrado.');
  }
  return body.data;
}

export async function fetchFunnel(): Promise<FunnelDto> {
  const body = await call<FunnelDto>('/admin/prospecting/funnel');
  if (body.data === undefined) {
    throw new AdminApiError(502, 'funnel', 'Funil indisponível.');
  }
  return body.data;
}

export async function fetchUsage(input: {
  month?: string;
  limit?: number;
  offset?: number;
}): Promise<{ spend: SpendDto; rows: UsageDto[]; paging: ProspectingPaging | null }> {
  const params = new URLSearchParams();
  if (input.month) params.set('month', input.month);
  params.set('limit', String(input.limit ?? 25));
  if (input.offset) params.set('offset', String(input.offset));

  const body = await call<{ spend: SpendDto; rows: UsageDto[] }>(
    `/admin/prospecting/usage?${params.toString()}`,
  );

  if (body.data === undefined) {
    throw new AdminApiError(502, 'usage', 'Consumo indisponível.');
  }
  return { spend: body.data.spend, rows: body.data.rows, paging: body.paging ?? null };
}

export async function fetchProspectingSettings(): Promise<ProspectingSettingsDto> {
  const body = await call<ProspectingSettingsDto>('/admin/prospecting/settings');
  if (body.data === undefined) {
    throw new AdminApiError(502, 'settings', 'Definições indisponíveis.');
  }
  return body.data;
}

/* ----------------------------------------------------------------- writes */

export async function startSearch(input: {
  industries: string[];
  city: string | null;
  size: string | null;
  maxLeads: number;
  minScore: number;
}): Promise<ProspectingJobDto> {
  const body = await call<ProspectingJobDto>('/admin/prospecting/search', {
    method: 'POST',
    body: {
      industries: input.industries,
      city: input.city,
      size: input.size,
      maxLeads: input.maxLeads,
      minScore: input.minScore,
    },
  });

  if (body.data === undefined) {
    throw new AdminApiError(502, 'search', 'A procura não devolveu um trabalho.');
  }
  return body.data;
}

export async function cancelSearch(jobId: string): Promise<ProspectingJobDto> {
  const body = await call<ProspectingJobDto>(
    `/admin/prospecting/jobs/${encodeURIComponent(jobId)}/cancel`,
    { method: 'POST' },
  );
  if (body.data === undefined) {
    throw new AdminApiError(502, 'cancel', 'Não foi possível cancelar.');
  }
  return body.data;
}

export async function findDecisionMakers(prospectId: string): Promise<{
  status: string;
  decision_makers_found: number;
  spend_usd: number;
}> {
  const body = await call<{
    status: string;
    decision_makers_found: number;
    spend_usd: number;
  }>(
    `/admin/prospecting/leads/${encodeURIComponent(prospectId)}/find-decision-makers`,
    { method: 'POST' },
  );
  return (
    body.data ?? { status: 'FAILED', decision_makers_found: 0, spend_usd: 0 }
  );
}

export async function enrichLead(prospectId: string): Promise<{
  score: number;
  band: string;
  spend_usd: number;
}> {
  const body = await call<{ score: number; band: string; spend_usd: number }>(
    `/admin/prospecting/leads/${encodeURIComponent(prospectId)}/enrich`,
    { method: 'POST' },
  );
  return body.data ?? { score: 0, band: 'LOW_FIT', spend_usd: 0 };
}

export async function analyzeLead(
  prospectId: string,
  force = false,
): Promise<Record<string, unknown>> {
  const body = await call<Record<string, unknown>>(
    `/admin/prospecting/leads/${encodeURIComponent(prospectId)}/analyze`,
    { method: 'POST', body: { force } },
  );
  return body.data ?? {};
}

export async function generateOutreach(
  prospectId: string,
  channel: string,
): Promise<OutreachDraftDto> {
  const body = await call<OutreachDraftDto>(
    `/admin/prospecting/leads/${encodeURIComponent(prospectId)}/generate-outreach`,
    { method: 'POST', body: { channel } },
  );
  if (body.data === undefined) {
    throw new AdminApiError(502, 'outreach', 'Não foi possível gerar a mensagem.');
  }
  return body.data;
}

export async function markContacted(input: {
  prospectId: string;
  channel: string;
  note: string | null;
}): Promise<void> {
  await call(`/admin/prospecting/leads/${encodeURIComponent(input.prospectId)}/contact`, {
    method: 'POST',
    body: { channel: input.channel, note: input.note },
  });
}

export async function setLeadStatus(input: {
  prospectId: string;
  status: string;
  note: string | null;
}): Promise<void> {
  await call(`/admin/prospecting/leads/${encodeURIComponent(input.prospectId)}/status`, {
    method: 'POST',
    body: { status: input.status, note: input.note },
  });
}

export async function saveProspectingSettings(
  patch: Record<string, unknown>,
): Promise<ProspectingSettingsDto> {
  const body = await call<ProspectingSettingsDto>('/admin/prospecting/settings', {
    method: 'PUT',
    body: patch,
  });
  if (body.data === undefined) {
    throw new AdminApiError(502, 'settings', 'Não foi possível guardar.');
  }
  return body.data;
}
