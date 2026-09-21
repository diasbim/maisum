import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertCompanySane,
  assertNoFabrication,
  ProviderError,
  runChain,
  seniorityFromTitle,
  type CompanyRecord,
  type PersonRecord,
  type ProviderIdentity,
} from './prospecting_providers.js';
import { FixtureProvider, NotConfiguredProvider } from './prospecting_provider_fixtures.js';
import { normalizePhone } from './prospecting_normalization.js';

/* ------------------------------------------------------------- the chain */

type Stub = ProviderIdentity & { calls: number };

function stub(key: string, configured: boolean): Stub {
  return { key, calls: 0, isConfigured: () => configured };
}

test('the first configured provider that answers ends the chain', async () => {
  const first = stub('a', true);
  const second = stub('b', true);

  const outcome = await runChain([first, second], async (provider) => {
    (provider as Stub).calls++;
    return provider.key;
  });

  assert.equal(outcome.ok, true);
  assert.equal(outcome.ok === true && outcome.value, 'a');
  assert.equal(outcome.ok === true && outcome.partial, false);
  assert.equal(second.calls, 0);
});

test('an unconfigured provider is skipped without being called or charged', async () => {
  const first = stub('a', false);
  const second = stub('b', true);

  const outcome = await runChain([first, second], async (provider) => {
    (provider as Stub).calls++;
    return provider.key;
  });

  assert.equal(outcome.ok === true && outcome.value, 'b');
  assert.equal(first.calls, 0);
  // Nothing was spent, so nothing is recorded for it.
  assert.equal(outcome.attempts.length, 1);
});

test('a failure falls through to the next provider and the result is marked partial', async () => {
  const first = stub('a', true);
  const second = stub('b', true);

  const outcome = await runChain([first, second], async (provider) => {
    if (provider.key === 'a') {
      throw new ProviderError({
        code: 'TIMEOUT',
        provider: 'a',
        operation: 'ENRICH_COMPANY',
      });
    }
    return provider.key;
  });

  assert.equal(outcome.ok === true && outcome.value, 'b');
  assert.equal(outcome.ok === true && outcome.partial, true);
  assert.equal(outcome.attempts.length, 2);
  assert.equal(outcome.attempts[0].ok, false);
  assert.equal(outcome.attempts[0].code, 'TIMEOUT');
  // The failed call still produced an attempt, because it was still charged.
  assert.equal(outcome.attempts[1].ok, true);
});

test('every fallback-worthy code is walked past', async () => {
  for (const code of [
    'UNAVAILABLE',
    'TIMEOUT',
    'RATE_LIMITED',
    'INSUFFICIENT_CREDITS',
    'INVALID_SCHEMA',
    'NOT_CONFIGURED',
  ] as const) {
    const outcome = await runChain([stub('a', true), stub('b', true)], async (provider) => {
      if (provider.key === 'a') {
        throw new ProviderError({ code, provider: 'a', operation: 'ENRICH_COMPANY' });
      }
      return 'answered';
    });
    assert.equal(outcome.ok === true && outcome.value, 'answered', `code ${code}`);
  }
});

test('NO_RESULT ends the chain, because it is an answer', async () => {
  // Asking the next provider would be a second charge to hear the same thing.
  // Fallback routes around breakage; it does not shop for a better reply.
  const second = stub('b', true);

  const outcome = await runChain([stub('a', true), second], async (provider) => {
    if (provider.key === 'a') {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: 'a',
        operation: 'FIND_DECISION_MAKERS',
      });
    }
    return provider.key;
  });

  assert.equal(outcome.ok, false);
  assert.equal(outcome.ok === false && outcome.code, 'NO_RESULT');
  assert.equal(outcome.attempts.length, 1);
});

test('a chain of nothing configured fails with NOT_CONFIGURED', async () => {
  const outcome = await runChain([stub('a', false), stub('b', false)], async () => 'x');
  assert.equal(outcome.ok, false);
  assert.equal(outcome.ok === false && outcome.code, 'NOT_CONFIGURED');
  assert.deepEqual(outcome.attempts, []);
});

test('an error that is not a ProviderError is treated as the provider being down', async () => {
  const outcome = await runChain([stub('a', true)], async () => {
    throw new TypeError('fetch is not defined');
  });
  assert.equal(outcome.ok === false && outcome.code, 'UNAVAILABLE');
});

/* --------------------------------------------------------- not configured */

test('the not-configured provider refuses every operation without calling anything', async () => {
  const provider = new NotConfiguredProvider('aisa');
  assert.equal(provider.isConfigured(), false);

  for (const call of [
    () => provider.searchBusinesses(),
    () => provider.enrichCompany(),
    () => provider.findDecisionMakers(),
    () => provider.enrichPerson(),
    () => provider.researchCompany(),
  ]) {
    await assert.rejects(call, (error: unknown) => {
      assert.ok(error instanceof ProviderError);
      assert.equal(error.code, 'NOT_CONFIGURED');
      assert.equal(error.provider, 'aisa');
      return true;
    });
  }
});

/* ------------------------------------------------------------- fabrication */

function person(overrides: Partial<PersonRecord> = {}): PersonRecord {
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

test('a person with nothing known is accepted; absence is not fabrication', () => {
  assert.doesNotThrow(() => assertNoFabrication(person(), 'x', 'ENRICH_PERSON'));
});

test('an address that is not an address is refused', () => {
  assert.throws(
    () => assertNoFabrication(person({ email: 'not-an-email' }), 'x', 'ENRICH_PERSON'),
    (error: unknown) => error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
});

test('a VERIFIED status with no address is refused', () => {
  assert.throws(
    () => assertNoFabrication(person({ email_status: 'VERIFIED' }), 'x', 'ENRICH_PERSON'),
    (error: unknown) => error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
});

test('a confidence score outside nought to one is refused', () => {
  for (const value of [-0.1, 1.5, 90]) {
    assert.throws(
      () => assertNoFabrication(person({ confidence_score: value }), 'x', 'ENRICH_PERSON'),
      (error: unknown) => error instanceof ProviderError,
      `confidence ${value}`,
    );
  }
});

function company(overrides: Partial<CompanyRecord> = {}): CompanyRecord {
  return {
    name: 'Barbearia X',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'barbershop',
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

test('a company with no name is refused', () => {
  assert.throws(
    () => assertCompanySane(company({ name: '  ' }), 'x', 'SEARCH_BUSINESSES'),
    (error: unknown) => error instanceof ProviderError && error.code === 'INVALID_SCHEMA',
  );
});

test('an employee count that is not a whole number is refused', () => {
  assert.throws(
    () => assertCompanySane(company({ employee_count: 6.5 }), 'x', 'SEARCH_BUSINESSES'),
    (error: unknown) => error instanceof ProviderError,
  );
  assert.throws(
    () => assertCompanySane(company({ employee_count: -1 }), 'x', 'SEARCH_BUSINESSES'),
    (error: unknown) => error instanceof ProviderError,
  );
});

/* -------------------------------------------------------------- seniority */

test('a title maps to the seniority the scorer reads, in both languages', () => {
  assert.equal(seniorityFromTitle('Proprietário'), 'OWNER');
  assert.equal(seniorityFromTitle('Owner'), 'OWNER');
  assert.equal(seniorityFromTitle('Fundadora'), 'FOUNDER');
  assert.equal(seniorityFromTitle('CEO'), 'C_LEVEL');
  assert.equal(seniorityFromTitle('Directora Geral'), 'DIRECTOR');
  assert.equal(seniorityFromTitle('Gerente'), 'MANAGER');
  assert.equal(seniorityFromTitle('Atendimento'), 'STAFF');
});

test('an unmapped title is UNKNOWN, never STAFF', () => {
  // Treating it as junior would quietly drop real owners whose title is
  // written in a way nobody anticipated.
  assert.equal(seniorityFromTitle('Chefe de Tesoura'), 'UNKNOWN');
  assert.equal(seniorityFromTitle(null), 'UNKNOWN');
});

/* --------------------------------------------------------------- fixtures */

test('the fixture provider pages through its results', async () => {
  const provider = new FixtureProvider();

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

  assert.equal(first.length, 2);
  const cursor = first[first.length - 1].cursor;
  assert.ok(cursor, 'expected a cursor for the next page');

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

  assert.ok(second.length > 0);
  assert.notEqual(second[0].company.name + second[0].company.provider_org_id,
    first[0].company.name + first[0].company.provider_org_id);
});

test('the fixture provider filters by employee range without dropping unknown counts', async () => {
  const provider = new FixtureProvider();
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
    assert.ok(count === null || (count >= 3 && count <= 20), `count ${count}`);
  }
  assert.ok(results.some((result) => result.company.employee_count === null));
});

test('a configured failure surfaces as that code, for the chain to act on', async () => {
  const provider = new FixtureProvider({ failWith: 'RATE_LIMITED' });
  await assert.rejects(
    () =>
      provider.searchBusinesses({
        industries: [],
        city: null,
        province: null,
        country: 'MZ',
        employeeMin: null,
        employeeMax: null,
        limit: 10,
        cursor: null,
      }),
    (error: unknown) => error instanceof ProviderError && error.code === 'RATE_LIMITED',
  );
});

test('an empty provider answers NO_RESULT rather than an empty person', async () => {
  const provider = new FixtureProvider({ empty: true });
  await assert.rejects(
    () =>
      provider.findDecisionMakers({
        companyName: 'Barbearia Exemplo Central',
        domain: null,
        providerOrgId: 'fx-org-001',
        titles: [],
        limit: 5,
      }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NO_RESULT',
  );
});

test('a company with no decision maker in the fixtures answers NO_RESULT', async () => {
  // Most businesses do not yield one on the first attempt, and the NO_CONTACT
  // path is the one an operator will meet most often.
  const provider = new FixtureProvider();
  await assert.rejects(
    () =>
      provider.findDecisionMakers({
        companyName: 'Café Exemplo Aroma',
        domain: null,
        providerOrgId: 'fx-org-007',
        titles: [],
        limit: 5,
      }),
    (error: unknown) => error instanceof ProviderError && error.code === 'NO_RESULT',
  );
});

test('every fixture company survives the sanity check', async () => {
  const provider = new FixtureProvider();
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
  assert.equal(results.length, 20);
});

test('every fixture person survives the fabrication check', async () => {
  const provider = new FixtureProvider();
  const found = await provider.findDecisionMakers({
    companyName: 'Barbearia Exemplo Central',
    domain: null,
    providerOrgId: 'fx-org-001',
    titles: [],
    limit: 5,
  });
  assert.equal(found.length, 1);
  assert.equal(found[0].person.email_status, 'VERIFIED');
});

test('fixture contact details are unmistakably fictional', async () => {
  // Nothing here may become the contact detail of a real person or business.
  const provider = new FixtureProvider();
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
      assert.ok(record.domain.endsWith('.test'), `${record.domain} must be under .test`);
    }
    if (record.phone !== null) {
      // Normalised first, because one fixture deliberately writes its number
      // with spaces — it is the duplicate that proves deduplication folds two
      // spellings of one business together.
      const normalized = normalizePhone(record.phone, '+258');
      assert.ok(normalized, `${record.phone} is not a phone number`);
      assert.ok(
        normalized.startsWith('+2588400001') || normalized.startsWith('+2582100001'),
        `${normalized} is outside the fixture block`,
      );
    }
  }
});
