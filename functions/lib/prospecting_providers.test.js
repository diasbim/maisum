"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_providers_js_1 = require("./prospecting_providers.js");
const prospecting_provider_fixtures_js_1 = require("./prospecting_provider_fixtures.js");
const prospecting_normalization_js_1 = require("./prospecting_normalization.js");
function stub(key, configured) {
    return { key, calls: 0, isConfigured: () => configured };
}
(0, node_test_1.default)('the first configured provider that answers ends the chain', async () => {
    const first = stub('a', true);
    const second = stub('b', true);
    const outcome = await (0, prospecting_providers_js_1.runChain)([first, second], async (provider) => {
        provider.calls++;
        return provider.key;
    });
    strict_1.default.equal(outcome.ok, true);
    strict_1.default.equal(outcome.ok === true && outcome.value, 'a');
    strict_1.default.equal(outcome.ok === true && outcome.partial, false);
    strict_1.default.equal(second.calls, 0);
});
(0, node_test_1.default)('an unconfigured provider is skipped without being called or charged', async () => {
    const first = stub('a', false);
    const second = stub('b', true);
    const outcome = await (0, prospecting_providers_js_1.runChain)([first, second], async (provider) => {
        provider.calls++;
        return provider.key;
    });
    strict_1.default.equal(outcome.ok === true && outcome.value, 'b');
    strict_1.default.equal(first.calls, 0);
    // Nothing was spent, so nothing is recorded for it.
    strict_1.default.equal(outcome.attempts.length, 1);
});
(0, node_test_1.default)('a failure falls through to the next provider and the result is marked partial', async () => {
    const first = stub('a', true);
    const second = stub('b', true);
    const outcome = await (0, prospecting_providers_js_1.runChain)([first, second], async (provider) => {
        if (provider.key === 'a') {
            throw new prospecting_providers_js_1.ProviderError({
                code: 'TIMEOUT',
                provider: 'a',
                operation: 'ENRICH_COMPANY',
            });
        }
        return provider.key;
    });
    strict_1.default.equal(outcome.ok === true && outcome.value, 'b');
    strict_1.default.equal(outcome.ok === true && outcome.partial, true);
    strict_1.default.equal(outcome.attempts.length, 2);
    strict_1.default.equal(outcome.attempts[0].ok, false);
    strict_1.default.equal(outcome.attempts[0].code, 'TIMEOUT');
    // The failed call still produced an attempt, because it was still charged.
    strict_1.default.equal(outcome.attempts[1].ok, true);
});
(0, node_test_1.default)('every fallback-worthy code is walked past', async () => {
    for (const code of [
        'UNAVAILABLE',
        'TIMEOUT',
        'RATE_LIMITED',
        'INSUFFICIENT_CREDITS',
        'INVALID_SCHEMA',
        'NOT_CONFIGURED',
    ]) {
        const outcome = await (0, prospecting_providers_js_1.runChain)([stub('a', true), stub('b', true)], async (provider) => {
            if (provider.key === 'a') {
                throw new prospecting_providers_js_1.ProviderError({ code, provider: 'a', operation: 'ENRICH_COMPANY' });
            }
            return 'answered';
        });
        strict_1.default.equal(outcome.ok === true && outcome.value, 'answered', `code ${code}`);
    }
});
(0, node_test_1.default)('NO_RESULT ends the chain, because it is an answer', async () => {
    // Asking the next provider would be a second charge to hear the same thing.
    // Fallback routes around breakage; it does not shop for a better reply.
    const second = stub('b', true);
    const outcome = await (0, prospecting_providers_js_1.runChain)([stub('a', true), second], async (provider) => {
        if (provider.key === 'a') {
            throw new prospecting_providers_js_1.ProviderError({
                code: 'NO_RESULT',
                provider: 'a',
                operation: 'FIND_DECISION_MAKERS',
            });
        }
        return provider.key;
    });
    strict_1.default.equal(outcome.ok, false);
    strict_1.default.equal(outcome.ok === false && outcome.code, 'NO_RESULT');
    strict_1.default.equal(outcome.attempts.length, 1);
});
(0, node_test_1.default)('a chain of nothing configured fails with NOT_CONFIGURED', async () => {
    const outcome = await (0, prospecting_providers_js_1.runChain)([stub('a', false), stub('b', false)], async () => 'x');
    strict_1.default.equal(outcome.ok, false);
    strict_1.default.equal(outcome.ok === false && outcome.code, 'NOT_CONFIGURED');
    strict_1.default.deepEqual(outcome.attempts, []);
});
(0, node_test_1.default)('an error that is not a ProviderError is treated as the provider being down', async () => {
    const outcome = await (0, prospecting_providers_js_1.runChain)([stub('a', true)], async () => {
        throw new TypeError('fetch is not defined');
    });
    strict_1.default.equal(outcome.ok === false && outcome.code, 'UNAVAILABLE');
});
/* --------------------------------------------------------- not configured */
(0, node_test_1.default)('the not-configured provider refuses every operation without calling anything', async () => {
    const provider = new prospecting_provider_fixtures_js_1.NotConfiguredProvider('aisa');
    strict_1.default.equal(provider.isConfigured(), false);
    for (const call of [
        () => provider.searchBusinesses(),
        () => provider.enrichCompany(),
        () => provider.findDecisionMakers(),
        () => provider.enrichPerson(),
        () => provider.researchCompany(),
    ]) {
        await strict_1.default.rejects(call, (error) => {
            strict_1.default.ok(error instanceof prospecting_providers_js_1.ProviderError);
            strict_1.default.equal(error.code, 'NOT_CONFIGURED');
            strict_1.default.equal(error.provider, 'aisa');
            return true;
        });
    }
});
/* ------------------------------------------------------------- fabrication */
function person(overrides = {}) {
    return {
        first_name: 'Arlindo',
        last_name: null,
        job_title: 'Proprietário',
        seniority: 'OWNER',
        email: null,
        email_status: 'UNKNOWN',
        phone: null,
        linkedin_url: null,
        provider_person_id: 'p1',
        confidence_score: null,
        ...overrides,
    };
}
(0, node_test_1.default)('a person with nothing known is accepted; absence is not fabrication', () => {
    strict_1.default.doesNotThrow(() => (0, prospecting_providers_js_1.assertNoFabrication)(person(), 'x', 'ENRICH_PERSON'));
});
(0, node_test_1.default)('an address that is not an address is refused', () => {
    strict_1.default.throws(() => (0, prospecting_providers_js_1.assertNoFabrication)(person({ email: 'not-an-email' }), 'x', 'ENRICH_PERSON'), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
});
(0, node_test_1.default)('a VERIFIED status with no address is refused', () => {
    strict_1.default.throws(() => (0, prospecting_providers_js_1.assertNoFabrication)(person({ email_status: 'VERIFIED' }), 'x', 'ENRICH_PERSON'), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
});
(0, node_test_1.default)('a confidence score outside nought to one is refused', () => {
    for (const value of [-0.1, 1.5, 90]) {
        strict_1.default.throws(() => (0, prospecting_providers_js_1.assertNoFabrication)(person({ confidence_score: value }), 'x', 'ENRICH_PERSON'), (error) => error instanceof prospecting_providers_js_1.ProviderError, `confidence ${value}`);
    }
});
function company(overrides = {}) {
    return {
        name: 'Barbearia X',
        legal_name: null,
        domain: null,
        website: null,
        industry: 'barbershop',
        latitude: null,
        longitude: null,
        industry_raw: 'Barbearia',
        employee_count: null,
        city: 'Maputo',
        province: null,
        country: 'Moçambique',
        address: null,
        phone: null,
        email: null,
        linkedin_url: null,
        instagram_url: null,
        facebook_url: null,
        whatsapp: null,
        rating: null,
        review_count: null,
        has_opening_hours: null,
        has_photos: null,
        business_status: null,
        source: 'x',
        source_reference: null,
        provider_org_id: null,
        ...overrides,
    };
}
(0, node_test_1.default)('a company with no name is refused', () => {
    strict_1.default.throws(() => (0, prospecting_providers_js_1.assertCompanySane)(company({ name: '  ' }), 'x', 'SEARCH_BUSINESSES'), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'INVALID_SCHEMA');
});
(0, node_test_1.default)('an employee count that is not a whole number is refused', () => {
    strict_1.default.throws(() => (0, prospecting_providers_js_1.assertCompanySane)(company({ employee_count: 6.5 }), 'x', 'SEARCH_BUSINESSES'), (error) => error instanceof prospecting_providers_js_1.ProviderError);
    strict_1.default.throws(() => (0, prospecting_providers_js_1.assertCompanySane)(company({ employee_count: -1 }), 'x', 'SEARCH_BUSINESSES'), (error) => error instanceof prospecting_providers_js_1.ProviderError);
});
/* -------------------------------------------------------------- seniority */
(0, node_test_1.default)('a title maps to the seniority the scorer reads, in both languages', () => {
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Proprietário'), 'OWNER');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Owner'), 'OWNER');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Fundadora'), 'FOUNDER');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('CEO'), 'C_LEVEL');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Directora Geral'), 'DIRECTOR');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Gerente'), 'MANAGER');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Atendimento'), 'STAFF');
});
(0, node_test_1.default)('an unmapped title is UNKNOWN, never STAFF', () => {
    // Treating it as junior would quietly drop real owners whose title is
    // written in a way nobody anticipated.
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)('Chefe de Tesoura'), 'UNKNOWN');
    strict_1.default.equal((0, prospecting_providers_js_1.seniorityFromTitle)(null), 'UNKNOWN');
});
/* --------------------------------------------------------------- fixtures */
(0, node_test_1.default)('the fixture provider pages through its results', async () => {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const first = await provider.searchBusinesses({
        industries: ['barbershop'],
        city: 'Maputo',
        province: null,
        country: 'Moçambique',
        employeeMin: null,
        employeeMax: null,
        limit: 2,
        cursor: null,
    });
    strict_1.default.equal(first.length, 2);
    const cursor = first[first.length - 1].cursor;
    strict_1.default.ok(cursor, 'expected a cursor for the next page');
    const second = await provider.searchBusinesses({
        industries: ['barbershop'],
        city: 'Maputo',
        province: null,
        country: 'Moçambique',
        employeeMin: null,
        employeeMax: null,
        limit: 2,
        cursor,
    });
    strict_1.default.ok(second.length > 0);
    strict_1.default.notEqual(second[0].company.name + second[0].company.provider_org_id, first[0].company.name + first[0].company.provider_org_id);
});
(0, node_test_1.default)('the fixture provider filters by employee range without dropping unknown counts', async () => {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const results = await provider.searchBusinesses({
        industries: [],
        city: null,
        province: null,
        country: 'Moçambique',
        employeeMin: 3,
        employeeMax: 20,
        limit: 100,
        cursor: null,
    });
    for (const result of results) {
        const count = result.company.employee_count;
        // A business whose size is unknown is not excluded by a size filter — it
        // is unknown, and excluding it would be reading null as "too big".
        strict_1.default.ok(count === null || (count >= 3 && count <= 20), `count ${count}`);
    }
    strict_1.default.ok(results.some((result) => result.company.employee_count === null));
});
(0, node_test_1.default)('a configured failure surfaces as that code, for the chain to act on', async () => {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider({ failWith: 'RATE_LIMITED' });
    await strict_1.default.rejects(() => provider.searchBusinesses({
        industries: [],
        city: null,
        province: null,
        country: 'MZ',
        employeeMin: null,
        employeeMax: null,
        limit: 10,
        cursor: null,
    }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'RATE_LIMITED');
});
(0, node_test_1.default)('an empty provider answers NO_RESULT rather than an empty person', async () => {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider({ empty: true });
    await strict_1.default.rejects(() => provider.findDecisionMakers({
        companyName: 'Barbearia Exemplo Central',
        domain: null,
        providerOrgId: 'fx-org-001',
        titles: [],
        limit: 5,
    }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NO_RESULT');
});
(0, node_test_1.default)('a company with no decision maker in the fixtures answers NO_RESULT', async () => {
    // Most businesses do not yield one on the first attempt, and the NO_CONTACT
    // path is the one an operator will meet most often.
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    await strict_1.default.rejects(() => provider.findDecisionMakers({
        companyName: 'Café Exemplo Aroma',
        domain: null,
        providerOrgId: 'fx-org-007',
        titles: [],
        limit: 5,
    }), (error) => error instanceof prospecting_providers_js_1.ProviderError && error.code === 'NO_RESULT');
});
(0, node_test_1.default)('every fixture company survives the sanity check', async () => {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const results = await provider.searchBusinesses({
        industries: [],
        city: null,
        province: null,
        country: 'Moçambique',
        employeeMin: null,
        employeeMax: null,
        limit: 100,
        cursor: null,
    });
    strict_1.default.equal(results.length, 20);
});
(0, node_test_1.default)('every fixture person survives the fabrication check', async () => {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const found = await provider.findDecisionMakers({
        companyName: 'Barbearia Exemplo Central',
        domain: null,
        providerOrgId: 'fx-org-001',
        titles: [],
        limit: 5,
    });
    strict_1.default.equal(found.length, 1);
    strict_1.default.equal(found[0].person.email_status, 'VERIFIED');
});
(0, node_test_1.default)('fixture contact details are unmistakably fictional', async () => {
    // Nothing here may become the contact detail of a real person or business.
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const results = await provider.searchBusinesses({
        industries: [],
        city: null,
        province: null,
        country: 'Moçambique',
        employeeMin: null,
        employeeMax: null,
        limit: 100,
        cursor: null,
    });
    for (const { company: record } of results) {
        if (record.domain !== null) {
            strict_1.default.ok(record.domain.endsWith('.test'), `${record.domain} must be under .test`);
        }
        if (record.phone !== null) {
            // Normalised first, because one fixture deliberately writes its number
            // with spaces — it is the duplicate that proves deduplication folds two
            // spellings of one business together.
            const normalized = (0, prospecting_normalization_js_1.normalizePhone)(record.phone, '+258');
            strict_1.default.ok(normalized, `${record.phone} is not a phone number`);
            strict_1.default.ok(normalized.startsWith('+2588400001') || normalized.startsWith('+2582100001'), `${normalized} is outside the fixture block`);
        }
    }
});
