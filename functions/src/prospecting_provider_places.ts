import { ICP_INDUSTRIES, findIcpIndustry } from './prospecting_config.js';
import type { ProviderErrorCode, ProviderOperation } from './prospecting_contracts.js';
import {
  assertCompanySane,
  ProviderError,
  type BusinessDiscoveryProvider,
  type BusinessDiscoveryResult,
  type BusinessSearchCriteria,
  type CompanyRecord,
  type ListingDetailInput,
  type ListingDetailProvider,
  type ListingDetailResult,
} from './prospecting_providers.js';

/**
 * Google Places, as two calls priced apart.
 *
 * Written against the Places API (New), which bills by the *field mask* as
 * well as by the request: asking for a name, a trade and a rating is one
 * price, and asking for the phone number and the website is a dearer one. That
 * is not an implementation detail to be hidden behind a single `search()` —
 * it is the only variable cost this module has left, so it is the thing the
 * adapter is shaped around.
 *
 *   POST /v1/places:searchText   — the cheap half. Everything the scoring
 *                                  engine can use to decide whether a lead is
 *                                  worth paying more for.
 *   GET  /v1/places/{id}         — the dear half. Phone, website, timetable,
 *                                  photos. Asked only about a business that
 *                                  already cleared the score gate.
 *
 * Both authenticate with `X-Goog-Api-Key` and both require `X-Goog-FieldMask`.
 * The masks are module constants rather than inline strings precisely because
 * they are the price: a field added to `SEARCH_FIELD_MASK` moves every
 * discovery call to a dearer tier, and that should be a visible edit to a
 * named constant, reviewed as the cost change it is.
 *
 * Three things the API does that shape this adapter:
 *
 * **A page is at most twenty results.** `pageSize` is capped there, and more
 * results mean more billed requests. The chain pages through `cursor`, so a
 * campaign for 500 businesses is 25 search calls, not one.
 *
 * **There is no headcount, and there never will be.** Places describes
 * storefronts, not companies. `employeeMin`/`employeeMax` on the criteria are
 * therefore unsatisfiable here — see `UNSUPPORTED_FILTERS`. They are reported
 * rather than silently dropped, because a caller that believes it filtered by
 * size and did not will read the result as evidence about shop sizes.
 *
 * **`nextPageToken` is not immediately valid.** Google documents a short delay
 * before a freshly issued token can be used. The adapter passes it back out as
 * an opaque cursor and does not retry on its behalf; the job that walks pages
 * is already spaced by its own work.
 */

const DEFAULT_BASE_URL = 'https://places.googleapis.com/v1';
const DEFAULT_TIMEOUT_MS = 20_000;
export const PLACES_KEY = 'places';

/** The most results one `searchText` call may return. */
export const MAX_PAGE_SIZE = 20;

/**
 * The cheap mask: what a lead is scored on before anything is paid for twice.
 *
 * Every entry here feeds a criterion in `DEFAULT_SCORING`. Nothing is
 * requested "in case it is useful later" — an unused field is a tier upgrade
 * bought for nothing.
 */
export const SEARCH_FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.primaryType',
  'places.types',
  'places.formattedAddress',
  'places.addressComponents',
  'places.rating',
  'places.userRatingCount',
  'places.businessStatus',
  'nextPageToken',
].join(',');

/** The dear mask: only ever sent about a business that cleared the gate. */
export const DETAIL_FIELD_MASK = [
  'id',
  'internationalPhoneNumber',
  'nationalPhoneNumber',
  'websiteUri',
  'regularOpeningHours',
  'photos',
].join(',');

/**
 * Criteria fields this source cannot honour.
 *
 * Stated as data so the pipeline can log it once per search rather than
 * leaving it as a comment nobody reads.
 */
export const UNSUPPORTED_FILTERS = ['employeeMin', 'employeeMax'] as const;

export type PlacesOptions = {
  apiKey: string | undefined;
  baseUrl?: string;
  timeoutMs?: number;
  /** Injected so the adapter can be exercised without a network. */
  fetchImpl?: typeof fetch;
  /** What one search and one detail call are expected to cost, in USD. */
  searchCostUsd?: number;
  detailCostUsd?: number;
};

/* ------------------------------------------------------------- the query */

/**
 * The text query for a set of ICP trades in a place.
 *
 * Deliberately a text query and not a coordinate circle. A circle needs a
 * centre, and this module has no coordinates for its cities — only names, in
 * `TargetGeography`. Inventing a latitude for "Maputo" to make the request
 * look more precise would be exactly the fabrication the rest of the module
 * refuses: the radius would be real and the centre would be a guess, and the
 * campaign would quietly miss whole neighbourhoods on one side of it.
 *
 * `regionCode` does the disambiguation that the circle would have done, and
 * the city goes in the query text where a human would put it.
 */
export function buildTextQuery(criteria: BusinessSearchCriteria): string {
  const trades =
    criteria.industries.length === 0
      ? ICP_INDUSTRIES.map((entry) => entry.keywords[0])
      : criteria.industries
          .map((id) => findIcpIndustry(id))
          .filter((entry): entry is NonNullable<typeof entry> => entry !== null)
          .map((entry) => entry.keywords[0]);

  const where = [criteria.city, criteria.province]
    .filter((part): part is string => typeof part === 'string' && part.trim() !== '')
    // The city already implies the province in every target geography this
    // sells in, and repeating both narrows the text match for no gain.
    .slice(0, 1);

  const what = trades.length === 0 ? 'negócios' : trades.join(' OR ');
  return where.length === 0 ? what : `${what} em ${where[0]}`;
}

/* ------------------------------------------------------------- the mapping */

type AddressComponent = {
  longText: string | null;
  types: readonly string[];
};

/**
 * City, province and country out of the structured address.
 *
 * Read from `addressComponents` rather than parsed out of the formatted
 * address, because the formatted string's shape varies by country and a
 * split on commas would put a street name in the city field for any listing
 * that happens to have one part fewer. Absent components stay null, which the
 * scoring engine reads as "not known" rather than "not the target".
 */
export function placeFrom(components: readonly AddressComponent[]): {
  city: string | null;
  province: string | null;
  country: string | null;
} {
  const find = (type: string): string | null =>
    components.find((entry) => entry.types.includes(type))?.longText ?? null;

  return {
    // `locality` is the city proper; `postal_town` is what some countries use
    // instead, and falling back to the second-level admin area catches the
    // listings that carry neither.
    city: find('locality') ?? find('postal_town') ?? find('administrative_area_level_2'),
    province: find('administrative_area_level_1'),
    country: find('country'),
  };
}

/**
 * A place's trade, as an ICP id.
 *
 * Places carries a `primaryType` from its own taxonomy (`hair_care`,
 * `barber_shop`, ...) plus a `types` array, and the ICP keywords are in
 * Portuguese and English. Matching runs over the type strings *and* the
 * business name, because a shop called "Barbearia do Zé" typed only as
 * `establishment` is still a barbershop and is exactly the lead worth having.
 */
export function industryFromPlace(
  primaryType: string | null,
  types: readonly string[],
  name: string,
): string | null {
  const haystack = [primaryType ?? '', types.join(' '), name]
    .join(' ')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    // Places types are snake_case; the keywords are words.
    .replace(/_/g, ' ')
    .toLowerCase();

  for (const entry of ICP_INDUSTRIES) {
    for (const keyword of entry.keywords) {
      const folded = keyword.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
      if (haystack.includes(folded)) return entry.businessType;
    }
  }
  return null;
}

/** HTTP status and body, mapped to the code the chain acts on. */
export function statusToCode(status: number, body: unknown): ProviderErrorCode {
  const error = asRecord(asRecord(body)?.error);
  const message = (asStringField(error?.message) ?? '').toLowerCase();
  const reason = (asStringField(error?.status) ?? '').toLowerCase();

  // The body is read before the status is judged, and that order is the whole
  // point. Google returns a disabled billing account as 403 and an exhausted
  // quota as 429 — the same statuses as a bad key and an ordinary rate limit.
  // Judging the status first would send an operator whose card expired to the
  // screen where they re-paste an API key that was never the problem.
  if (message.includes('billing') || reason === 'resource_exhausted') {
    return 'INSUFFICIENT_CREDITS';
  }
  if (message.includes('quota') || message.includes('rate limit')) {
    return 'RATE_LIMITED';
  }

  if (status === 401 || status === 403) return 'NOT_CONFIGURED';
  if (status === 429) return 'RATE_LIMITED';
  if (status >= 500) return 'UNAVAILABLE';
  if (status === 400 || status === 404 || status === 422) return 'INVALID_SCHEMA';
  return 'UNAVAILABLE';
}

/* ------------------------------------------------------------ the adapter */

export class PlacesProvider
  implements BusinessDiscoveryProvider, ListingDetailProvider
{
  readonly key = PLACES_KEY;
  /** What the last call actually cost, when the caller set a price. */
  lastCostUsd: number | null = null;
  private readonly options: PlacesOptions;
  private lastOperation: ProviderOperation | null = null;

  constructor(options: PlacesOptions) {
    this.options = options;
  }

  isConfigured(): boolean {
    const key = this.options.apiKey;
    return typeof key === 'string' && key.trim() !== '';
  }

  /**
   * What the next call is expected to cost.
   *
   * Reads the operation the adapter is about to perform, because the two
   * halves are priced differently and a single number would misreport one of
   * them by design. Zero when the caller configured no price — the budget
   * guard treats that as "not costed here" and falls back to the table.
   */
  estimatedCostUsd(): number {
    return this.lastOperation === 'FETCH_LISTING_DETAILS'
      ? (this.options.detailCostUsd ?? 0)
      : (this.options.searchCostUsd ?? 0);
  }

  private baseUrl(): string {
    return (this.options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, '');
  }

  /**
   * One request, with every failure turned into a typed one.
   *
   * The key goes in a header and never into the URL: a Places key in a query
   * string ends up in every proxy log and access log between here and Google,
   * and the same key is billable by anyone who reads one.
   */
  private async request(
    operation: ProviderOperation,
    path: string,
    init: {
      method: 'GET' | 'POST';
      fieldMask: string;
      body?: unknown;
      query?: Record<string, string>;
    },
  ): Promise<Record<string, unknown>> {
    const apiKey = this.options.apiKey;
    if (typeof apiKey !== 'string' || apiKey.trim() === '') {
      throw new ProviderError({
        code: 'NOT_CONFIGURED',
        provider: this.key,
        operation,
        detail: 'GOOGLE_PLACES_API_KEY is not set',
      });
    }

    this.lastOperation = operation;
    this.lastCostUsd = null;

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
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': init.fieldMask,
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
        // The body can name the place that was looked up, so only the status
        // travels into the log.
        detail: `HTTP ${response.status}`,
      });
    }

    if (body === null || typeof body !== 'object' || Array.isArray(body)) {
      throw new ProviderError({
        code: 'INVALID_SCHEMA',
        provider: this.key,
        operation,
        detail: 'response body is not an object',
      });
    }

    // A call that reached Google was billed, whatever it returned.
    this.lastCostUsd =
      operation === 'FETCH_LISTING_DETAILS'
        ? (this.options.detailCostUsd ?? null)
        : (this.options.searchCostUsd ?? null);

    return body as Record<string, unknown>;
  }

  /* ------------------------------------------------------------- stage one */

  async searchBusinesses(
    criteria: BusinessSearchCriteria,
  ): Promise<BusinessDiscoveryResult[]> {
    const body: Record<string, unknown> = {
      textQuery: buildTextQuery(criteria),
      pageSize: Math.max(1, Math.min(MAX_PAGE_SIZE, criteria.limit)),
      languageCode: 'pt',
      regionCode: 'MZ',
    };
    if (criteria.cursor !== null && criteria.cursor.trim() !== '') {
      body.pageToken = criteria.cursor;
    }

    const response = await this.request('SEARCH_BUSINESSES', '/places:searchText', {
      method: 'POST',
      fieldMask: SEARCH_FIELD_MASK,
      body,
    });

    const places = Array.isArray(response.places) ? response.places : [];
    const cursor = asStringField(response.nextPageToken);

    const results: BusinessDiscoveryResult[] = [];
    for (const entry of places) {
      const record = asRecord(entry);
      if (record === null) continue;
      const company = this.toCompany(record);
      // One malformed listing in a page of twenty costs that listing, not the
      // page. A malformed *page* is a different thing and threw above.
      if (company !== null) results.push({ company, cursor });
    }
    return results;
  }

  private toCompany(place: Record<string, unknown>): CompanyRecord | null {
    const id = asStringField(place.id);
    const name = asStringField(asRecord(place.displayName)?.text);
    if (id === null || name === null) return null;

    const types = Array.isArray(place.types)
      ? place.types.filter((value): value is string => typeof value === 'string')
      : [];
    const components = Array.isArray(place.addressComponents)
      ? place.addressComponents.flatMap((value): AddressComponent[] => {
          const component = asRecord(value);
          if (component === null) return [];
          return [
            {
              longText: asStringField(component.longText),
              types: Array.isArray(component.types)
                ? component.types.filter(
                    (entry): entry is string => typeof entry === 'string',
                  )
                : [],
            },
          ];
        })
      : [];
    const where = placeFrom(components);

    const record: CompanyRecord = {
      name,
      legal_name: null,
      domain: null,
      // The website is in the dear mask. Null here is "not asked", and the
      // scoring engine reads a null website as no website — which is correct
      // at this stage: nothing has looked for one yet.
      website: null,
      industry: industryFromPlace(asStringField(place.primaryType), types, name),
      industry_raw: asStringField(place.primaryType),
      employee_count: null,
      city: where.city,
      province: where.province,
      country: where.country,
      address: asStringField(place.formattedAddress),
      phone: null,
      email: null,
      linkedin_url: null,
      instagram_url: null,
      facebook_url: null,
      whatsapp: null,
      rating: asNumberField(place.rating),
      review_count: asNumberField(place.userRatingCount),
      // Not in the cheap mask, and not guessed at.
      has_opening_hours: null,
      has_photos: null,
      business_status: asStringField(place.businessStatus),
      source: this.key,
      // The place id is the deduplication key, and the only field Google
      // permits being stored indefinitely.
      source_reference: id,
      provider_org_id: id,
    };

    try {
      return assertCompanySane(record, this.key, 'SEARCH_BUSINESSES');
    } catch {
      return null;
    }
  }

  /* ------------------------------------------------------------- stage two */

  async fetchListingDetail(input: ListingDetailInput): Promise<ListingDetailResult> {
    const reference = input.reference.trim();
    if (reference === '') {
      throw new ProviderError({
        code: 'INVALID_SCHEMA',
        provider: this.key,
        operation: 'FETCH_LISTING_DETAILS',
        detail: 'no place reference',
      });
    }

    const response = await this.request(
      'FETCH_LISTING_DETAILS',
      `/places/${encodeURIComponent(reference)}`,
      { method: 'GET', fieldMask: DETAIL_FIELD_MASK },
    );

    const hours = asRecord(response.regularOpeningHours);
    const photos = response.photos;

    return {
      // International first: the stored number is dialled from a phone that
      // may not be in Mozambique, and the national form is ambiguous the
      // moment it leaves the country.
      phone:
        asStringField(response.internationalPhoneNumber) ??
        asStringField(response.nationalPhoneNumber),
      website: asStringField(response.websiteUri),
      // The field was requested, so its absence is an answer: this listing
      // publishes no timetable. Distinct from the null a search result
      // carries, which means nobody asked.
      hasOpeningHours: hours !== null && Array.isArray(hours.periods)
        ? hours.periods.length > 0
        : false,
      hasPhotos: Array.isArray(photos) ? photos.length > 0 : false,
    };
  }
}

/* ------------------------------------------------------------------ utils */

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
