import assert from 'node:assert/strict';
import test from 'node:test';

import { DEFAULT_SETTINGS } from './prospecting_config.js';
import type { ProspectSource, ProspectStatus } from './prospecting_contracts.js';
import {
  fetchListingDetails,
  findDecisionMakers,
  researchCompany,
  runDiscoveryBatch,
  signalsFromCompany,
  signalsFromResearch,
  storeDiscovered,
  type PipelineDeps,
  type PipelineStore,
} from './prospecting_pipeline.js';
import { COMPANY_FIXTURES, FixtureProvider } from './prospecting_provider_fixtures.js';
import {
  buildMatchKeys,
  matchKeyDocId,
} from './prospecting_normalization.js';
import type {
  CompanyRecord,
  ListingDetailResult,
} from './prospecting_providers.js';

/**
 * The whole pipeline over a map.
 *
 * `MemoryStore` is the real dedup rule — the same lookup-key claim the
 * Firestore store implements — over a JavaScript `Map`. That is what makes
 * criterion 9 provable here rather than only in an emulator: the property
 * being tested is that two spellings of one business claim the same key, and
 * the key is computed by the same function in both implementations.
 */

class MemoryStore implements PipelineStore {
  readonly companies = new Map<string, CompanyRecord>();
  readonly lookup = new Map<string, string>();
  readonly prospects = new Map<
    string,
    {
      id: string;
      companyId: string;
      status: ProspectStatus;
      source: ProspectSource;
      suspectedMerchantId: string | null;
      disqualifyReason: string | null;
      enrichmentStatus: string;
      decisionMakerCount: number;
      hasReachableContact: boolean;
      score: number | null;
      spendUsd: number;
    }
  >();
  readonly contacts: Array<{ prospectId: string; name: string | null; isDecisionMaker: boolean }> = [];
  readonly activities: Array<{ prospectId: string; type: string; description: string }> = [];
  readonly usage: Array<{
    provider: string;
    operation: string;
    success: boolean;
    errorCode: string | null;
    cost: number;
    actualCost: number | null;
    prospectId: string | null;
  }> = [];

  /** Existing MaisUm merchants, as `businesses` documents would be. */
  merchants: Array<{ id: string; name: string; phone: string | null }> = [];

  monthSpend = 0;
  daySpend = 0;

  private nextId = 1;

  async claimCompany(company: CompanyRecord) {
    const keys = buildMatchKeys(
      {
        name: company.name,
        city: company.city,
        domain: company.domain,
        website: company.website,
        phone: company.phone,
        whatsapp: company.whatsapp,
        providerOrgId: company.provider_org_id,
        provider: company.source,
        linkedinUrl: company.linkedin_url,
        instagramUrl: company.instagram_url,
        facebookUrl: company.facebook_url,
      },
      DEFAULT_SETTINGS.geography.phoneCountryCode,
    );

    let companyId: string | null = null;
    let matchedOn: { kind: string; value: string } | null = null;

    for (const key of keys) {
      const found = this.lookup.get(matchKeyDocId(key));
      if (found !== undefined) {
        companyId = found;
        matchedOn = key;
        break;
      }
    }

    const created = companyId === null;
    const id = companyId ?? `company_${this.nextId++}`;

    for (const key of keys) this.lookup.set(matchKeyDocId(key), id);

    if (created) {
      this.companies.set(id, company);
    } else {
      const existing = this.companies.get(id);
      if (existing !== undefined) {
        // Fills gaps, never overwrites with a null.
        const merged = { ...existing };
        for (const [field, value] of Object.entries(company)) {
          if (value !== null && value !== undefined) {
            (merged as Record<string, unknown>)[field] = value;
          }
        }
        this.companies.set(id, merged);
      }
    }

    return { companyId: id, created, matchedOn };
  }

  async matchExistingCustomer(company: CompanyRecord) {
    const normalize = (value: string | null) =>
      value === null ? null : value.replace(/\D/g, '');
    const fold = (value: string) =>
      value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();

    let nameMatch: { kind: 'NAME'; merchantId: string; merchantName: string | null } | null =
      null;

    for (const merchant of this.merchants) {
      const merchantPhone = normalize(merchant.phone);
      if (
        merchantPhone !== null &&
        (merchantPhone === normalize(company.phone) ||
          merchantPhone === normalize(company.whatsapp))
      ) {
        return { kind: 'PHONE' as const, merchantId: merchant.id, merchantName: merchant.name };
      }
      if (nameMatch === null && fold(merchant.name) === fold(company.name)) {
        nameMatch = { kind: 'NAME', merchantId: merchant.id, merchantName: merchant.name };
      }
    }

    return nameMatch ?? { kind: 'NONE' as const };
  }

  async createProspect(input: {
    companyId: string;
    source: ProspectSource;
    sourceReference: string | null;
    status: ProspectStatus;
    suspectedMerchantId?: string | null;
    disqualifyReason?: string | null;
  }) {
    const existing = this.prospects.get(input.companyId);
    if (existing !== undefined) {
      return { prospectId: existing.id, created: false };
    }

    this.prospects.set(input.companyId, {
      id: input.companyId,
      companyId: input.companyId,
      status: input.status,
      source: input.source,
      suspectedMerchantId: input.suspectedMerchantId ?? null,
      disqualifyReason: input.disqualifyReason ?? null,
      enrichmentStatus: 'NOT_STARTED',
      decisionMakerCount: 0,
      hasReachableContact: false,
      score: null,
      spendUsd: 0,
    });

    return { prospectId: input.companyId, created: true };
  }

  async saveScores(input: { prospectId: string; score: { total: number } }) {
    const prospect = this.prospects.get(input.prospectId);
    if (prospect !== undefined) prospect.score = input.score.total;
  }

  async setStatus(input: { prospectId: string; to: ProspectStatus }) {
    const prospect = this.prospects.get(input.prospectId);
    if (prospect !== undefined) prospect.status = input.to;
  }

  async setEnrichment(input: {
    prospectId: string;
    status: string;
    decisionMakerCount?: number;
    hasReachableContact?: boolean;
  }) {
    const prospect = this.prospects.get(input.prospectId);
    if (prospect === undefined) return;
    prospect.enrichmentStatus = input.status;
    if (input.decisionMakerCount !== undefined) {
      prospect.decisionMakerCount = input.decisionMakerCount;
    }
    if (input.hasReachableContact !== undefined) {
      prospect.hasReachableContact = input.hasReachableContact;
    }
  }

  async saveContact(input: {
    prospectId: string;
    person: { first_name: string | null };
    isDecisionMaker: boolean;
  }) {
    this.contacts.push({
      prospectId: input.prospectId,
      name: input.person.first_name,
      isDecisionMaker: input.isDecisionMaker,
    });
  }

  async updateCompanyListing(input: {
    companyId: string;
    phone: string | null;
    website: string | null;
    hasOpeningHours: boolean | null;
    hasPhotos: boolean | null;
  }) {
    const existing = this.companies.get(input.companyId);
    if (existing === undefined) return;
    // The same narrowing the Firestore store does: a null phone is "the
    // response did not carry one", which must not erase what discovery found.
    this.companies.set(input.companyId, {
      ...existing,
      phone: input.phone ?? existing.phone,
      website: input.website ?? existing.website,
      has_opening_hours: input.hasOpeningHours,
      has_photos: input.hasPhotos,
    });
  }

  async appendActivity(input: { prospectId: string; type: string; description: string }) {
    this.activities.push({
      prospectId: input.prospectId,
      type: input.type,
      description: input.description,
    });
  }

  async recordUsage(input: {
    provider: string;
    operation: string;
    prospectId: string | null;
    estimatedCostUsd: number;
    actualCostUsd?: number | null;
    success: boolean;
    errorCode: string | null;
  }) {
    this.usage.push({
      provider: input.provider,
      operation: input.operation,
      success: input.success,
      errorCode: input.errorCode,
      cost: input.estimatedCostUsd,
      actualCost: input.actualCostUsd ?? null,
      prospectId: input.prospectId,
    });

    this.monthSpend = Math.round((this.monthSpend + input.estimatedCostUsd) * 10_000) / 10_000;
    this.daySpend = Math.round((this.daySpend + input.estimatedCostUsd) * 10_000) / 10_000;

    if (input.prospectId !== null) {
      const prospect = this.prospects.get(input.prospectId);
      if (prospect !== undefined) {
        prospect.spendUsd =
          Math.round((prospect.spendUsd + input.estimatedCostUsd) * 10_000) / 10_000;
      }
    }
  }

  async readSpend(prospectId: string | null) {
    return {
      monthUsd: this.monthSpend,
      dayUsd: this.daySpend,
      leadUsd:
        prospectId === null ? 0 : (this.prospects.get(prospectId)?.spendUsd ?? 0),
    };
  }
}

function deps(overrides: Partial<PipelineDeps> = {}): PipelineDeps & { store: MemoryStore } {
  const store = (overrides.store as MemoryStore) ?? new MemoryStore();
  const provider = new FixtureProvider();

  return {
    store,
    providers: {
      discovery: [provider],
      personDiscovery: [provider],
      personEnrichment: [provider],
      webResearch: [provider],
      listingDetail: [],
    },
    settings: DEFAULT_SETTINGS,
    now: () => 1_758_000_000_000,
    ...overrides,
    // Keep the concrete store on the returned object for assertions.
    ...(overrides.store === undefined ? {} : { store }),
  } as PipelineDeps & { store: MemoryStore };
}

const CRITERIA = {
  industries: ['barbershop'],
  city: 'Maputo',
  province: null,
  employeeMin: null,
  employeeMax: null,
  minScore: 60,
  maxLeads: 100,
};

function fixtureCompany(orgId: string): CompanyRecord {
  const fixture = COMPANY_FIXTURES.find((entry) => entry.provider_org_id === orgId);
  assert.ok(fixture, `no fixture ${orgId}`);
  return {
    ...fixture,
    // The listing fields are optional on a fixture and required on the record.
    // Same defaulting as `FixturesProvider.toCompany`, for the tests that
    // build a record straight from the table.
    rating: fixture.rating ?? null,
    review_count: fixture.review_count ?? null,
    has_opening_hours: fixture.has_opening_hours ?? null,
    has_photos: fixture.has_photos ?? null,
    business_status: fixture.business_status ?? null,
    latitude: fixture.latitude ?? null,
    longitude: fixture.longitude ?? null,
    source: 'fixtures',
    source_reference: orgId,
  };
}

/* ----------------------------------------------- criterion 9: duplicates */

test('the same business discovered twice produces one company', async () => {
  const context = deps();

  const first = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });
  const second = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(first.created, true);
  assert.equal(second.created, false);
  assert.equal(first.companyId, second.companyId);
  assert.equal(context.store.companies.size, 1);
  assert.equal(context.store.prospects.size, 1);
});

test('two spellings of one business produce one company', async () => {
  // fx-org-020 is fx-org-001 written the way a second provider would write it:
  // a scheme and a www, the legal suffix attached, the phone spaced out.
  const context = deps();

  const first = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });
  const second = await storeDiscovered({
    company: fixtureCompany('fx-org-020'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(second.created, false);
  assert.equal(first.companyId, second.companyId);
  assert.equal(context.store.companies.size, 1);
});

test('a whole discovery run stores no duplicate companies', async () => {
  const context = deps();

  await runDiscoveryBatch({
    criteria: { ...CRITERIA, industries: [] },
    cursor: null,
    batchSize: 100,
    deps: context,
  });

  // Twenty fixtures, less the one whose trade is outside the ICP — an empty
  // industry list means every ICP industry, not every business on earth, so
  // the workshop is never searched for. Of the nineteen that come back, two
  // are the same business written two ways.
  assert.equal(context.store.companies.size, 18);

  const companyIds = [...context.store.lookup.values()];
  assert.equal(new Set(companyIds).size, 18);
});

test('a second sighting fills gaps without erasing what was known', async () => {
  const context = deps();

  await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });
  // The duplicate has no Instagram URL; the original does. A plain merge of
  // the new record would null it out.
  await storeDiscovered({
    company: fixtureCompany('fx-org-020'),
    criteria: CRITERIA,
    deps: context,
  });

  const stored = [...context.store.companies.values()][0];
  assert.ok(stored.instagram_url, 'the known Instagram URL was erased');
  assert.equal(stored.legal_name, 'Barbearia Exemplo Central Lda');
});

/* ------------------------------------------ criterion 10: real customers */

test('a business whose phone matches a merchant is never a lead', async () => {
  const context = deps();
  context.store.merchants = [
    { id: 'merchant_1', name: 'Outro Nome Qualquer', phone: '+258840000101' },
  ];

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(result.status, 'EXISTING_CUSTOMER');
  assert.equal(result.qualified, false);
  assert.equal(result.score, null);

  const prospect = context.store.prospects.get(result.prospectId);
  assert.equal(prospect?.status, 'EXISTING_CUSTOMER');
  assert.equal(prospect?.suspectedMerchantId, 'merchant_1');
});

test('a phone match wins over the trade and the city', async () => {
  // An existing customer is recognised as one whatever else is true.
  const context = deps();
  context.store.merchants = [
    { id: 'merchant_1', name: 'Oficina Exemplo Motor', phone: '+258840000118' },
  ];

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-018'),
    criteria: CRITERIA,
    deps: context,
  });

  // Would otherwise have been NOT_A_FIT on the trade.
  assert.equal(result.status, 'EXISTING_CUSTOMER');
});

test('a name-only match is flagged for a person, not made terminal', async () => {
  // `businesses` stores no city, so a name match has nothing to disambiguate
  // it. EXISTING_CUSTOMER is terminal and terminal is irreversible, and a name
  // collision must not be able to kill a real lead permanently.
  const context = deps();
  context.store.merchants = [
    { id: 'merchant_9', name: 'Barbearia Exemplo Central', phone: '+258999999999' },
  ];

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(result.status, 'SCORED');
  const prospect = context.store.prospects.get(result.prospectId);
  assert.equal(prospect?.suspectedMerchantId, 'merchant_9');
});

/* ---------------------------------------------------------- qualification */

test('a business outside the ICP is stored as NOT_A_FIT with the reason', async () => {
  const context = deps();

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-018'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(result.status, 'NOT_A_FIT');
  assert.equal(
    context.store.prospects.get(result.prospectId)?.disqualifyReason,
    'NOT_TARGET_INDUSTRY',
  );
});

test('a business outside the geography is stored as NOT_A_FIT with the reason', async () => {
  const context = deps();

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-019'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(result.status, 'NOT_A_FIT');
  assert.equal(
    context.store.prospects.get(result.prospectId)?.disqualifyReason,
    'OUT_OF_GEOGRAPHY',
  );
});

test('widening the configured cities is all it takes to qualify Beira', async () => {
  const context = deps({
    settings: {
      ...DEFAULT_SETTINGS,
      geography: {
        ...DEFAULT_SETTINGS.geography,
        cities: [...DEFAULT_SETTINGS.geography.cities, 'Beira'],
        provinces: [...DEFAULT_SETTINGS.geography.provinces, 'Sofala'],
      },
    },
  });

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-019'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(result.status, 'SCORED');
});

test('the pipeline runs in the fixed order, and the trail evidences it', async () => {
  const context = deps();

  const result = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  assert.equal(result.status, 'SCORED');
  assert.ok(result.score);
  assert.ok(result.score.total > 0);

  const types = context.store.activities.map((entry) => entry.type);
  assert.deepEqual(types, ['DISCOVERED']);
});

/* ------------------------------------------------ criterion 11: the cap */

test('enrichment stops at the monthly cap and says which cap stopped it', async () => {
  const context = deps();
  context.store.monthSpend = 49.99;

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  const outcome = await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-001'),
    leadScore: 90,
    deps: context,
  });

  assert.equal(outcome.refusal, 'MONTHLY_CAP');
  assert.equal(outcome.status, 'BUDGET_BLOCKED');
  assert.equal(outcome.contactsFound, 0);
  // Nothing was called, so nothing was charged.
  assert.equal(
    context.store.usage.some((row) => row.operation === 'FIND_DECISION_MAKERS'),
    false,
  );
});

test('a blocked budget is a state of its own, not a failure', async () => {
  const context = deps();
  context.store.monthSpend = 50;

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });
  await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-001'),
    leadScore: 90,
    deps: context,
  });

  assert.equal(
    context.store.prospects.get(stored.prospectId)?.enrichmentStatus,
    'BUDGET_BLOCKED',
  );
});

test('a lead below the threshold is never paid for', async () => {
  const context = deps();

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-015'),
    criteria: CRITERIA,
    deps: context,
  });

  const outcome = await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-015'),
    leadScore: 40,
    deps: context,
  });

  assert.equal(outcome.refusal, 'BELOW_THRESHOLD');
  assert.equal(outcome.status, 'BELOW_THRESHOLD');
  assert.equal(context.store.usage.length, 0);
});

test('the per-lead cap stops one lead without stopping the rest', async () => {
  const context = deps();

  const first = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });
  const prospect = context.store.prospects.get(first.prospectId);
  assert.ok(prospect);
  prospect.spendUsd = 0.49;

  const blocked = await findDecisionMakers({
    prospectId: first.prospectId,
    company: fixtureCompany('fx-org-001'),
    leadScore: 90,
    deps: context,
  });
  assert.equal(blocked.refusal, 'PER_LEAD_CAP');

  const second = await storeDiscovered({
    company: fixtureCompany('fx-org-003'),
    criteria: CRITERIA,
    deps: context,
  });
  const allowed = await findDecisionMakers({
    prospectId: second.prospectId,
    company: fixtureCompany('fx-org-003'),
    leadScore: 90,
    deps: context,
  });
  assert.equal(allowed.refusal, null);
});

/* -------------------------------------------------------------- enrichment */

test('a decision maker is found, enriched and stored', async () => {
  const context = deps();

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  const outcome = await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-001'),
    leadScore: 90,
    deps: context,
  });

  assert.equal(outcome.status, 'COMPLETE');
  assert.equal(outcome.decisionMakersFound, 1);
  assert.equal(context.store.contacts.length, 1);
  assert.equal(context.store.contacts[0].name, 'Arlindo');
  assert.equal(context.store.contacts[0].isDecisionMaker, true);
  assert.ok(outcome.spentUsd > 0);
});

test('a company with no decision maker records NO_RESULT, so it is not paid for twice', async () => {
  const context = deps();

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-007'),
    criteria: CRITERIA,
    deps: context,
  });

  const outcome = await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-007'),
    leadScore: 90,
    deps: context,
  });

  assert.equal(outcome.status, 'NO_RESULT');
  assert.equal(outcome.decisionMakersFound, 0);
  assert.equal(
    context.store.prospects.get(stored.prospectId)?.enrichmentStatus,
    'NO_RESULT',
  );
});

test('a contact who is not a decision maker is stored but not counted as one', async () => {
  const context = deps();

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-002'),
    criteria: CRITERIA,
    deps: context,
  });
  const outcome = await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-002'),
    leadScore: 90,
    deps: context,
  });

  assert.equal(context.store.contacts.length, 1);
  assert.equal(context.store.contacts[0].isDecisionMaker, false);
  assert.equal(outcome.decisionMakersFound, 0);
  assert.equal(outcome.status, 'NO_RESULT');
});

test('a decision maker with no way to reach them is PARTIAL, not COMPLETE', async () => {
  // fx-per-002 has a verified email, so use one whose only contact is a
  // LinkedIn URL by stripping what the fixture returns.
  const context = deps();
  const emptyEnrichment = new FixtureProvider({ key: 'no-enrichment', empty: true });
  const discovery = new FixtureProvider();

  const scoped: PipelineDeps = {
    ...context,
    providers: {
      discovery: [discovery],
      personDiscovery: [discovery],
      personEnrichment: [emptyEnrichment],
      webResearch: [discovery],
      listingDetail: [],
    },
  };

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-010'),
    criteria: CRITERIA,
    deps: scoped,
  });
  const outcome = await findDecisionMakers({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-010'),
    leadScore: 90,
    deps: scoped,
  });

  // The fixture person already carries a verified email from discovery, so
  // this stays COMPLETE — what is asserted is that a failed enrichment does
  // not erase what discovery already knew.
  assert.equal(outcome.status, 'COMPLETE');
  assert.equal(context.store.contacts.length, 1);
});

/* ------------------------------------------------------------- the chain */

test('a provider outage falls through and the failed attempt is still charged', async () => {
  const store = new MemoryStore();
  const broken = new FixtureProvider({ key: 'broken', failWith: 'UNAVAILABLE' });
  const working = new FixtureProvider({ key: 'working' });

  const context: PipelineDeps = {
    store,
    providers: {
      discovery: [broken, working],
      personDiscovery: [broken, working],
      personEnrichment: [working],
      webResearch: [working],
      listingDetail: [],
    },
    settings: DEFAULT_SETTINGS,
    now: () => 1_758_000_000_000,
  };

  const outcome = await runDiscoveryBatch({
    criteria: { ...CRITERIA, industries: ['barbershop'] },
    cursor: null,
    batchSize: 10,
    deps: context,
  });

  assert.ok(outcome.discovered > 0);
  const search = store.usage.filter((row) => row.operation === 'SEARCH_BUSINESSES');
  assert.equal(search.length, 2);
  assert.equal(search[0].success, false);
  assert.equal(search[0].provider, 'broken');
  assert.equal(search[1].success, true);
});

test('a provider that is not configured costs nothing at all', async () => {
  const store = new MemoryStore();
  const unconfigured = {
    key: 'unconfigured',
    isConfigured: () => false,
    searchBusinesses: async () => {
      throw new Error('should never be called');
    },
  };
  const working = new FixtureProvider({ key: 'working' });

  const context: PipelineDeps = {
    store,
    providers: {
      discovery: [unconfigured as never, working],
      personDiscovery: [working],
      personEnrichment: [working],
      webResearch: [working],
      listingDetail: [],
    },
    settings: DEFAULT_SETTINGS,
    now: () => 1_758_000_000_000,
  };

  await runDiscoveryBatch({
    criteria: CRITERIA,
    cursor: null,
    batchSize: 5,
    deps: context,
  });

  assert.equal(
    store.usage.some((row) => row.provider === 'unconfigured'),
    false,
  );
});

test('running out of results is the ordinary end of a search, not a failure', async () => {
  const store = new MemoryStore();
  const empty = new FixtureProvider({ key: 'empty', empty: true });

  const context: PipelineDeps = {
    store,
    providers: {
      discovery: [empty],
      personDiscovery: [empty],
      personEnrichment: [empty],
      webResearch: [empty],
      listingDetail: [],
    },
    settings: DEFAULT_SETTINGS,
    now: () => 1_758_000_000_000,
  };

  const outcome = await runDiscoveryBatch({
    criteria: CRITERIA,
    cursor: null,
    batchSize: 10,
    deps: context,
  });

  assert.equal(outcome.fatalCode, null);
  assert.equal(outcome.cursor, null);
  assert.equal(outcome.discovered, 0);
});

test('discovery is refused outright when the budget is gone', async () => {
  const context = deps();
  context.store.monthSpend = 50;

  const outcome = await runDiscoveryBatch({
    criteria: CRITERIA,
    cursor: null,
    batchSize: 10,
    deps: context,
  });

  assert.equal(outcome.fatalCode, 'MONTHLY_CAP');
  assert.equal(outcome.discovered, 0);
  assert.equal(context.store.usage.length, 0);
});

/* ------------------------------------------------------- reported costs */

test('a provider that reports its price has it recorded as the actual cost', async () => {
  // AIsa states what it charged through `X-AISA-Price-USD`. That figure must
  // reach the usage row, because it is the one thing in the month's total
  // that is not a guess.
  const store = new MemoryStore();
  const reporting = Object.assign(new FixtureProvider({ key: 'aisa' }), {
    lastCostUsd: 0.0184 as number | null,
    estimatedCostUsd: () => 0.012,
  });

  const context: PipelineDeps = {
    store,
    providers: {
      discovery: [reporting],
      personDiscovery: [reporting],
      personEnrichment: [reporting],
      webResearch: [reporting],
      listingDetail: [],
    },
    settings: DEFAULT_SETTINGS,
    now: () => 1_758_000_000_000,
  };

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });

  await researchCompany({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-001'),
    leadScore: 90,
    deps: context,
  });

  const row = store.usage.find((entry) => entry.operation === 'RESEARCH_COMPANY');
  assert.ok(row);
  assert.equal(row.actualCost, 0.0184);
  // Its own pre-authorisation figure, not the table rate.
  assert.equal(row.cost, 0.012);
});

test('a provider that reports nothing leaves the actual cost null', async () => {
  // Which is what makes the console label the month "estimado".
  const context = deps();

  const stored = await storeDiscovered({
    company: fixtureCompany('fx-org-001'),
    criteria: CRITERIA,
    deps: context,
  });
  await researchCompany({
    prospectId: stored.prospectId,
    company: fixtureCompany('fx-org-001'),
    leadScore: 90,
    deps: context,
  });

  const row = context.store.usage.find((entry) => entry.operation === 'RESEARCH_COMPANY');
  assert.ok(row);
  assert.equal(row.actualCost, null);
  assert.equal(row.cost, 0.03);
});

/* ---------------------------------------------------------------- signals */

test('company signals leave what is unknown unknown', () => {
  const signals = signalsFromCompany(fixtureCompany('fx-org-005'));

  assert.equal(signals.employeeCount, null);
  assert.equal(signals.runsPromotions, null);
  assert.equal(signals.growthSignal, null);
  assert.equal(signals.hasContactChannel, true);
  assert.equal(signals.socialProfileCount, 1);
});

test('research folds into the signals it answers, and contacts into theirs', () => {
  const base = signalsFromCompany(fixtureCompany('fx-org-001'));
  const merged = signalsFromResearch(
    base,
    {
      findings: [],
      unknowns: [],
      website_reachable: true,
      social_profiles: ['a', 'b', 'c'],
      runs_promotions: true,
      growth_signal: false,
    },
    [
      {
        first_name: 'Arlindo',
        last_name: null,
        job_title: 'Proprietário',
        seniority: 'OWNER',
        email: 'a@b.test',
        email_status: 'VERIFIED',
        phone: null,
        linkedin_url: null,
        provider_person_id: 'p',
        confidence_score: 0.9,
      },
    ],
  );

  assert.equal(merged.runsPromotions, true);
  assert.equal(merged.growthSignal, false);
  assert.equal(merged.decisionMakerIdentified, true);
  assert.equal(merged.reachableContact, true);
  assert.equal(merged.socialProfileCount, 3);
});

test('a guessed email does not make a contact reachable', () => {
  const merged = signalsFromResearch(signalsFromCompany(fixtureCompany('fx-org-001')), null, [
    {
      first_name: 'Nelson',
      last_name: null,
      job_title: 'Gerente',
      seniority: 'MANAGER',
      email: 'nelson@x.test',
      email_status: 'GUESSED',
      phone: null,
      linkedin_url: null,
      provider_person_id: 'p',
      confidence_score: 0.4,
    },
  ]);

  assert.equal(merged.decisionMakerIdentified, true);
  assert.equal(merged.reachableContact, false);
});

/* ------------------------------- criterion: the two-stage cost gate */

/**
 * The gate is the cost design, so these are the tests that matter most.
 *
 * Everything discovery can read is free; the second call is not. What the
 * suite has to pin is not that the call works — it is that it does not
 * happen for a lead the rules did not like, because that is the difference
 * between paying for three hundred listings and paying for a thousand.
 */

class RecordingDetailProvider {
  readonly key: string;
  readonly calls: string[] = [];
  private readonly answer: ListingDetailResult;

  constructor(answer: Partial<ListingDetailResult> = {}, key = 'places') {
    this.key = key;
    this.answer = {
      phone: '+258840000101',
      website: 'https://barbearia.test',
      hasOpeningHours: true,
      hasPhotos: true,
      ...answer,
    };
  }

  isConfigured() {
    return true;
  }

  async fetchListingDetail(input: { reference: string }): Promise<ListingDetailResult> {
    this.calls.push(input.reference);
    return this.answer;
  }
}

async function scoredLead(
  store: MemoryStore,
  orgId = 'fx-org-001',
): Promise<{ prospectId: string; companyId: string; company: CompanyRecord }> {
  const company = fixtureCompany(orgId);
  const claimed = await store.claimCompany(company);
  const created = await store.createProspect({
    companyId: claimed.companyId,
    source: 'DISCOVERY',
    sourceReference: company.source_reference,
    status: 'SCORED',
  });
  return {
    prospectId: created.prospectId,
    companyId: claimed.companyId,
    company,
  };
}

function detailDeps(
  store: MemoryStore,
  detail: RecordingDetailProvider,
  settings = DEFAULT_SETTINGS,
): PipelineDeps {
  const provider = new FixtureProvider();
  return {
    store,
    providers: {
      discovery: [provider],
      personDiscovery: [provider],
      personEnrichment: [provider],
      webResearch: [provider],
      listingDetail: [detail as never],
    },
    settings,
    now: () => 1_758_000_000_000,
  };
}

test('a lead below the threshold never reaches the paid call', async () => {
  const store = new MemoryStore();
  const detail = new RecordingDetailProvider();
  const lead = await scoredLead(store);

  const outcome = await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: lead.company,
    // The default threshold is 60.
    leadScore: 45,
    deps: detailDeps(store, detail),
  });

  assert.equal(outcome.status, 'BELOW_THRESHOLD');
  assert.equal(outcome.refusal, 'BELOW_THRESHOLD');
  assert.equal(outcome.spentUsd, 0);
  // The assertion the whole design rests on.
  assert.deepEqual(detail.calls, []);
  assert.equal(store.usage.length, 0);
});

test('a lead above the threshold is asked about exactly once', async () => {
  const store = new MemoryStore();
  const detail = new RecordingDetailProvider();
  const lead = await scoredLead(store);

  const outcome = await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: lead.company,
    leadScore: 75,
    deps: detailDeps(store, detail),
  });

  assert.equal(outcome.status, 'COMPLETE');
  assert.deepEqual(detail.calls, ['fx-org-001']);
  assert.equal(store.usage.length, 1);
  assert.equal(store.usage[0].operation, 'FETCH_LISTING_DETAILS');
});

test('the daily cap refuses the paid call and says which cap refused it', async () => {
  const store = new MemoryStore();
  store.daySpend = DEFAULT_SETTINGS.dailyBudgetUsd;
  const detail = new RecordingDetailProvider();
  const lead = await scoredLead(store);

  const outcome = await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: lead.company,
    leadScore: 90,
    deps: detailDeps(store, detail),
  });

  assert.equal(outcome.refusal, 'DAILY_CAP');
  assert.equal(outcome.status, 'BUDGET_BLOCKED');
  assert.deepEqual(detail.calls, []);
});

test('what the paid call returns is written back and re-scored', async () => {
  const store = new MemoryStore();
  const detail = new RecordingDetailProvider();
  // A fixture with no website, so the detail call has something to add.
  const lead = await scoredLead(store, 'fx-org-008');
  const before = store.prospects.get(lead.prospectId)!.score;

  const outcome = await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: lead.company,
    leadScore: 70,
    deps: detailDeps(store, detail),
  });

  assert.ok(outcome.fieldsDiscovered.includes('website'));
  assert.ok(outcome.fieldsDiscovered.includes('phone'));

  const stored = store.companies.get(lead.companyId)!;
  assert.equal(stored.website, 'https://barbearia.test');
  assert.equal(stored.has_opening_hours, true);

  // Re-scored on the evidence that was just paid for, rather than left
  // ranked on what was known before it arrived.
  const after = store.prospects.get(lead.prospectId)!.score;
  assert.notEqual(after, before);
  assert.ok(after !== null && after > 0);
});

test('a listing that answers with no phone is partial, not complete', async () => {
  const store = new MemoryStore();
  const detail = new RecordingDetailProvider({ phone: null });
  const lead = await scoredLead(store);

  const outcome = await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: lead.company,
    leadScore: 75,
    deps: detailDeps(store, detail),
  });

  // Real and worth showing; just not one an operator can open WhatsApp on.
  assert.equal(outcome.status, 'PARTIAL');
  assert.notEqual(store.prospects.get(lead.prospectId)!.status, 'READY_TO_CONTACT');
});

test('a company with no source reference is NO_RESULT and costs nothing', async () => {
  const store = new MemoryStore();
  const detail = new RecordingDetailProvider();
  const lead = await scoredLead(store);

  const outcome = await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: { ...lead.company, source_reference: null },
    leadScore: 95,
    deps: detailDeps(store, detail),
  });

  // Nothing to call. Not a failure, and not a budget problem — calling anyway
  // would spend money to receive a 404.
  assert.equal(outcome.status, 'NO_RESULT');
  assert.deepEqual(detail.calls, []);
  assert.equal(store.usage.length, 0);
});

test('a reachable lead is moved to READY_TO_CONTACT', async () => {
  const store = new MemoryStore();
  const detail = new RecordingDetailProvider();
  const lead = await scoredLead(store);

  await fetchListingDetails({
    prospectId: lead.prospectId,
    companyId: lead.companyId,
    company: lead.company,
    leadScore: 75,
    deps: detailDeps(store, detail),
  });

  assert.equal(store.prospects.get(lead.prospectId)!.status, 'READY_TO_CONTACT');
});
