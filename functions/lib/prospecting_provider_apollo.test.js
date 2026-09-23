"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_provider_apollo_js_1 = require("./prospecting_provider_apollo.js");
const prospecting_providers_js_1 = require("./prospecting_providers.js");
function mockFetch(responder) {
    const calls = [];
    const fetchImpl = (async (input, init) => {
        const call = { url: String(input), init: init ?? {} };
        calls.push(call);
        const result = await responder(call);
        return {
            ok: result.status >= 200 && result.status < 300,
            status: result.status,
            json: async () => result.body,
        };
    });
    return { fetchImpl, calls };
}
function provider(fetchImpl, apiKey = 'secret-key') {
    return new prospecting_provider_apollo_js_1.ApolloProvider({ apiKey, fetchImpl });
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
};
/* ---------------------------------------------------------------- success */
(0, node_test_1.default)('an organization search maps a documented response into the internal model', async () => {
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
    strict_1.default.equal(results.length, 1);
    const company = results[0].company;
    strict_1.default.equal(company.name, 'Barbearia Exemplo');
    strict_1.default.equal(company.domain, 'barbearia-exemplo.test');
    strict_1.default.equal(company.provider_org_id, 'org_1');
    strict_1.default.equal(company.source, 'apollo');
    strict_1.default.equal(company.employee_count, 6);
    // Mapped onto the product's own taxonomy, not Apollo's string.
    strict_1.default.equal(company.industry, 'barbershop');
    strict_1.default.equal(company.industry_raw, 'Barbearia');
    // The request was the documented one.
    strict_1.default.equal(calls[0].url, 'https://api.apollo.io/api/v1/mixed_companies/search');
    strict_1.default.equal(calls[0].init.method, 'POST');
    const body = JSON.parse(String(calls[0].init.body));
    strict_1.default.deepEqual(body.organization_locations, ['Maputo, Moçambique']);
    strict_1.default.deepEqual(body.organization_num_employees_ranges, ['3,20']);
    strict_1.default.ok(body.q_organization_keyword_tags.includes('barbearia'));
});
(0, node_test_1.default)('the API key travels in the header and never in the URL', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({
        status: 200,
        body: { organizations: [{ id: 'o', name: 'X' }], pagination: { total_pages: 1 } },
    }));
    await provider(fetchImpl, 'super-secret').searchBusinesses({ ...SEARCH_CRITERIA });
    const headers = calls[0].init.headers;
    strict_1.default.equal(headers['x-api-key'], 'super-secret');
    strict_1.default.equal(calls[0].url.includes('super-secret'), false);
});
(0, node_test_1.default)('a provider error never carries the key in its message', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 500, body: { error: 'boom' } }));
    await strict_1.default.rejects(() => provider(fetchImpl, 'super-secret').searchBusinesses({ ...SEARCH_CRITERIA }), (error) => {
        strict_1.default.ok(error instanceof prospecting_providers_js_1.ProviderError);
        strict_1.default.equal(error.message.includes('super-secret'), false);
        strict_1.default.equal((error.detail ?? '').includes('super-secret'), false);
        return true;
    });
});
/* ------------------------------------------------------------ pagination */
(0, node_test_1.default)('the cursor is the next page number, and is absent on the last page', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: {
            pagination: { page: 1, total_pages: 3 },
            organizations: [{ id: 'o1', name: 'A' }, { id: 'o2', name: 'B' }],
        },
    }));
    const results = await provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA });
    strict_1.default.equal(results[0].cursor, null);
    strict_1.default.equal(results[results.length - 1].cursor, '2');
    const { fetchImpl: lastPage } = mockFetch(() => ({
        status: 200,
        body: {
            pagination: { page: 3, total_pages: 3 },
            organizations: [{ id: 'o3', name: 'C' }],
        },
    }));
    const final = await provider(lastPage).searchBusinesses({ ...SEARCH_CRITERIA, cursor: '3' });
    strict_1.default.equal(final[0].cursor, null);
});
/* --------------------------------------------------------------- failures */
(0, node_test_1.default)('a timeout is a TIMEOUT, not a generic outage', async () => {
    const { fetchImpl } = mockFetch(() => {
        const error = new Error('aborted');
        error.name = 'AbortError';
        return Promise.reject(error);
    });
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'TIMEOUT');
});
(0, node_test_1.default)('a 429 is a rate limit', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 429, body: {} }));
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'RATE_LIMITED');
});
(0, node_test_1.default)('exhausted credits are their own code, whether by status or by message', async () => {
    const { fetchImpl: byStatus } = mockFetch(() => ({ status: 402, body: {} }));
    await strict_1.default.rejects(() => provider(byStatus).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INSUFFICIENT_CREDITS');
    const { fetchImpl: byMessage } = mockFetch(() => ({
        status: 422,
        body: { error: 'You have insufficient credits remaining' },
    }));
    await strict_1.default.rejects(() => provider(byMessage).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INSUFFICIENT_CREDITS');
});
(0, node_test_1.default)('a rejected key is NOT_CONFIGURED, so the chain moves on rather than retrying', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 401, body: {} }));
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NOT_CONFIGURED');
});
(0, node_test_1.default)('a response that is not the documented shape is INVALID_SCHEMA', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: { organizations: 'not an array' },
    }));
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
});
(0, node_test_1.default)('a body that is not JSON at all is INVALID_SCHEMA', async () => {
    const fetchImpl = (async () => ({
        ok: true,
        status: 200,
        json: async () => {
            throw new SyntaxError('unexpected token');
        },
    }));
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
});
(0, node_test_1.default)('an empty result set is NO_RESULT, which is an answer rather than a failure', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: { organizations: [], pagination: { total_pages: 0 } },
    }));
    await strict_1.default.rejects(() => provider(fetchImpl).searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NO_RESULT');
});
(0, node_test_1.default)('one malformed row costs that row, not the page', async () => {
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
    strict_1.default.equal(results.length, 2);
    strict_1.default.deepEqual(results.map((entry) => entry.company.name), ['Barbearia Boa', 'Salão Bom']);
    strict_1.default.equal(results[1].company.employee_count, null);
});
(0, node_test_1.default)('no key configured means the provider is skipped, not called', async () => {
    const { fetchImpl, calls } = mockFetch(() => ({ status: 200, body: {} }));
    const unset = new prospecting_provider_apollo_js_1.ApolloProvider({ apiKey: undefined, fetchImpl });
    strict_1.default.equal(unset.isConfigured(), false);
    await strict_1.default.rejects(() => unset.searchBusinesses({ ...SEARCH_CRITERIA }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NOT_CONFIGURED');
    strict_1.default.equal(calls.length, 0);
});
/* ----------------------------------------------------------- people search */
(0, node_test_1.default)('people search returns no contact details, whatever the flags say', async () => {
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
    strict_1.default.equal(found.length, 1);
    const person = found[0].person;
    strict_1.default.equal(person.first_name, 'Arlindo');
    strict_1.default.equal(person.last_name, null, 'an obfuscated last name is not a last name');
    strict_1.default.equal(person.email, null, 'this endpoint returns no email');
    strict_1.default.equal(person.email_status, 'UNKNOWN');
    strict_1.default.equal(person.phone, null, 'this endpoint returns no phone');
    strict_1.default.equal(person.seniority, 'OWNER');
    strict_1.default.equal(person.provider_person_id, 'per_1');
});
(0, node_test_1.default)('people search asks only for the seniorities that decide', async () => {
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
    strict_1.default.equal(calls[0].url, 'https://api.apollo.io/api/v1/mixed_people/api_search');
    const body = JSON.parse(String(calls[0].init.body));
    strict_1.default.deepEqual(body.organization_ids, ['org_1']);
    strict_1.default.equal(body.person_seniorities.includes('owner'), true);
    strict_1.default.equal(body.person_seniorities.includes('intern'), false);
});
/* ------------------------------------------------------- person enrichment */
(0, node_test_1.default)('person enrichment maps the match confidence and never asks for a phone', async () => {
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
    strict_1.default.equal(result.person.email, 'arlindo@barbearia-exemplo.test');
    strict_1.default.equal(result.person.email_status, 'VERIFIED');
    strict_1.default.equal(result.person.confidence_score, 0.9);
    strict_1.default.equal(result.person.seniority, 'OWNER');
    // Phone reveal needs a webhook this module does not expose. Asking for it
    // would spend credits on a result with nowhere to arrive.
    const body = JSON.parse(String(calls[0].init.body));
    strict_1.default.equal('reveal_phone_number' in body, false);
    strict_1.default.equal(body.reveal_personal_emails, false);
    strict_1.default.equal(result.person.phone, undefined);
});
(0, node_test_1.default)('a match confidence of none is no match, not a low-confidence match', async () => {
    const { fetchImpl } = mockFetch(() => ({
        status: 200,
        body: { person: { id: 'p', match_confidence: 'none' } },
    }));
    await strict_1.default.rejects(() => provider(fetchImpl).enrichPerson({
        providerPersonId: 'p',
        firstName: null,
        lastName: null,
        companyName: null,
        domain: null,
        linkedinUrl: null,
    }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NO_RESULT');
});
/* ------------------------------------------------------ company enrichment */
(0, node_test_1.default)('company enrichment identifies by the strongest identifier available', async () => {
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
    strict_1.default.ok(calls[0].url.includes('/organizations/enrich'));
    strict_1.default.ok(calls[0].url.includes('domain=barbearia-exemplo.test'));
    strict_1.default.equal(calls[0].init.method, 'GET');
    strict_1.default.equal(result.company.employee_count, 8);
    strict_1.default.ok(result.fieldsDiscovered.includes('employee_count'));
});
(0, node_test_1.default)('an enrichment that filled nothing is NO_RESULT rather than an empty success', async () => {
    const { fetchImpl } = mockFetch(() => ({ status: 200, body: { organization: {} } }));
    await strict_1.default.rejects(() => provider(fetchImpl).enrichCompany({
        name: 'X',
        domain: 'x.test',
        website: null,
        linkedinUrl: null,
        providerOrgId: null,
    }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NO_RESULT');
});
/* ---------------------------------------------------------------- mapping */
(0, node_test_1.default)('the employee range is written the way the documentation spells it', () => {
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.employeeRangeParam)(3, 20), '3,20');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.employeeRangeParam)(null, null), null);
    // No open-ended form is documented, so an unbounded top is written against a
    // ceiling rather than omitted — omitting it would widen the search silently.
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.employeeRangeParam)(51, null), '51,10000');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.employeeRangeParam)(null, 5), '1,5');
});
(0, node_test_1.default)('an unrecognised industry maps to null, and the raw string is kept', () => {
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.industryFrom)('Barbearia', null, 'X'), 'barbershop');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.industryFrom)('Hair Salon', null, 'X'), 'salon');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.industryFrom)(null, ['gym', 'fitness'], 'X'), 'gym');
    // The name is the last resort, and it works: Apollo has no code for these.
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.industryFrom)(null, null, 'Lavagem Auto Exemplo'), 'car_wash');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.industryFrom)('Mining', null, 'Minas X'), null);
});
(0, node_test_1.default)('an unknown email status is never read as verified', () => {
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.emailStatusFrom)('verified', true), 'VERIFIED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.emailStatusFrom)('guessed', true), 'GUESSED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.emailStatusFrom)('unavailable', true), 'INVALID');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.emailStatusFrom)('something new', true), 'UNVERIFIED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.emailStatusFrom)(undefined, true), 'UNVERIFIED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.emailStatusFrom)('verified', false), 'UNKNOWN');
});
(0, node_test_1.default)('the match confidence is a rename of the category, not an estimate', () => {
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.confidenceFromMatch)('high'), 0.9);
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.confidenceFromMatch)('medium'), 0.6);
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.confidenceFromMatch)('low'), 0.3);
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.confidenceFromMatch)('none'), null);
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.confidenceFromMatch)(0.9), null);
});
(0, node_test_1.default)("Apollo's seniority vocabulary is translated, not cast", () => {
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.seniorityFrom)('c_suite', null), 'C_LEVEL');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.seniorityFrom)('head', null), 'DIRECTOR');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.seniorityFrom)('vp', null), 'DIRECTOR');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.seniorityFrom)('intern', null), 'STAFF');
    // An unrecognised value falls through to the title, and an unrecognised
    // title falls through to UNKNOWN — never to STAFF.
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.seniorityFrom)('galactic_overlord', 'Gerente'), 'MANAGER');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.seniorityFrom)(null, null), 'UNKNOWN');
});
(0, node_test_1.default)('status codes map to what the caller should do about them', () => {
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(401, {}), 'NOT_CONFIGURED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(403, {}), 'NOT_CONFIGURED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(429, {}), 'RATE_LIMITED');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(402, {}), 'INSUFFICIENT_CREDITS');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(500, {}), 'UNAVAILABLE');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(503, {}), 'UNAVAILABLE');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(422, {}), 'INVALID_SCHEMA');
    strict_1.default.equal((0, prospecting_provider_apollo_js_1.statusToCode)(422, { error: 'rate limit exceeded' }), 'RATE_LIMITED');
});
