import { ICP_INDUSTRIES } from './prospecting_config.js';
import type { EmailStatus, ProviderOperation, Seniority } from './prospecting_contracts.js';
import {
  assertCompanySane,
  assertNoFabrication,
  ProviderError,
  seniorityFromTitle,
  type BusinessDiscoveryProvider,
  type BusinessDiscoveryResult,
  type BusinessSearchCriteria,
  type CompanyEnrichmentInput,
  type CompanyEnrichmentProvider,
  type CompanyEnrichmentResult,
  type CompanyRecord,
  type DecisionMakerSearchInput,
  type PersonDiscoveryProvider,
  type PersonDiscoveryResult,
  type PersonEnrichmentInput,
  type PersonEnrichmentProvider,
  type PersonEnrichmentResult,
  type PersonRecord,
} from './prospecting_providers.js';

/**
 * Apollo, as four documented endpoints.
 *
 * Verified against the official reference on 20 September 2026, not written
 * from memory:
 *
 *   POST /api/v1/mixed_companies/search  — docs.apollo.io/reference/organization-search
 *   GET  /api/v1/organizations/enrich    — docs.apollo.io/reference/organization-enrichment
 *   POST /api/v1/mixed_people/api_search — docs.apollo.io/reference/people-api-search
 *   POST /api/v1/people/match            — docs.apollo.io/reference/people-enrichment
 *
 * All four authenticate with an `x-api-key` header. The key is read from the
 * environment at call time and never logged, never put in a URL, and never
 * included in a `ProviderError.detail`.
 *
 * Three things the documentation says that shape this adapter more than the
 * request bodies do:
 *
 * **People search returns `last_name_obfuscated`, not a last name, and returns
 * no email and no phone at all.** It returns `has_email` and
 * `has_direct_phone` — flags saying an address exists, not the address. So
 * `findDecisionMakers` produces a person with `last_name: null`,
 * `email: null` and `email_status: 'UNKNOWN'`, and finding the contact detail
 * is a second, separately-charged call. An adapter that filled those fields
 * from the flags would be fabricating exactly what criterion 13 forbids.
 *
 * **Phone numbers arrive asynchronously.** `reveal_phone_number` requires an
 * HTTPS webhook that Apollo calls back, and this module has no such endpoint.
 * So the adapter never sets that parameter, phones stay null from Apollo, and
 * the final report records it as the one capability the integration does not
 * have. Setting the flag without a webhook would burn credits for data that
 * never arrives.
 *
 * **`match_confidence` is a category, not a number.** Apollo answers `high`,
 * `medium`, `low` or `none`. The internal model wants a 0–1 score, so there is
 * a fixed mapping below. It is a rename of the provider's own judgement, not
 * an estimate of anything, and `none` is not mapped to a low number — it is a
 * `NO_RESULT`, because the documentation says it means no match was found and
 * costs no credits.
 */

const DEFAULT_BASE_URL = 'https://api.apollo.io/api/v1';
const DEFAULT_TIMEOUT_MS = 20_000;
export const APOLLO_KEY = 'apollo';

export type ApolloOptions = {
  apiKey: string | undefined;
  baseUrl?: string;
  timeoutMs?: number;
  /** Injected so the adapter can be exercised without a network. */
  fetchImpl?: typeof fetch;
  now?: () => number;
};

/**
 * Apollo's employee-count filter, as the documentation spells it.
 *
 * The parameter takes ranges written as `"min,max"`. There is no open-ended
 * form documented, so an unbounded upper end is written against a ceiling no
 * small business in Maputo will reach rather than omitted — omitting it would
 * silently widen the search to every company size and spend the search's
 * budget on results that cannot qualify.
 */
export function employeeRangeParam(
  min: number | null,
  max: number | null,
): string | null {
  if (min === null && max === null) return null;
  return `${Math.max(1, min ?? 1)},${max ?? 10_000}`;
}

/**
 * Apollo's own seniority vocabulary, from the people-search reference.
 *
 * `owner, founder, c_suite, partner, vp, head, director, manager, senior,
 * entry, intern`. Only the ones that decide a software purchase are asked
 * for; sending the whole list would return receptionists and charge for them.
 */
export const APOLLO_SENIORITIES = [
  'owner',
  'founder',
  'c_suite',
  'partner',
  'head',
  'director',
  'manager',
] as const;

/** Apollo's category, renamed. `none` never reaches here — it is a NO_RESULT. */
export function confidenceFromMatch(value: unknown): number | null {
  if (typeof value !== 'string') return null;
  switch (value.trim().toLowerCase()) {
    case 'high':
      return 0.9;
    case 'medium':
      return 0.6;
    case 'low':
      return 0.3;
    default:
      return null;
  }
}

/**
 * Apollo's `email_status`, where it sends one.
 *
 * Anything unrecognised becomes `UNVERIFIED` rather than `VERIFIED`: an
 * unknown status is not a guarantee, and the difference decides whether the
 * address earns a scoring point and whether the UI presents it as usable.
 */
export function emailStatusFrom(value: unknown, hasEmail: boolean): EmailStatus {
  if (!hasEmail) return 'UNKNOWN';
  if (typeof value !== 'string') return 'UNVERIFIED';
  switch (value.trim().toLowerCase()) {
    case 'verified':
      return 'VERIFIED';
    case 'guessed':
    case 'likely':
      return 'GUESSED';
    case 'unavailable':
    case 'invalid':
      return 'INVALID';
    default:
      return 'UNVERIFIED';
  }
}

/**
 * Apollo's industry string mapped onto `businesses.business_type`.
 *
 * Apollo indexes global industry taxonomies that have no entry for "barbearia"
 * as Mozambique means it, so the mapping goes through the ICP keyword lists
 * rather than through a code table. An unrecognised industry maps to null —
 * the trade is unknown, the scorer treats it as unknown, and the raw string is
 * kept beside it so an operator can see what Apollo actually said.
 */
export function industryFrom(
  industry: unknown,
  keywords: unknown,
  name: string,
): string | null {
  const haystack = [
    typeof industry === 'string' ? industry : '',
    Array.isArray(keywords) ? keywords.filter((k) => typeof k === 'string').join(' ') : '',
    name,
  ]
    .join(' ')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase();

  for (const entry of ICP_INDUSTRIES) {
    for (const keyword of entry.keywords) {
      const folded = keyword.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
      if (haystack.includes(folded)) return entry.businessType;
    }
  }
  return null;
}

/* ------------------------------------------------------------ the adapter */

export class ApolloProvider
  implements
    BusinessDiscoveryProvider,
    CompanyEnrichmentProvider,
    PersonDiscoveryProvider,
    PersonEnrichmentProvider
{
  readonly key = APOLLO_KEY;
  private readonly options: ApolloOptions;

  constructor(options: ApolloOptions) {
    this.options = options;
  }

  isConfigured(): boolean {
    const key = this.options.apiKey;
    return typeof key === 'string' && key.trim() !== '';
  }

  private baseUrl(): string {
    return (this.options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, '');
  }

  /**
   * One request, with every failure turned into a typed one.
   *
   * The response body is read before the status is judged, because Apollo puts
   * the reason a call was refused in the body and a 422 with "insufficient
   * credits" must not be reported as a schema problem. The body never reaches
   * a log wholesale — only the mapped code and a short reason do — because it
   * carries personal data on the people endpoints.
   */
  private async request(
    operation: ProviderOperation,
    path: string,
    init: { method: 'GET' | 'POST'; body?: unknown; query?: Record<string, string> },
  ): Promise<Record<string, unknown>> {
    const apiKey = this.options.apiKey;
    if (typeof apiKey !== 'string' || apiKey.trim() === '') {
      throw new ProviderError({
        code: 'NOT_CONFIGURED',
        provider: this.key,
        operation,
        detail: 'APOLLO_API_KEY is not set',
      });
    }

    const fetchImpl = this.options.fetchImpl ?? fetch;
    const url = new URL(`${this.baseUrl()}${path}`);
    for (const [name, value] of Object.entries(init.query ?? {})) {
      url.searchParams.set(name, value);
    }

    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      this.options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
    );

    let response: Response;
    try {
      response = await fetchImpl(url, {
        method: init.method,
        headers: {
          'x-api-key': apiKey,
          accept: 'application/json',
          ...(init.body !== undefined ? { 'content-type': 'application/json' } : {}),
        },
        body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
        signal: controller.signal,
      });
    } catch (error) {
      const aborted =
        error instanceof Error &&
        (error.name === 'AbortError' || error.name === 'TimeoutError');
      throw new ProviderError({
        code: aborted ? 'TIMEOUT' : 'UNAVAILABLE',
        provider: this.key,
        operation,
        detail: aborted ? 'request timed out' : 'network error',
      });
    } finally {
      clearTimeout(timer);
    }

    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }

    if (!response.ok) {
      throw new ProviderError({
        code: statusToCode(response.status, body),
        provider: this.key,
        operation,
        detail: `HTTP ${response.status}`,
      });
    }

    if (body === null || typeof body !== 'object' || Array.isArray(body)) {
      throw new ProviderError({
        code: 'INVALID_SCHEMA',
        provider: this.key,
        operation,
        detail: 'response was not a JSON object',
      });
    }

    return body as Record<string, unknown>;
  }

  /* --------------------------------------------------------- discovery */

  async searchBusinesses(
    criteria: BusinessSearchCriteria,
  ): Promise<BusinessDiscoveryResult[]> {
    // The keyword tags are how a Mozambican trade is actually found: Apollo
    // has no industry code for "barbearia", but the word appears in the name
    // and the tags of every one of them.
    const keywords = criteria.industries.flatMap((businessType) => {
      const entry = ICP_INDUSTRIES.find((icp) => icp.businessType === businessType);
      return entry === undefined ? [] : [...entry.keywords];
    });

    const location = [criteria.city, criteria.province, criteria.country]
      .filter((part): part is string => typeof part === 'string' && part.trim() !== '')
      .join(', ');

    const range = employeeRangeParam(criteria.employeeMin, criteria.employeeMax);
    const page = criteria.cursor === null ? 1 : Math.max(1, Number.parseInt(criteria.cursor, 10) || 1);

    const body = await this.request('SEARCH_BUSINESSES', '/mixed_companies/search', {
      method: 'POST',
      body: {
        organization_locations: location === '' ? undefined : [location],
        q_organization_keyword_tags: keywords.length > 0 ? keywords : undefined,
        organization_num_employees_ranges: range === null ? undefined : [range],
        page,
        // Documented maximum is 100 per page, and one credit is charged per
        // page regardless of how many come back — so asking for fewer than the
        // caller wants would cost more, not less.
        per_page: Math.min(100, Math.max(1, criteria.limit)),
      },
    });

    const organizations = body.organizations;
    if (!Array.isArray(organizations)) {
      throw new ProviderError({
        code: 'INVALID_SCHEMA',
        provider: this.key,
        operation: 'SEARCH_BUSINESSES',
        detail: 'organizations was not an array',
      });
    }
    if (organizations.length === 0) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'SEARCH_BUSINESSES',
      });
    }

    const pagination = asRecord(body.pagination);
    const totalPages = asNumberField(pagination?.total_pages);
    const nextCursor =
      totalPages !== null && page < totalPages ? String(page + 1) : null;

    return organizations.flatMap((raw, index) => {
      const organization = asRecord(raw);
      if (organization === null) return [];
      const company = this.toCompany(organization);
      if (company === null) return [];
      return [
        {
          company,
          cursor: index === organizations.length - 1 ? nextCursor : null,
        },
      ];
    });
  }

  /**
   * One organization, mapped.
   *
   * Returns null rather than throwing for a row with no name: one malformed
   * entry in a page of a hundred should cost that entry, not the page. A
   * malformed *page* is a different thing and does throw, above.
   */
  private toCompany(organization: Record<string, unknown>): CompanyRecord | null {
    const name = asStringField(organization.name);
    if (name === null) return null;

    const website = asStringField(organization.website_url);
    const domain = asStringField(organization.primary_domain);

    const record: CompanyRecord = {
      name,
      legal_name: null,
      domain,
      website,
      industry: industryFrom(organization.industry, organization.keywords, name),
      industry_raw: asStringField(organization.industry),
      employee_count: asNumberField(organization.estimated_num_employees),
      // Apollo's search response carries location on the organization for the
      // people endpoints but not reliably here; a field that is absent stays
      // null rather than being back-filled from the search criteria, which
      // would record the place that was asked for as the place that was found.
      city: asStringField(organization.city),
      province: asStringField(organization.state),
      country: asStringField(organization.country),
      address: asStringField(organization.street_address),
      phone:
        asStringField(organization.sanitized_phone) ??
        asStringField(organization.primary_phone),
      email: null,
      linkedin_url: asStringField(organization.linkedin_url),
      instagram_url: null,
      facebook_url: asStringField(organization.facebook_url),
      whatsapp: null,
      // Apollo indexes companies, not storefronts: it has no public rating,
      // no review count and no trading status. Null rather than a stand-in,
      // so a lead sourced here is scored as "not known" on those criteria
      // instead of silently losing the points a Places lead would earn.
      rating: null,
      review_count: null,
      has_opening_hours: null,
      has_photos: null,
      business_status: null,
      source: this.key,
      source_reference: asStringField(organization.id),
      provider_org_id: asStringField(organization.id),
    };

    try {
      return assertCompanySane(record, this.key, 'SEARCH_BUSINESSES');
    } catch {
      return null;
    }
  }

  /* -------------------------------------------------- company enrichment */

  async enrichCompany(
    input: CompanyEnrichmentInput,
  ): Promise<CompanyEnrichmentResult> {
    const query: Record<string, string> = {};
    if (input.domain !== null) query.domain = input.domain;
    else if (input.website !== null) query.website = input.website;
    else if (input.linkedinUrl !== null) query.linkedin_url = input.linkedinUrl;
    else query.name = input.name;

    const body = await this.request('ENRICH_COMPANY', '/organizations/enrich', {
      method: 'GET',
      query,
    });

    const organization = asRecord(body.organization);
    if (organization === null) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_COMPANY',
      });
    }

    const company: Partial<CompanyRecord> = {
      domain: asStringField(organization.primary_domain) ?? undefined,
      website: asStringField(organization.website_url) ?? undefined,
      linkedin_url: asStringField(organization.linkedin_url) ?? undefined,
      employee_count: asNumberField(organization.estimated_num_employees) ?? undefined,
      industry_raw: asStringField(organization.industry) ?? undefined,
      provider_org_id: asStringField(organization.id) ?? undefined,
    };

    const industry = industryFrom(
      organization.industry,
      organization.keywords,
      asStringField(organization.name) ?? input.name,
    );
    if (industry !== null) company.industry = industry;

    const fieldsDiscovered = Object.entries(company)
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([field]) => field);

    if (fieldsDiscovered.length === 0) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_COMPANY',
      });
    }

    return { company, fieldsDiscovered };
  }

  /* ------------------------------------------------------ people search */

  async findDecisionMakers(
    input: DecisionMakerSearchInput,
  ): Promise<PersonDiscoveryResult[]> {
    const body = await this.request('FIND_DECISION_MAKERS', '/mixed_people/api_search', {
      method: 'POST',
      body: {
        person_titles: input.titles.length > 0 ? [...input.titles] : undefined,
        person_seniorities: [...APOLLO_SENIORITIES],
        organization_ids:
          input.providerOrgId === null ? undefined : [input.providerOrgId],
        q_organization_domains_list:
          input.domain === null ? undefined : [input.domain],
        page: 1,
        per_page: Math.min(100, Math.max(1, input.limit)),
      },
    });

    const people = body.people;
    if (!Array.isArray(people)) {
      throw new ProviderError({
        code: 'INVALID_SCHEMA',
        provider: this.key,
        operation: 'FIND_DECISION_MAKERS',
        detail: 'people was not an array',
      });
    }
    if (people.length === 0) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'FIND_DECISION_MAKERS',
      });
    }

    return people.flatMap((raw) => {
      const person = asRecord(raw);
      if (person === null) return [];

      const title = asStringField(person.title);
      const record: PersonRecord = {
        first_name: asStringField(person.first_name),
        // `last_name_obfuscated` is what this endpoint returns, and an
        // obfuscated name is not a name. Enrichment is what resolves it.
        last_name: null,
        job_title: title,
        seniority: seniorityFrom(person.seniority, title),
        // This endpoint returns neither, whatever `has_email` says.
        email: null,
        email_status: 'UNKNOWN',
        phone: null,
        linkedin_url: asStringField(person.linkedin_url),
        provider_person_id: asStringField(person.id),
        confidence_score: null,
      };

      try {
        return [{ person: assertNoFabrication(record, this.key, 'FIND_DECISION_MAKERS') }];
      } catch {
        return [];
      }
    });
  }

  /* -------------------------------------------------- person enrichment */

  async enrichPerson(input: PersonEnrichmentInput): Promise<PersonEnrichmentResult> {
    const body = await this.request('ENRICH_PERSON', '/people/match', {
      method: 'POST',
      body: {
        id: input.providerPersonId ?? undefined,
        first_name: input.firstName ?? undefined,
        last_name: input.lastName ?? undefined,
        organization_name: input.companyName ?? undefined,
        domain: input.domain ?? undefined,
        linkedin_url: input.linkedinUrl ?? undefined,
        // Work addresses only. A personal email belonging to the owner of a
        // barbershop is not what a first sales contact should arrive at, and
        // requesting one costs a credit for data the product will not use.
        reveal_personal_emails: false,
        // Deliberately absent: `reveal_phone_number` requires an HTTPS webhook
        // Apollo calls back, and this module exposes none. Sending it would
        // spend credits on a result that has nowhere to arrive.
      },
    });

    const person = asRecord(body.person);
    if (person === null) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_PERSON',
      });
    }

    const confidenceRaw = asStringField(person.match_confidence);
    if (confidenceRaw !== null && confidenceRaw.toLowerCase() === 'none') {
      // Documented as costing no credits, and it means no match was found.
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_PERSON',
      });
    }

    const email = asStringField(person.email);
    const title = asStringField(person.title);

    const mapped: Partial<PersonRecord> = {
      first_name: asStringField(person.first_name) ?? undefined,
      last_name: asStringField(person.last_name) ?? undefined,
      job_title: title ?? undefined,
      email: email ?? undefined,
      email_status: emailStatusFrom(person.email_status, email !== null),
      // Stays null: see the note at the top of this file about webhooks.
      phone: undefined,
      linkedin_url: asStringField(person.linkedin_url) ?? undefined,
      provider_person_id: asStringField(person.id) ?? undefined,
      confidence_score: confidenceFromMatch(person.match_confidence) ?? undefined,
    };

    if (title !== null) mapped.seniority = seniorityFromTitle(title);

    const fieldsDiscovered = Object.entries(mapped)
      .filter(([field, value]) => value !== undefined && value !== null && field !== 'email_status')
      .map(([field]) => field);

    if (fieldsDiscovered.length === 0) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_PERSON',
      });
    }

    return { person: mapped, fieldsDiscovered };
  }
}

/* ------------------------------------------------------------- mapping */

/**
 * HTTP status to a code the chain can act on.
 *
 * 401 and 403 become `NOT_CONFIGURED` rather than `UNAVAILABLE`, because a key
 * the provider rejects is functionally a key that is not set: retrying will
 * not help, and the right behaviour is to move to the next provider and tell
 * the operator the integration needs attention.
 */
export function statusToCode(
  status: number,
  body: unknown,
): import('./prospecting_contracts.js').ProviderErrorCode {
  if (status === 401 || status === 403) return 'NOT_CONFIGURED';
  if (status === 429) return 'RATE_LIMITED';
  if (status === 402) return 'INSUFFICIENT_CREDITS';

  const record = asRecord(body);
  const message = [
    asStringField(record?.error),
    asStringField(record?.error_message),
    asStringField(record?.message),
  ]
    .filter((value): value is string => value !== null)
    .join(' ')
    .toLowerCase();

  if (message.includes('credit') || message.includes('quota')) {
    return 'INSUFFICIENT_CREDITS';
  }
  if (message.includes('rate limit')) return 'RATE_LIMITED';
  if (status >= 500) return 'UNAVAILABLE';
  if (status === 422 || status === 400) return 'INVALID_SCHEMA';
  return 'UNAVAILABLE';
}

/**
 * Apollo's seniority if it sent one, the title's otherwise.
 *
 * Apollo's vocabulary is its own (`c_suite`, `head`), so it is translated
 * rather than cast. An unrecognised value falls through to the title, and an
 * unrecognised title falls through to `UNKNOWN` — never to `STAFF`.
 */
export function seniorityFrom(raw: unknown, title: string | null): Seniority {
  if (typeof raw === 'string') {
    switch (raw.trim().toLowerCase()) {
      case 'owner':
        return 'OWNER';
      case 'founder':
        return 'FOUNDER';
      case 'c_suite':
        return 'C_LEVEL';
      case 'partner':
      case 'head':
      case 'director':
      case 'vp':
        return 'DIRECTOR';
      case 'manager':
        return 'MANAGER';
      case 'senior':
      case 'entry':
      case 'intern':
        return 'STAFF';
      default:
        break;
    }
  }
  return seniorityFromTitle(title);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function asStringField(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function asNumberField(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}
