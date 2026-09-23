/**
 * Reading the Find Leads form, and the list's query string.
 *
 * Framework-free and server-free on purpose: this is the half of the
 * prospecting surface that can be tested with `node --test`, and it is the
 * half where a mistake is silent. A max-leads that quietly became 25 when the
 * operator chose 500, or a filter dropped because a checkbox arrived under a
 * name nobody expected, produces a screen that looks like it worked.
 *
 * The API validates all of this again and refuses what it does not like. This
 * layer exists so the refusal usually never happens — a form that can only
 * submit legal values is a better experience than one that submits anything
 * and renders the server's complaint.
 */

export const MAX_LEADS_OPTIONS = [25, 50, 100, 250, 500] as const;
export const MIN_SCORE_OPTIONS = [40, 60, 70, 80] as const;
export const SIZE_KEYS = ['1-5', '6-20', '21-50', '50+'] as const;

export type SearchFormValues = {
  industries: string[];
  city: string | null;
  maxLeads: number;
  minScore: number;
  size: string | null;
};

export type FormFailure = { field: string; message: string };

export type ParsedSearch =
  | { ok: true; values: SearchFormValues }
  | { ok: false; errors: FormFailure[] };

/**
 * Every industry checkbox that was ticked.
 *
 * A multi-select of checkboxes arrives as repeated entries under one name, so
 * this reads all of them rather than the first. Reading only the first is the
 * bug this function exists to not have: the form would look multi-select and
 * behave single-select, and nobody would notice until a search came back with
 * a third of the businesses it should have.
 */
export function readIndustries(form: {
  getAll: (name: string) => unknown[];
}): string[] {
  const raw = form.getAll('industries');
  const industries: string[] = [];

  for (const entry of raw) {
    if (typeof entry !== 'string') continue;
    const value = entry.trim().toLowerCase();
    if (value !== '' && !industries.includes(value)) industries.push(value);
  }

  return industries;
}

function text(form: { get: (name: string) => unknown }, key: string): string {
  const value = form.get(key);
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * The search form, or the fields that are wrong.
 *
 * Every failure is keyed to its field, because a single message at the foot of
 * a five-field form does not say which one to fix — the same reasoning
 * `ActionState.fieldErrors` already encodes.
 */
export function parseSearchForm(form: {
  get: (name: string) => unknown;
  getAll: (name: string) => unknown[];
}): ParsedSearch {
  const errors: FormFailure[] = [];

  const industries = readIndustries(form);
  // An empty selection is legal and means every ICP industry — which is what
  // an operator who ticked nothing almost certainly wants, and is what the API
  // does with an empty list.

  const maxLeadsRaw = Number.parseInt(text(form, 'maxLeads'), 10);
  const maxLeads = (MAX_LEADS_OPTIONS as readonly number[]).includes(maxLeadsRaw)
    ? maxLeadsRaw
    : 0;
  if (maxLeads === 0) {
    errors.push({ field: 'maxLeads', message: 'Escolha quantos negócios procurar.' });
  }

  const minScoreRaw = Number.parseInt(text(form, 'minScore'), 10);
  const minScore = (MIN_SCORE_OPTIONS as readonly number[]).includes(minScoreRaw)
    ? minScoreRaw
    : 0;
  if (minScore === 0) {
    errors.push({ field: 'minScore', message: 'Escolha uma pontuação mínima.' });
  }

  const sizeRaw = text(form, 'size');
  const size =
    sizeRaw === '' ? null : (SIZE_KEYS as readonly string[]).includes(sizeRaw) ? sizeRaw : '';
  if (size === '') {
    errors.push({ field: 'size', message: 'Escolha uma dimensão da lista.' });
  }

  const cityRaw = text(form, 'city');
  if (cityRaw.length > 80) {
    errors.push({ field: 'city', message: 'Localização demasiado longa.' });
  }

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    values: {
      industries,
      city: cityRaw === '' ? null : cityRaw,
      maxLeads,
      minScore,
      size,
    },
  };
}

/* ------------------------------------------------------------- list query */

export const LEAD_PAGE_SIZE = 25;

export type LeadListQuery = {
  status?: string;
  band?: string;
  industry?: string;
  city?: string;
  source?: string;
  enrichment?: string;
  contact?: string;
  search?: string;
  sort?: string;
  offset?: number;
};

/**
 * The query string the list page sends to the API.
 *
 * Blank filters are left out rather than sent empty, and `offset=0` is left
 * out too: they mean the same thing as their absence, and only one of the two
 * makes a URL worth pasting into a message.
 */
export function buildLeadQuery(query: LeadListQuery): string {
  const params = new URLSearchParams();

  const put = (key: string, value: string | undefined) => {
    const trimmed = (value ?? '').trim();
    if (trimmed !== '') params.set(key, trimmed);
  };

  put('status', query.status);
  put('band', query.band);
  put('industry', query.industry);
  put('city', query.city);
  put('source', query.source);
  put('enrichment', query.enrichment);
  put('contact', query.contact);
  put('search', query.search);
  if (query.sort !== undefined && query.sort !== '' && query.sort !== 'score') {
    params.set('sort', query.sort);
  }

  params.set('limit', String(LEAD_PAGE_SIZE));
  if (query.offset !== undefined && query.offset > 0) {
    params.set('offset', String(query.offset));
  }

  return `?${params.toString()}`;
}

/** The same values, as the URL of a filtered view of the list page. */
export function leadListHref(query: LeadListQuery): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (key === 'offset') continue;
    const trimmed = String(value ?? '').trim();
    if (trimmed !== '') params.set(key, trimmed);
  }
  if (query.offset !== undefined && query.offset > 0) {
    params.set('offset', String(query.offset));
  }

  const qs = params.toString();
  return qs === '' ? '/admin/prospecao' : `/admin/prospecao?${qs}`;
}

/* ----------------------------------------------------------------- money */

/**
 * A dollar amount, as an operator reads it.
 *
 * Kept to cents: the budgets are tens of dollars and the individual calls are
 * cents, so a figure rounded to the dollar would show every provider call as
 * `$0`. `estimated` puts a tilde in front, because a number presented without
 * one will be planned against.
 */
export function formatUsd(value: number | null, estimated = false): string {
  if (value === null || !Number.isFinite(value)) return '—';
  return `${estimated ? '~' : ''}$${value.toFixed(2)}`;
}

/** A range, collapsed when both ends are the same. */
export function formatUsdRange(min: number, max: number): string {
  if (min === max) return formatUsd(min);
  return `${formatUsd(min)} – ${formatUsd(max)}`;
}

/* ------------------------------------------------------- the cost estimate */

/**
 * What a search would cost, recomputed as the operator changes the form.
 *
 * The panel fetches an estimate once, for the default size. That number stops
 * being true the moment somebody changes "Quantos negócios" from 100 to 500 —
 * and on the one screen in this console that spends money, a stale figure
 * beside the button is worse than no figure: it is a specific, confident,
 * wrong number the operator has no reason to doubt.
 *
 * So the arithmetic runs here, on every change. The *numbers* it runs over —
 * the unit costs and the qualify-rate table — come from the server in
 * `estimate_units`, never from a second copy in this file. That is the part
 * that would have drifted; the four lines below are the part that will not.
 */
export type EstimateUnits = {
  discovery_unit_usd: number;
  enrichment_unit_usd: number;
  /** Ordered high to low; the first threshold the score meets wins. */
  qualify_rates: ReadonlyArray<{ minScore: number; rate: number }>;
};

export type LocalEstimate = {
  minUsd: number;
  maxUsd: number;
  likelyUsd: number;
  assumedQualifyRate: number;
};

/** Cents, matching the server's `round`. */
function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function qualifyRateFrom(units: EstimateUnits, minScore: number): number {
  return units.qualify_rates.find((entry) => minScore >= entry.minScore)?.rate ?? 0.6;
}

export function estimateSearch(
  maxLeads: number,
  minScore: number,
  units: EstimateUnits,
): LocalEstimate {
  const leads = Math.max(0, Math.floor(maxLeads));
  const discovery = round2(leads * units.discovery_unit_usd);
  const fullEnrichment = round2(leads * units.enrichment_unit_usd);
  const rate = qualifyRateFrom(units, minScore);

  return {
    minUsd: discovery,
    maxUsd: round2(discovery + fullEnrichment),
    likelyUsd: round2(discovery + fullEnrichment * rate),
    assumedQualifyRate: rate,
  };
}
