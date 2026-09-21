import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildTextQuery,
  DETAIL_FIELD_MASK,
  industryFromPlace,
  MAX_PAGE_SIZE,
  placeFrom,
  PlacesProvider,
  SEARCH_FIELD_MASK,
  statusToCode,
} from './prospecting_provider_places.js';
import { ProviderError } from './prospecting_providers.js';

/**
 * The adapter against a mocked `fetch`.
 *
 * Every response shape here is the one the Places API (New) documents, with
 * the field names it uses — `places`, `displayName.text`, `userRatingCount`,
 * `regularOpeningHours.periods`, `internationalPhoneNumber`. A test written
 * against a shape this adapter invented would pass forever and prove nothing.
 */

type MockCall = { url: string; init: RequestInit };

function mockFetch(
  responder: (call: MockCall) => { status: number; body: unknown },
): { fetchImpl: typeof fetch; calls: MockCall[] } {
  const calls: MockCall[] = [];
  const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = { url: String(input), init: init ?? {} };
    calls.push(call);
    const result = responder(call);
    return {
      ok: result.status >= 200 && result.status < 300,
      status: result.status,
      json: async () => result.body,
    } as Response;
  }) as unknown as typeof fetch;

  return { fetchImpl, calls };
}

function provider(fetchImpl: typeof fetch) {
  return new PlacesProvider({
    apiKey: 'secret-key',
    fetchImpl,
    baseUrl: 'https://places.googleapis.com/v1',
    searchCostUsd: 0.02,
    detailCostUsd: 0.03,
  });
}

function unconfigured(fetchImpl: typeof fetch) {
  return new PlacesProvider({ apiKey: undefined, fetchImpl });
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
} as const;

function place(overrides: Record<string, unknown> = {}) {
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

test('the text query names the trade and the city, and never a coordinate', () => {
  const query = buildTextQuery(CRITERIA);
  assert.ok(query.includes('barbearia'));
  assert.ok(query.includes('Maputo'));
});

test('an empty industry list searches every ICP trade rather than nothing', () => {
  const query = buildTextQuery({ ...CRITERIA, industries: [] });
  assert.ok(query.includes('barbearia'));
  assert.ok(query.includes('OR'));
});

/* -------------------------------------------------------------- the mapping */

test('city, province and country come from the structured address', () => {
  const where = placeFrom([
    { longText: 'Matola', types: ['locality'] },
    { longText: 'Maputo', types: ['administrative_area_level_1'] },
    { longText: 'Moçambique', types: ['country'] },
  ]);
  assert.deepEqual(where, {
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
  });
});

test('an address with no locality falls back rather than inventing one', () => {
  const where = placeFrom([
    { longText: 'Boane', types: ['administrative_area_level_2'] },
    { longText: 'Maputo', types: ['administrative_area_level_1'] },
  ]);
  assert.equal(where.city, 'Boane');
  assert.equal(where.country, null);
});

test('a trade is read from the Places type or from the name', () => {
  assert.equal(industryFromPlace('barber_shop', [], 'Casa X'), 'barbershop');
  assert.equal(industryFromPlace('hair_care', ['hair_care'], 'Salão Beleza'), 'salon');
  // Typed only as a generic establishment, but the name says what it is — and
  // that is precisely the lead worth having.
  assert.equal(
    industryFromPlace('establishment', ['establishment'], 'Barbearia do Zé'),
    'barbershop',
  );
  assert.equal(industryFromPlace('bank', ['bank'], 'Banco X'), null);
});

/* ------------------------------------------------------------------ search */

test('a search maps a listing into a company with its rating and reviews', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: { places: [place()] },
  }));

  const results = await provider(fetchImpl).searchBusinesses(CRITERIA);

  assert.equal(results.length, 1);
  const company = results[0]!.company;
  assert.equal(company.name, 'Barbearia do Zé');
  assert.equal(company.industry, 'barbershop');
  assert.equal(company.rating, 4.6);
  assert.equal(company.review_count, 87);
  assert.equal(company.business_status, 'OPERATIONAL');
  assert.equal(company.city, 'Maputo');
  assert.equal(company.source, 'places');
  assert.equal(company.source_reference, 'places/ChIJxxxx');

  // The key travels in a header, never in the URL: a key in a query string is
  // in every access log between here and Google.
  assert.ok(!calls[0]!.url.includes('secret-key'));
  const headers = calls[0]!.init.headers as Record<string, string>;
  assert.equal(headers['X-Goog-Api-Key'], 'secret-key');
});

test('the cheap mask is what a search sends, and it asks for no contact details', () => {
  // The mask is the price. Phone and website belong to the dear call, and a
  // test that pins this is the thing that catches a field quietly added to
  // the search and silently moving every campaign to a higher tier.
  assert.ok(SEARCH_FIELD_MASK.includes('places.rating'));
  assert.ok(SEARCH_FIELD_MASK.includes('places.userRatingCount'));
  assert.ok(!SEARCH_FIELD_MASK.includes('nationalPhoneNumber'));
  assert.ok(!SEARCH_FIELD_MASK.includes('websiteUri'));
  assert.ok(!SEARCH_FIELD_MASK.includes('regularOpeningHours'));

  assert.ok(DETAIL_FIELD_MASK.includes('websiteUri'));
  assert.ok(DETAIL_FIELD_MASK.includes('internationalPhoneNumber'));
});

test('a search leaves phone, website and the listing extras unasked', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 200, body: { places: [place()] } }));
  const company = (await provider(fetchImpl).searchBusinesses(CRITERIA))[0]!.company;

  assert.equal(company.phone, null);
  assert.equal(company.website, null);
  // Null, not false: nobody looked, which is a different answer from "none".
  assert.equal(company.has_opening_hours, null);
  assert.equal(company.has_photos, null);
});

test('a listing with no rating yet is null, not zero', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: { places: [place({ rating: undefined, userRatingCount: undefined })] },
  }));
  const company = (await provider(fetchImpl).searchBusinesses(CRITERIA))[0]!.company;

  assert.equal(company.rating, null);
  assert.equal(company.review_count, null);
});

test('the page token goes out as a cursor and comes back on every result', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: { places: [place()], nextPageToken: 'token-2' },
  }));

  const first = await provider(fetchImpl).searchBusinesses(CRITERIA);
  assert.equal(first[0]!.cursor, 'token-2');

  await provider(fetchImpl).searchBusinesses({ ...CRITERIA, cursor: 'token-2' });
  const body = JSON.parse(String(calls[1]!.init.body)) as Record<string, unknown>;
  assert.equal(body.pageToken, 'token-2');
});

test('a page is never asked for more than twenty results', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: { places: [] } }));
  await provider(fetchImpl).searchBusinesses({ ...CRITERIA, limit: 500 });

  const body = JSON.parse(String(calls[0]!.init.body)) as Record<string, unknown>;
  assert.equal(body.pageSize, MAX_PAGE_SIZE);
});

test('one malformed listing costs that listing, not the page', async () => {
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
  assert.equal(results.length, 1);
  assert.equal(results[0]!.company.name, 'Barbearia do Zé');
});

test('a rating outside the 0-5 scale is refused rather than scored', async () => {
  // `assertCompanySane` throws, `toCompany` drops the listing. A provider
  // whose scale is not the assumed one must not quietly hand every lead five
  // points for the wrong reason.
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: { places: [place({ rating: 9.2 })] },
  }));

  assert.deepEqual(await provider(fetchImpl).searchBusinesses(CRITERIA), []);
});

/* ------------------------------------------------------------------ detail */

test('the detail call returns the contact fields and the listing extras', async () => {
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

  assert.equal(detail.phone, '+258 84 000 0101');
  assert.equal(detail.website, 'https://barbearia.test');
  assert.equal(detail.hasOpeningHours, true);
  assert.equal(detail.hasPhotos, true);
  assert.ok(calls[0]!.url.includes('places%2FChIJxxxx'));
});

test('a detail response missing a requested field answers "none", not "unknown"', async () => {
  // The field was asked for, so its absence is the answer. This is the one
  // place in the module where false beats null, and it is because the mask
  // makes the question explicit.
  const { fetchImpl } = mockFetch(() => ({ status: 200, body: { id: 'places/x' } }));
  const detail = await provider(fetchImpl).fetchListingDetail({ reference: 'places/x' });

  assert.equal(detail.hasOpeningHours, false);
  assert.equal(detail.hasPhotos, false);
  assert.equal(detail.phone, null);
  assert.equal(detail.website, null);
});

test('the international number wins over the national one', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: {
      id: 'places/x',
      internationalPhoneNumber: '+258840000101',
      nationalPhoneNumber: '84 000 0101',
    },
  }));
  const detail = await provider(fetchImpl).fetchListingDetail({ reference: 'places/x' });
  assert.equal(detail.phone, '+258840000101');
});

test('an empty reference is refused before a request is made', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: {} }));
  await assert.rejects(
    () => provider(fetchImpl).fetchListingDetail({ reference: '  ' }),
    (error: unknown) =>
      error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
  assert.equal(calls.length, 0);
});

/* ------------------------------------------------------------------ errors */

test('an unset key is NOT_CONFIGURED and costs no request', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: {} }));
  await assert.rejects(
    () => unconfigured(fetchImpl).searchBusinesses(CRITERIA),
    (error: unknown) =>
      error instanceof ProviderError && error.code === 'NOT_CONFIGURED',
  );
  assert.equal(calls.length, 0);
  assert.equal(unconfigured(fetchImpl).isConfigured(), false);
});

test('HTTP statuses map to the code the chain acts on', () => {
  assert.equal(statusToCode(401, null), 'NOT_CONFIGURED');
  assert.equal(statusToCode(403, null), 'NOT_CONFIGURED');
  assert.equal(statusToCode(429, null), 'RATE_LIMITED');
  assert.equal(statusToCode(500, null), 'UNAVAILABLE');
  assert.equal(statusToCode(400, null), 'INVALID_SCHEMA');
});

test('a disabled billing account is not a credentials problem', () => {
  // 403 with a billing message is not something re-pasting a key fixes, and
  // telling an operator to check their key would send them to the wrong screen.
  assert.equal(
    statusToCode(403, { error: { message: 'Billing has not been enabled' } }),
    'INSUFFICIENT_CREDITS',
  );
  assert.equal(
    statusToCode(429, { error: { status: 'RESOURCE_EXHAUSTED' } }),
    'INSUFFICIENT_CREDITS',
  );
});

test('a non-object body is a schema error, not an empty result', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 200, body: 'not json' }));
  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses(CRITERIA),
    (error: unknown) =>
      error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
});

/* -------------------------------------------------------------------- cost */

test('the reported cost distinguishes the cheap call from the dear one', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 200, body: { places: [place()] } }));
  const places = provider(fetchImpl);

  await places.searchBusinesses(CRITERIA);
  assert.equal(places.lastCostUsd, 0.02);
  assert.equal(places.estimatedCostUsd(), 0.02);

  const detail = mockFetch(() => ({ status: 200, body: { id: 'places/x' } }));
  const second = provider(detail.fetchImpl);
  await second.fetchListingDetail({ reference: 'places/x' });
  assert.equal(second.lastCostUsd, 0.03);
  assert.equal(second.estimatedCostUsd(), 0.03);
});

test('a refused call reports no cost', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 429, body: {} }));
  const places = provider(fetchImpl);

  await assert.rejects(() => places.searchBusinesses(CRITERIA));
  assert.equal(places.lastCostUsd, null);
});
