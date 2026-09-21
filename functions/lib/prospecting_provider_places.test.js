"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_provider_places_js_1 = require("./prospecting_provider_places.js");
const prospecting_providers_js_1 = require("./prospecting_providers.js");
function mockFetch(responder) {
    const calls = [];
    const fetchImpl = (async (input, init) => {
        const call = { url: String(input), init: init ?? {} };
        calls.push(call);
        const result = responder(call);
        return {
            ok: result.status >= 200 && result.status < 300,
            status: result.status,
            json: async () => result.body,
        };
    });
    return { fetchImpl, calls };
}
function provider(fetchImpl) {
    return new prospecting_provider_places_js_1.PlacesProvider({
        apiKey: 'secret-key',
        fetchImpl,
        baseUrl: 'https://places.googleapis.com/v1',
        searchCostUsd: 0.02,
        detailCostUsd: 0.03,
    });
}
function unconfigured(fetchImpl) {
    return new prospecting_provider_places_js_1.PlacesProvider({ apiKey: undefined, fetchImpl });
}
const CRITERIA = {
    industries: ['barbershop'],
    city: 'Maputo',
    province: null,
    country: 'Moçambique',
    employeeMin: 3,
    employeeMax: 20,
    limit: 25,
    cursor: null,
};
function place(overrides = {}) {
    return {
        id: 'places/ChIJxxxx',
        displayName: { text: 'Barbearia do Zé', languageCode: 'pt' },
        primaryType: 'barber_shop',
        types: ['barber_shop', 'point_of_interest', 'establishment'],
        formattedAddress: 'Av. 24 de Julho 100, Maputo, Moçambique',
        addressComponents: [
            { longText: 'Maputo', shortText: 'Maputo', types: ['locality'] },
            {
                longText: 'Maputo Cidade',
                shortText: 'MPM',
                types: ['administrative_area_level_1'],
            },
            { longText: 'Moçambique', shortText: 'MZ', types: ['country'] },
        ],
        rating: 4.6,
        userRatingCount: 87,
        businessStatus: 'OPERATIONAL',
        ...overrides,
    };
}
/* ---------------------------------------------------------------- the query */
(0, node_test_1.default)('the text query names the trade and the city, and never a coordinate', () => {
    const query = (0, prospecting_provider_places_js_1.buildTextQuery)(CRITERIA);
    strict_1.default.ok(query.includes('barbearia'));
    strict_1.default.ok(query.includes('Maputo'));
});
(0, node_test_1.default)('an empty industry list searches every ICP trade rather than nothing', () => {
    const query = (0, prospecting_provider_places_js_1.buildTextQuery)({ ...CRITERIA, industries: [] });
    strict_1.default.ok(query.includes('barbearia'));
    strict_1.default.ok(query.includes('OR'));
});
/* -------------------------------------------------------------- the mapping */
(0, node_test_1.default)('city, province and country come from the structured address', () => {
    const where = (0, prospecting_provider_places_js_1.placeFrom)([
        { longText: 'Matola', types: ['locality'] },
        { longText: 'Maputo', types: ['administrative_area_level_1'] },
        { longText: 'Moçambique', types: ['country'] },
    ]);
    strict_1.default.deepEqual(where, {
        city: 'Matola',
        province: 'Maputo',
        country: 'Moçambique',
    });
});
(0, node_test_1.default)('an address with no locality falls back rather than inventing one', () => {
    const where = (0, prospecting_provider_places_js_1.placeFrom)([
        { longText: 'Boane', types: ['administrative_area_level_2'] },
        { longText: 'Maputo', types: ['administrative_area_level_1'] },
    ]);
    strict_1.default.equal(where.city, 'Boane');
    strict_1.default.equal(where.country, null);
});
(0, node_test_1.default)('a trade is read from the Places type or from the name', () => {
    strict_1.default.equal((0, prospecting_provider_places_js_1.industryFromPlace)('barber_shop', [], 'Casa X'), 'barbershop');
    strict_1.default.equal((0, prospecting_provider_places_js_1.industryFromPlace)('hair_care', ['hair_care'], 'Salão Beleza'), 'salon');
    // Typed only as a generic establishment, but the name says what it is — and
    // that is precisely the lead worth having.
    strict_1.default.equal((0, prospecting_provider_places_js_1.industryFromPlace)('establishment', ['establishment'], 'Barbearia do Zé'), 'barbershop');
    strict_1.default.equal((0, prospecting_provider_places_js_1.industryFromPlace)('bank', ['bank'], 'Banco X'), null);
});
/* ------------------------------------------------------------------ search */
(0, node_test_1.default)('a search maps a listing into a company with its rating and reviews', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({
        status: 200,
        body: { places: [place()] },
    }));
    const results = await provider(fetchImpl).searchBusinesses(CRITERIA);
    strict_1.default.equal(results.length, 1);
    const company = results[0].company;
    strict_1.default.equal(company.name, 'Barbearia do Zé');
    strict_1.default.equal(company.industry, 'barbershop');
    strict_1.default.equal(company.rating, 4.6);
    strict_1.default.equal(company.review_count, 87);
    strict_1.default.equal(company.business_status, 'OPERATIONAL');
    strict_1.default.equal(company.city, 'Maputo');
    strict_1.default.equal(company.source, 'places');
    strict_1.default.equal(company.source_reference, 'places/ChIJxxxx');
    // The key travels in a header, never in the URL: a key in a query string is
    // in every access log between here and Google.
    strict_1.default.ok(!calls[0].url.includes('secret-key'));
    const headers = calls[0].init.headers;
    strict_1.default.equal(headers['X-Goog-Api-Key'], 'secret-key');
});
(0, node_test_1.default)('the cheap mask is what a search sends, and it asks for no contact details', () => {
    // The mask is the price. Phone and website belong to the dear call, and a
    // test that pins this is the thing that catches a field quietly added to
    // the search and silently moving every campaign to a higher tier.
    strict_1.default.ok(prospecting_provider_places_js_1.SEARCH_FIELD_MASK.includes('places.rating'));
    strict_1.default.ok(prospecting_provider_places_js_1.SEARCH_FIELD_MASK.includes('places.userRatingCount'));
    strict_1.default.ok(!prospecting_provider_places_js_1.SEARCH_FIELD_MASK.includes('nationalPhoneNumber'));
    strict_1.default.ok(!prospecting_provider_places_js_1.SEARCH_FIELD_MASK.includes('websiteUri'));
    strict_1.default.ok(!prospecting_provider_places_js_1.SEARCH_FIELD_MASK.includes('regularOpeningHours'));
    strict_1.default.ok(prospecting_provider_places_js_1.DETAIL_FIELD_MASK.includes('websiteUri'));
    strict_1.default.ok(prospecting_provider_places_js_1.DETAIL_FIELD_MASK.includes('internationalPhoneNumber'));
});
(0, node_test_1.default)('a search leaves phone, website and the listing extras unasked', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 200, body: { places: [place()] } }));
    const company = (await provider(fetchImpl).searchBusinesses(CRITERIA))[0].company;
    strict_1.default.equal(company.phone, null);
    strict_1.default.equal(company.website, null);
    // Null, not false: nobody looked, which is a different answer from "none".
    strict_1.default.equal(company.has_opening_hours, null);
    strict_1.default.equal(company.has_photos, null);
});
(0, node_test_1.default)('a listing with no rating yet is null, not zero', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: { places: [place({ rating: undefined, userRatingCount: undefined })] },
    }));
    const company = (await provider(fetchImpl).searchBusinesses(CRITERIA))[0].company;
    strict_1.default.equal(company.rating, null);
    strict_1.default.equal(company.review_count, null);
});
(0, node_test_1.default)('the page token goes out as a cursor and comes back on every result', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({
        status: 200,
        body: { places: [place()], nextPageToken: 'token-2' },
    }));
    const first = await provider(fetchImpl).searchBusinesses(CRITERIA);
    strict_1.default.equal(first[0].cursor, 'token-2');
    await provider(fetchImpl).searchBusinesses({ ...CRITERIA, cursor: 'token-2' });
    const body = JSON.parse(String(calls[1].init.body));
    strict_1.default.equal(body.pageToken, 'token-2');
});
(0, node_test_1.default)('a page is never asked for more than twenty results', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: { places: [] } }));
    await provider(fetchImpl).searchBusinesses({ ...CRITERIA, limit: 500 });
    const body = JSON.parse(String(calls[0].init.body));
    strict_1.default.equal(body.pageSize, prospecting_provider_places_js_1.MAX_PAGE_SIZE);
});
(0, node_test_1.default)('one malformed listing costs that listing, not the page', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: {
            places: [
                { id: 'places/broken' }, // no displayName
                place(),
                { displayName: { text: 'Sem id' } }, // no id, so no dedup key
            ],
        },
    }));
    const results = await provider(fetchImpl).searchBusinesses(CRITERIA);
    strict_1.default.equal(results.length, 1);
    strict_1.default.equal(results[0].company.name, 'Barbearia do Zé');
});
(0, node_test_1.default)('a rating outside the 0-5 scale is refused rather than scored', async () => {
    // `assertCompanySane` throws, `toCompany` drops the listing. A provider
    // whose scale is not the assumed one must not quietly hand every lead five
    // points for the wrong reason.
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: { places: [place({ rating: 9.2 })] },
    }));
    strict_1.default.deepEqual(await provider(fetchImpl).searchBusinesses(CRITERIA), []);
});
/* ------------------------------------------------------------------ detail */
(0, node_test_1.default)('the detail call returns the contact fields and the listing extras', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({
        status: 200,
        body: {
            id: 'places/ChIJxxxx',
            internationalPhoneNumber: '+258 84 000 0101',
            websiteUri: 'https://barbearia.test',
            regularOpeningHours: { periods: [{ open: { day: 1, hour: 8 } }] },
            photos: [{ name: 'places/ChIJxxxx/photos/1' }],
        },
    }));
    const detail = await provider(fetchImpl).fetchListingDetail({
        reference: 'places/ChIJxxxx',
    });
    strict_1.default.equal(detail.phone, '+258 84 000 0101');
    strict_1.default.equal(detail.website, 'https://barbearia.test');
    strict_1.default.equal(detail.hasOpeningHours, true);
    strict_1.default.equal(detail.hasPhotos, true);
    strict_1.default.ok(calls[0].url.includes('places%2FChIJxxxx'));
});
(0, node_test_1.default)('a detail response missing a requested field answers "none", not "unknown"', async () => {
    // The field was asked for, so its absence is the answer. This is the one
    // place in the module where false beats null, and it is because the mask
    // makes the question explicit.
    const { fetchImpl } = mockFetch(() => ({ status: 200, body: { id: 'places/x' } }));
    const detail = await provider(fetchImpl).fetchListingDetail({ reference: 'places/x' });
    strict_1.default.equal(detail.hasOpeningHours, false);
    strict_1.default.equal(detail.hasPhotos, false);
    strict_1.default.equal(detail.phone, null);
    strict_1.default.equal(detail.website, null);
});
(0, node_test_1.default)('the international number wins over the national one', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: {
            id: 'places/x',
            internationalPhoneNumber: '+258840000101',
            nationalPhoneNumber: '84 000 0101',
        },
    }));
    const detail = await provider(fetchImpl).fetchListingDetail({ reference: 'places/x' });
    strict_1.default.equal(detail.phone, '+258840000101');
});
(0, node_test_1.default)('an empty reference is refused before a request is made', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: {} }));
    await strict_1.default.rejects(() => provider(fetchImpl).fetchListingDetail({ reference: '  ' }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
    strict_1.default.equal(calls.length, 0);
});
/* ------------------------------------------------------------------ errors */
(0, node_test_1.default)('an unset key is NOT_CONFIGURED and costs no request', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: {} }));
    await strict_1.default.rejects(() => unconfigured(fetchImpl).searchBusinesses(CRITERIA), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NOT_CONFIGURED');
    strict_1.default.equal(calls.length, 0);
    strict_1.default.equal(unconfigured(fetchImpl).isConfigured(), false);
});
(0, node_test_1.default)('HTTP statuses map to the code the chain acts on', () => {
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(401, null), 'NOT_CONFIGURED');
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(403, null), 'NOT_CONFIGURED');
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(429, null), 'RATE_LIMITED');
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(500, null), 'UNAVAILABLE');
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(400, null), 'INVALID_SCHEMA');
});
(0, node_test_1.default)('a disabled billing account is not a credentials problem', () => {
    // 403 with a billing message is not something re-pasting a key fixes, and
    // telling an operator to check their key would send them to the wrong screen.
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(403, { error: { message: 'Billing has not been enabled' } }), 'INSUFFICIENT_CREDITS');
    strict_1.default.equal((0, prospecting_provider_places_js_1.statusToCode)(429, { error: { status: 'RESOURCE_EXHAUSTED' } }), 'INSUFFICIENT_CREDITS');
});
(0, node_test_1.default)('a non-object body is a schema error, not an empty result', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 200, body: 'not json' }));
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses(CRITERIA), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
});
/* -------------------------------------------------------------------- cost */
(0, node_test_1.default)('the reported cost distinguishes the cheap call from the dear one', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 200, body: { places: [place()] } }));
    const places = provider(fetchImpl);
    await places.searchBusinesses(CRITERIA);
    strict_1.default.equal(places.lastCostUsd, 0.02);
    strict_1.default.equal(places.estimatedCostUsd(), 0.02);
    const detail = mockFetch(() => ({ status: 200, body: { id: 'places/x' } }));
    const second = provider(detail.fetchImpl);
    await second.fetchListingDetail({ reference: 'places/x' });
    strict_1.default.equal(second.lastCostUsd, 0.03);
    strict_1.default.equal(second.estimatedCostUsd(), 0.03);
});
(0, node_test_1.default)('a refused call reports no cost', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 429, body: {} }));
    const places = provider(fetchImpl);
    await strict_1.default.rejects(() => places.searchBusinesses(CRITERIA));
    strict_1.default.equal(places.lastCostUsd, null);
});
