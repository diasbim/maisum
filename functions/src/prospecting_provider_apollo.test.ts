import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ApolloProvider,
  confidenceFromMatch,
  emailStatusFrom,
  employeeRangeParam,
  industryFrom,
  seniorityFrom,
  statusToCode,
} from './prospecting_provider_apollo.js';
import { ProviderError } from './prospecting_providers.js';

/**
 * The adapter against a mocked `fetch`.
 *
 * Every response shape here is the one the official reference documents, and
 * the field names are the ones it names — `organizations`, `primary_domain`,
 * `last_name_obfuscated`, `match_confidence`. A test written against a shape
 * this adapter invented would pass forever and prove nothing.
 */

type MockCall = { url: string; init: RequestInit };

function mockFetch(
  responder: (call: MockCall) => { status: number; body: unknown } | Promise<never>,
): { fetchImpl: typeof fetch; calls: MockCall[] } {
  const calls: MockCall[] = [];
  const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = { url: String(input), init: init ?? {} };
    calls.push(call);
    const result = await responder(call);
    return {
      ok: result.status >= 200 && result.status < 300,
      status: result.status,
      json: async () => result.body,
    } as Response;
  }) as unknown as typeof fetch;

  return { fetchImpl, calls };
}

function provider(fetchImpl: typeof fetch, apiKey = 'secret-key') {
  return new ApolloProvider({ apiKey, fetchImpl });
}

const SEARCH_CRITERIA = {
  industries: ['barbershop'],
  city: 'Maputo',
  province: null,
  country: 'Moçambique',
  employeeMin: 3,
  employeeMax: 20,
  limit: 25,
  cursor: null,
} as const;

/* ---------------------------------------------------------------- success */

test('an organization search maps a documented response into the internal model', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: {
      pagination: { page: 1, per_page: 25, total_entries: 2, total_pages: 1 },
      organizations: [
        {
          id: 'org_1',
          name: 'Barbearia Exemplo',
          website_url: 'https://barbearia-exemplo.test',
          primary_domain: 'barbearia-exemplo.test',
          linkedin_url: 'https://linkedin.com/company/barbearia-exemplo',
          facebook_url: 'https://facebook.com/barbeariaexemplo',
          sanitized_phone: '+258841234567',
          estimated_num_employees: 6,
          industry: 'Barbearia',
          city: 'Maputo',
          country: 'Mozambique',
        },
      ],
    },
  }));

  const results = await provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA });

  assert.equal(results.length, 1);
  const company = results[0].company;
  assert.equal(company.name, 'Barbearia Exemplo');
  assert.equal(company.domain, 'barbearia-exemplo.test');
  assert.equal(company.provider_org_id, 'org_1');
  assert.equal(company.source, 'apollo');
  assert.equal(company.employee_count, 6);
  // Mapped onto the product's own taxonomy, not Apollo's string.
  assert.equal(company.industry, 'barbershop');
  assert.equal(company.industry_raw, 'Barbearia');

  // The request was the documented one.
  assert.equal(calls[0].url, 'https://api.apollo.io/api/v1/mixed_companies/search');
  assert.equal(calls[0].init.method, 'POST');
  const body = JSON.parse(String(calls[0].init.body));
  assert.deepEqual(body.organization_locations, ['Maputo, Moçambique']);
  assert.deepEqual(body.organization_num_employees_ranges, ['3,20']);
  assert.ok(body.q_organization_keyword_tags.includes('barbearia'));
});

test('the API key travels in the header and never in the URL', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: { organizations: [{ id: 'o', name: 'X' }], pagination: { total_pages: 1 } },
  }));

  await provider(fetchImpl, 'super-secret').searchBusinesses({ ...SEARCH_CRITERIA });

  const headers = calls[0].init.headers as Record<string, string>;
  assert.equal(headers['x-api-key'], 'super-secret');
  assert.equal(calls[0].url.includes('super-secret'), false);
});

test('a provider error never carries the key in its message', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 500, body: { error: 'boom' } }));

  await assert.rejects(
    () => provider(fetchImpl, 'super-secret').searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => {
      assert.ok(error instanceof ProviderError);
      assert.equal(error.message.includes('super-secret'), false);
      assert.equal((error.detail ?? '').includes('super-secret'), false);
      return true;
    },
  );
});

/* ------------------------------------------------------------ pagination */

test('the cursor is the next page number, and is absent on the last page', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: {
      pagination: { page: 1, total_pages: 3 },
      organizations: [{ id: 'o1', name: 'A' }, { id: 'o2', name: 'B' }],
    },
  }));

  const results = await provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA });
  assert.equal(results[0].cursor, null);
  assert.equal(results[results.length - 1].cursor, '2');

  const { fetchImpl: lastPage } = mockFetch(() => ({
    status: 200,
    body: {
      pagination: { page: 3, total_pages: 3 },
      organizations: [{ id: 'o3', name: 'C' }],
    },
  }));
  const final = await provider(lastPage).searchBusinesses({ ...SEARCH_CRITERIA, cursor: '3' });
  assert.equal(final[0].cursor, null);
});

/* --------------------------------------------------------------- failures */

test('a timeout is a TIMEOUT, not a generic outage', async () => {
  const { fetchImpl } = mockFetch(() => {
    const error = new Error('aborted');
    error.name = 'AbortError';
    return Promise.reject(error);
  });

  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'TIMEOUT',
  );
});

test('a 429 is a rate limit', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 429, body: {} }));
  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'RATE_LIMITED',
  );
});

test('exhausted credits are their own code, whether by status or by message', async () => {
  const { fetchImpl: byStatus } = mockFetch(() => ({ status: 402, body: {} }));
  await assert.rejects(
    () => provider(byStatus).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'INSUFFICIENT_CREDITS',
  );

  const { fetchImpl: byMessage } = mockFetch(() => ({
    status: 422,
    body: { error: 'You have insufficient credits remaining' },
  }));
  await assert.rejects(
    () => provider(byMessage).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'INSUFFICIENT_CREDITS',
  );
});

test('a rejected key is NOT_CONFIGURED, so the chain moves on rather than retrying', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 401, body: {} }));
  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NOT_CONFIGURED',
  );
});

test('a response that is not the documented shape is INVALID_SCHEMA', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: { organizations: 'not an array' },
  }));
  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
});

test('a body that is not JSON at all is INVALID_SCHEMA', async () => {
  const fetchImpl = (async () =>
    ({
      ok: true,
      status: 200,
      json: async () => {
        throw new SyntaxError('unexpected token');
      },
    }) as unknown as Response) as unknown as typeof fetch;

  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
});

test('an empty result set is NO_RESULT, which is an answer rather than a failure', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: { organizations: [], pagination: { total_pages: 0 } },
  }));
  await assert.rejects(
    () => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NO_RESULT',
  );
});

test('one malformed row costs that row, not the page', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: {
      pagination: { total_pages: 1 },
      organizations: [
        { id: 'o1', name: 'Barbearia Boa' },
        { id: 'o2' },
        null,
        { id: 'o3', name: 'Salão Bom', estimated_num_employees: 'not a number' },
      ],
    },
  }));

  const results = await provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA });
  assert.equal(results.length, 2);
  assert.deepEqual(
    results.map((entry) => entry.company.name),
    ['Barbearia Boa', 'Salão Bom'],
  );
  assert.equal(results[1].company.employee_count, null);
});

test('no key configured means the provider is skipped, not called', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: {} }));
  const unset = new ApolloProvider({ apiKey: undefined, fetchImpl });

  assert.equal(unset.isConfigured(), false);
  await assert.rejects(
    () => unset.searchBusinesses({ ...SEARCH_CRITERIA }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NOT_CONFIGURED',
  );
  assert.equal(calls.length, 0);
});

/* ----------------------------------------------------------- people search */

test('people search returns no contact details, whatever the flags say', async () => {
  // The documented response carries `has_email` and `last_name_obfuscated`.
  // A flag is not an address, and an obfuscated name is not a name.
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: {
      total_entries: 1,
      people: [
        {
          id: 'per_1',
          first_name: 'Arlindo',
          last_name_obfuscated: 'S****a',
          title: 'Proprietário',
          seniority: 'owner',
          has_email: true,
          has_direct_phone: true,
          linkedin_url: 'https://linkedin.com/in/arlindo',
        },
      ],
    },
  }));

  const found = await provider(fetchImpl).findDecisionMakers({
    companyName: 'Barbearia Exemplo',
    domain: 'barbearia-exemplo.test',
    providerOrgId: 'org_1',
    titles: ['owner'],
    limit: 5,
  });

  assert.equal(found.length, 1);
  const person = found[0].person;
  assert.equal(person.first_name, 'Arlindo');
  assert.equal(person.last_name, null, 'an obfuscated last name is not a last name');
  assert.equal(person.email, null, 'this endpoint returns no email');
  assert.equal(person.email_status, 'UNKNOWN');
  assert.equal(person.phone, null, 'this endpoint returns no phone');
  assert.equal(person.seniority, 'OWNER');
  assert.equal(person.provider_person_id, 'per_1');
});

test('people search asks only for the seniorities that decide', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: { people: [{ id: 'p', first_name: 'A', title: 'Owner' }] },
  }));

  await provider(fetchImpl).findDecisionMakers({
    companyName: 'X',
    domain: 'x.test',
    providerOrgId: 'org_1',
    titles: ['owner'],
    limit: 5,
  });

  assert.equal(calls[0].url, 'https://api.apollo.io/api/v1/mixed_people/api_search');
  const body = JSON.parse(String(calls[0].init.body));
  assert.deepEqual(body.organization_ids, ['org_1']);
  assert.equal(body.person_seniorities.includes('owner'), true);
  assert.equal(body.person_seniorities.includes('intern'), false);
});

/* ------------------------------------------------------- person enrichment */

test('person enrichment maps the match confidence and never asks for a phone', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: {
      person: {
        id: 'per_1',
        first_name: 'Arlindo',
        last_name: 'Exemplo',
        title: 'Proprietário',
        email: 'arlindo@barbearia-exemplo.test',
        email_status: 'verified',
        match_confidence: 'high',
      },
    },
  }));

  const result = await provider(fetchImpl).enrichPerson({
    providerPersonId: 'per_1',
    firstName: 'Arlindo',
    lastName: null,
    companyName: 'Barbearia Exemplo',
    domain: 'barbearia-exemplo.test',
    linkedinUrl: null,
  });

  assert.equal(result.person.email, 'arlindo@barbearia-exemplo.test');
  assert.equal(result.person.email_status, 'VERIFIED');
  assert.equal(result.person.confidence_score, 0.9);
  assert.equal(result.person.seniority, 'OWNER');
  // Phone reveal needs a webhook this module does not expose. Asking for it
  // would spend credits on a result with nowhere to arrive.
  const body = JSON.parse(String(calls[0].init.body));
  assert.equal('reveal_phone_number' in body, false);
  assert.equal(body.reveal_personal_emails, false);
  assert.equal(result.person.phone, undefined);
});

test('a match confidence of none is no match, not a low-confidence match', async () => {
  const { fetchImpl } = mockFetch(() => ({
    status: 200,
    body: { person: { id: 'p', match_confidence: 'none' } },
  }));

  await assert.rejects(
    () =>
      provider(fetchImpl).enrichPerson({
        providerPersonId: 'p',
        firstName: null,
        lastName: null,
        companyName: null,
        domain: null,
        linkedinUrl: null,
      }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NO_RESULT',
  );
});

/* ------------------------------------------------------ company enrichment */

test('company enrichment identifies by the strongest identifier available', async () => {
  const { fetchImpl, calls } = mockFetch(() => ({
    status: 200,
    body: {
      organization: {
        id: 'org_1',
        name: 'Barbearia Exemplo',
        primary_domain: 'barbearia-exemplo.test',
        estimated_num_employees: 8,
        industry: 'Barbearia',
      },
    },
  }));

  const result = await provider(fetchImpl).enrichCompany({
    name: 'Barbearia Exemplo',
    domain: 'barbearia-exemplo.test',
    website: null,
    linkedinUrl: null,
    providerOrgId: null,
  });

  assert.ok(calls[0].url.includes('/organizations/enrich'));
  assert.ok(calls[0].url.includes('domain=barbearia-exemplo.test'));
  assert.equal(calls[0].init.method, 'GET');
  assert.equal(result.company.employee_count, 8);
  assert.ok(result.fieldsDiscovered.includes('employee_count'));
});

test('an enrichment that filled nothing is NO_RESULT rather than an empty success', async () => {
  const { fetchImpl } = mockFetch(() => ({ status: 200, body: { organization: {} } }));
  await assert.rejects(
    () =>
      provider(fetchImpl).enrichCompany({
        name: 'X',
        domain: 'x.test',
        website: null,
        linkedinUrl: null,
        providerOrgId: null,
      }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NO_RESULT',
  );
});

/* ---------------------------------------------------------------- mapping */

test('the employee range is written the way the documentation spells it', () => {
  assert.equal(employeeRangeParam(3, 20), '3,20');
  assert.equal(employeeRangeParam(null, null), null);
  // No open-ended form is documented, so an unbounded top is written against a
  // ceiling rather than omitted — omitting it would widen the search silently.
  assert.equal(employeeRangeParam(51, null), '51,10000');
  assert.equal(employeeRangeParam(null, 5), '1,5');
});

test('an unrecognised industry maps to null, and the raw string is kept', () => {
  assert.equal(industryFrom('Barbearia', null, 'X'), 'barbershop');
  assert.equal(industryFrom('Hair Salon', null, 'X'), 'salon');
  assert.equal(industryFrom(null, ['gym', 'fitness'], 'X'), 'gym');
  // The name is the last resort, and it works: Apollo has no code for these.
  assert.equal(industryFrom(null, null, 'Lavagem Auto Exemplo'), 'car_wash');
  assert.equal(industryFrom('Mining', null, 'Minas X'), null);
});

test('an unknown email status is never read as verified', () => {
  assert.equal(emailStatusFrom('verified', true), 'VERIFIED');
  assert.equal(emailStatusFrom('guessed', true), 'GUESSED');
  assert.equal(emailStatusFrom('unavailable', true), 'INVALID');
  assert.equal(emailStatusFrom('something new', true), 'UNVERIFIED');
  assert.equal(emailStatusFrom(undefined, true), 'UNVERIFIED');
  assert.equal(emailStatusFrom('verified', false), 'UNKNOWN');
});

test('the match confidence is a rename of the category, not an estimate', () => {
  assert.equal(confidenceFromMatch('high'), 0.9);
  assert.equal(confidenceFromMatch('medium'), 0.6);
  assert.equal(confidenceFromMatch('low'), 0.3);
  assert.equal(confidenceFromMatch('none'), null);
  assert.equal(confidenceFromMatch(0.9), null);
});

test("Apollo's seniority vocabulary is translated, not cast", () => {
  assert.equal(seniorityFrom('c_suite', null), 'C_LEVEL');
  assert.equal(seniorityFrom('head', null), 'DIRECTOR');
  assert.equal(seniorityFrom('vp', null), 'DIRECTOR');
  assert.equal(seniorityFrom('intern', null), 'STAFF');
  // An unrecognised value falls through to the title, and an unrecognised
  // title falls through to UNKNOWN — never to STAFF.
  assert.equal(seniorityFrom('galactic_overlord', 'Gerente'), 'MANAGER');
  assert.equal(seniorityFrom(null, null), 'UNKNOWN');
});

test('status codes map to what the caller should do about them', () => {
  assert.equal(statusToCode(401, {}), 'NOT_CONFIGURED');
  assert.equal(statusToCode(403, {}), 'NOT_CONFIGURED');
  assert.equal(statusToCode(429, {}), 'RATE_LIMITED');
  assert.equal(statusToCode(402, {}), 'INSUFFICIENT_CREDITS');
  assert.equal(statusToCode(500, {}), 'UNAVAILABLE');
  assert.equal(statusToCode(503, {}), 'UNAVAILABLE');
  assert.equal(statusToCode(422, {}), 'INVALID_SCHEMA');
  assert.equal(statusToCode(422, { error: 'rate limit exceeded' }), 'RATE_LIMITED');
});
