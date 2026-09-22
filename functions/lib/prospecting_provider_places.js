"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlacesProvider = exports.UNSUPPORTED_FILTERS = exports.DETAIL_FIELD_MASK = exports.SEARCH_FIELD_MASK = exports.MAX_PAGE_SIZE = exports.PLACES_KEY = void 0;
exports.buildTextQuery = buildTextQuery;
exports.placeFrom = placeFrom;
exports.industryFromPlace = industryFromPlace;
exports.statusToCode = statusToCode;
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_providers_js_1 = require("./prospecting_providers.js");
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
const DEFAULT_TIMEOUT_MS = 20000;
exports.PLACES_KEY = 'places';
/** The most results one `searchText` call may return. */
exports.MAX_PAGE_SIZE = 20;
/**
 * The cheap mask: what a lead is scored on before anything is paid for twice.
 *
 * Every entry here feeds a criterion in `DEFAULT_SCORING`. Nothing is
 * requested "in case it is useful later" — an unused field is a tier upgrade
 * bought for nothing.
 */
exports.SEARCH_FIELD_MASK = [
    'places.id',
    'places.displayName',
    'places.primaryType',
    'places.types',
    'places.formattedAddress',
    'places.addressComponents',
    // Deduplication, not mapping. Costs nothing extra here: the SKU is set by
    // the dearest field asked for, `location` sits in the Pro tier, and this
    // mask already asks for `rating` and `userRatingCount`, which are
    // Enterprise. Adding a Pro field under an Enterprise mask does not move the
    // tier. Not yet checked against an invoice — see ESTIMATES_VERIFIED.
    'places.location',
    'places.rating',
    'places.userRatingCount',
    'places.businessStatus',
    'nextPageToken',
].join(',');
/** The dear mask: only ever sent about a business that cleared the gate. */
exports.DETAIL_FIELD_MASK = [
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
exports.UNSUPPORTED_FILTERS = ['employeeMin', 'employeeMax'];
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
function buildTextQuery(criteria) {
    const trades = criteria.industries.length === 0
        ? prospecting_config_js_1.ICP_INDUSTRIES.map((entry) => entry.keywords[0])
        : criteria.industries
            .map((id) => (0, prospecting_config_js_1.findIcpIndustry)(id))
            .filter((entry) => entry !== null)
            .map((entry) => entry.keywords[0]);
    const where = [criteria.city, criteria.province]
        .filter((part) => typeof part === 'string' && part.trim() !== '')
        // The city already implies the province in every target geography this
        // sells in, and repeating both narrows the text match for no gain.
        .slice(0, 1);
    const what = trades.length === 0 ? 'negócios' : trades.join(' OR ');
    return where.length === 0 ? what : `${what} em ${where[0]}`;
}
/**
 * City, province and country out of the structured address.
 *
 * Read from `addressComponents` rather than parsed out of the formatted
 * address, because the formatted string's shape varies by country and a
 * split on commas would put a street name in the city field for any listing
 * that happens to have one part fewer. Absent components stay null, which the
 * scoring engine reads as "not known" rather than "not the target".
 */
function placeFrom(components) {
    const find = (type) => components.find((entry) => entry.types.includes(type))?.longText ?? null;
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
function industryFromPlace(primaryType, types, name) {
    const haystack = [primaryType ?? '', types.join(' '), name]
        .join(' ')
        .normalize('NFD')
        .replace(/\p{M}/gu, '')
        // Places types are snake_case; the keywords are words.
        .replace(/_/g, ' ')
        .toLowerCase();
    for (const entry of prospecting_config_js_1.ICP_INDUSTRIES) {
        for (const keyword of entry.keywords) {
            const folded = keyword.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
            if (containsWord(haystack, folded))
                return entry.businessType;
        }
    }
    return null;
}
/**
 * Whether the keyword appears as a word, not merely as a run of letters.
 *
 * `includes` was matching inside words, and the short keywords made that
 * expensive: "spa" sits inside "Sparkle" and inside "Espaço" — a word that
 * names a great many Mozambican businesses. A car wash called "Sparkle Car
 * Wash", typed `car_wash` by Places, was being classified as a spa, and the
 * ICP is not cosmetic: it drives the retention criteria and is stored as the
 * lead's trade. The lead came out wrong, scored wrong, and said nothing.
 *
 * Boundaries are non-letters rather than `\b`, so accented characters count
 * as part of a word — with `\b`, "estética" would end a word at the "é".
 * Multi-word keywords work unchanged, since only the two outer edges are
 * tested.
 */
function containsWord(haystack, keyword) {
    if (keyword === '')
        return false;
    let from = 0;
    for (;;) {
        const at = haystack.indexOf(keyword, from);
        if (at === -1)
            return false;
        const before = at === 0 ? '' : haystack[at - 1];
        const after = haystack[at + keyword.length] ?? '';
        if (!isWordCharacter(before) && !isWordCharacter(after))
            return true;
        from = at + 1;
    }
}
const isWordCharacter = (character) => character !== '' && /[\p{L}\p{N}]/u.test(character);
/** HTTP status and body, mapped to the code the chain acts on. */
function statusToCode(status, body) {
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
    if (status === 401 || status === 403)
        return 'NOT_CONFIGURED';
    if (status === 429)
        return 'RATE_LIMITED';
    if (status >= 500)
        return 'UNAVAILABLE';
    if (status === 400 || status === 404 || status === 422)
        return 'INVALID_SCHEMA';
    return 'UNAVAILABLE';
}
/* ------------------------------------------------------------ the adapter */
class PlacesProvider {
    constructor(options) {
        this.key = exports.PLACES_KEY;
        /** What the last call actually cost, when the caller set a price. */
        this.lastCostUsd = null;
        this.lastOperation = null;
        this.options = options;
    }
    isConfigured() {
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
    estimatedCostUsd() {
        return this.lastOperation === 'FETCH_LISTING_DETAILS'
            ? (this.options.detailCostUsd ?? 0)
            : (this.options.searchCostUsd ?? 0);
    }
    /**
     * One request, with every failure turned into a typed one.
     *
     * The key goes in a header and never into the URL: a Places key in a query
     * string ends up in every proxy log and access log between here and Google,
     * and the same key is billable by anyone who reads one.
     */
    async request(operation, path, init) {
        const apiKey = this.options.apiKey;
        if (typeof apiKey !== 'string' || apiKey.trim() === '') {
            throw new prospecting_providers_js_1.ProviderError({
                code: 'NOT_CONFIGURED',
                provider: this.key,
                operation,
                detail: 'GOOGLE_PLACES_API_KEY is not set',
            });
        }
        this.lastOperation = operation;
        this.lastCostUsd = null;
        const fetchImpl = this.options.fetchImpl ?? fetch;
        const url = new URL(`${DEFAULT_BASE_URL}${path}`);
        for (const [name, value] of Object.entries(init.query ?? {})) {
            url.searchParams.set(name, value);
        }
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
        let response;
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
        }
        catch (error) {
            const aborted = error instanceof Error &&
                (error.name === 'AbortError' || error.name === 'TimeoutError');
            throw new prospecting_providers_js_1.ProviderError({
                code: aborted ? 'TIMEOUT' : 'UNAVAILABLE',
                provider: this.key,
                operation,
                detail: aborted ? 'request timed out' : 'network error',
            });
        }
        finally {
            clearTimeout(timer);
        }
        let body = null;
        try {
            body = await response.json();
        }
        catch {
            body = null;
        }
        if (!response.ok) {
            throw new prospecting_providers_js_1.ProviderError({
                code: statusToCode(response.status, body),
                provider: this.key,
                operation,
                // The body can name the place that was looked up, so only the status
                // travels into the log.
                detail: `HTTP ${response.status}`,
            });
        }
        if (body === null || typeof body !== 'object' || Array.isArray(body)) {
            throw new prospecting_providers_js_1.ProviderError({
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
        return body;
    }
    /* ------------------------------------------------------------- stage one */
    async searchBusinesses(criteria) {
        const body = {
            textQuery: buildTextQuery(criteria),
            pageSize: Math.max(1, Math.min(exports.MAX_PAGE_SIZE, criteria.limit)),
            languageCode: 'pt',
            regionCode: 'MZ',
        };
        if (criteria.cursor !== null && criteria.cursor.trim() !== '') {
            body.pageToken = criteria.cursor;
        }
        const response = await this.request('SEARCH_BUSINESSES', '/places:searchText', {
            method: 'POST',
            fieldMask: exports.SEARCH_FIELD_MASK,
            body,
        });
        const places = Array.isArray(response.places) ? response.places : [];
        const cursor = asStringField(response.nextPageToken);
        const results = [];
        for (const entry of places) {
            const record = asRecord(entry);
            if (record === null)
                continue;
            const company = this.toCompany(record);
            // One malformed listing in a page of twenty costs that listing, not the
            // page. A malformed *page* is a different thing and threw above.
            if (company !== null)
                results.push({ company, cursor });
        }
        return results;
    }
    toCompany(place) {
        const id = asStringField(place.id);
        const name = asStringField(asRecord(place.displayName)?.text);
        if (id === null || name === null)
            return null;
        const types = Array.isArray(place.types)
            ? place.types.filter((value) => typeof value === 'string')
            : [];
        const components = Array.isArray(place.addressComponents)
            ? place.addressComponents.flatMap((value) => {
                const component = asRecord(value);
                if (component === null)
                    return [];
                return [
                    {
                        longText: asStringField(component.longText),
                        types: Array.isArray(component.types)
                            ? component.types.filter((entry) => typeof entry === 'string')
                            : [],
                    },
                ];
            })
            : [];
        const where = placeFrom(components);
        const record = {
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
            latitude: asNumberField(asRecord(place.location)?.latitude),
            longitude: asNumberField(asRecord(place.location)?.longitude),
            source: this.key,
            // The place id is the deduplication key, and the only field Google
            // permits being stored indefinitely.
            source_reference: id,
            provider_org_id: id,
        };
        try {
            return (0, prospecting_providers_js_1.assertCompanySane)(record, this.key, 'SEARCH_BUSINESSES');
        }
        catch {
            return null;
        }
    }
    /* ------------------------------------------------------------- stage two */
    async fetchListingDetail(input) {
        const reference = input.reference.trim();
        if (reference === '') {
            throw new prospecting_providers_js_1.ProviderError({
                code: 'INVALID_SCHEMA',
                provider: this.key,
                operation: 'FETCH_LISTING_DETAILS',
                detail: 'no place reference',
            });
        }
        const response = await this.request('FETCH_LISTING_DETAILS', `/places/${encodeURIComponent(reference)}`, { method: 'GET', fieldMask: exports.DETAIL_FIELD_MASK });
        const hours = asRecord(response.regularOpeningHours);
        const photos = response.photos;
        return {
            // International first: the stored number is dialled from a phone that
            // may not be in Mozambique, and the national form is ambiguous the
            // moment it leaves the country.
            phone: asStringField(response.internationalPhoneNumber) ??
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
exports.PlacesProvider = PlacesProvider;
/* ------------------------------------------------------------------ utils */
function asRecord(value) {
    if (value === null || typeof value !== 'object' || Array.isArray(value))
        return null;
    return value;
}
function asStringField(value) {
    if (typeof value !== 'string')
        return null;
    const trimmed = value.trim();
    return trimmed === '' ? null : trimmed;
}
function asNumberField(value) {
    if (typeof value === 'number' && Number.isFinite(value))
        return value;
    if (typeof value === 'string' && value.trim() !== '') {
        const parsed = Number(value);
        if (Number.isFinite(parsed))
            return parsed;
    }
    return null;
}
