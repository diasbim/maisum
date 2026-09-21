"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_pipeline_js_1 = require("./prospecting_pipeline.js");
const prospecting_provider_fixtures_js_1 = require("./prospecting_provider_fixtures.js");
const prospecting_normalization_js_1 = require("./prospecting_normalization.js");
/**
 * The whole pipeline over a map.
 *
 * `MemoryStore` is the real dedup rule — the same lookup-key claim the
 * Firestore store implements — over a JavaScript `Map`. That is what makes
 * criterion 9 provable here rather than only in an emulator: the property
 * being tested is that two spellings of one business claim the same key, and
 * the key is computed by the same function in both implementations.
 */
class MemoryStore {
    constructor() {
        this.companies = new Map();
        this.lookup = new Map();
        this.prospects = new Map();
        this.contacts = [];
        this.activities = [];
        this.usage = [];
        /** Existing MaisUm merchants, as `businesses` documents would be. */
        this.merchants = [];
        this.monthSpend = 0;
        this.daySpend = 0;
        this.nextId = 1;
    }
    async claimCompany(company) {
        const keys = (0, prospecting_normalization_js_1.buildMatchKeys)({
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
        }, prospecting_config_js_1.DEFAULT_SETTINGS.geography.phoneCountryCode);
        let companyId = null;
        let matchedOn = null;
        for (const key of keys) {
            const found = this.lookup.get((0, prospecting_normalization_js_1.matchKeyDocId)(key));
            if (found !== undefined) {
                companyId = found;
                matchedOn = key;
                break;
            }
        }
        const created = companyId === null;
        const id = companyId ?? `company_${this.nextId++}`;
        for (const key of keys)
            this.lookup.set((0, prospecting_normalization_js_1.matchKeyDocId)(key), id);
        if (created) {
            this.companies.set(id, company);
        }
        else {
            const existing = this.companies.get(id);
            if (existing !== undefined) {
                // Fills gaps, never overwrites with a null.
                const merged = { ...existing };
                for (const [field, value] of Object.entries(company)) {
                    if (value !== null && value !== undefined) {
                        merged[field] = value;
                    }
                }
                this.companies.set(id, merged);
            }
        }
        return { companyId: id, created, matchedOn };
    }
    async matchExistingCustomer(company) {
        const normalize = (value) => value === null ? null : value.replace(/\D/g, '');
        const fold = (value) => value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
        let nameMatch = null;
        for (const merchant of this.merchants) {
            const merchantPhone = normalize(merchant.phone);
            if (merchantPhone !== null &&
                (merchantPhone === normalize(company.phone) ||
                    merchantPhone === normalize(company.whatsapp))) {
                return { kind: 'PHONE', merchantId: merchant.id, merchantName: merchant.name };
            }
            if (nameMatch === null && fold(merchant.name) === fold(company.name)) {
                nameMatch = { kind: 'NAME', merchantId: merchant.id, merchantName: merchant.name };
            }
        }
        return nameMatch ?? { kind: 'NONE' };
    }
    async createProspect(input) {
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
    async saveScores(input) {
        const prospect = this.prospects.get(input.prospectId);
        if (prospect !== undefined)
            prospect.score = input.score.total;
    }
    async setStatus(input) {
        const prospect = this.prospects.get(input.prospectId);
        if (prospect !== undefined)
            prospect.status = input.to;
    }
    async setEnrichment(input) {
        const prospect = this.prospects.get(input.prospectId);
        if (prospect === undefined)
            return;
        prospect.enrichmentStatus = input.status;
        if (input.decisionMakerCount !== undefined) {
            prospect.decisionMakerCount = input.decisionMakerCount;
        }
        if (input.hasReachableContact !== undefined) {
            prospect.hasReachableContact = input.hasReachableContact;
        }
    }
    async saveContact(input) {
        this.contacts.push({
            prospectId: input.prospectId,
            name: input.person.first_name,
            isDecisionMaker: input.isDecisionMaker,
        });
    }
    async updateCompanyListing(input) {
        const existing = this.companies.get(input.companyId);
        if (existing === undefined)
            return;
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
    async appendActivity(input) {
        this.activities.push({
            prospectId: input.prospectId,
            type: input.type,
            description: input.description,
        });
    }
    async recordUsage(input) {
        this.usage.push({
            provider: input.provider,
            operation: input.operation,
            success: input.success,
            errorCode: input.errorCode,
            cost: input.estimatedCostUsd,
            actualCost: input.actualCostUsd ?? null,
            prospectId: input.prospectId,
        });
        this.monthSpend = Math.round((this.monthSpend + input.estimatedCostUsd) * 10000) / 10000;
        this.daySpend = Math.round((this.daySpend + input.estimatedCostUsd) * 10000) / 10000;
        if (input.prospectId !== null) {
            const prospect = this.prospects.get(input.prospectId);
            if (prospect !== undefined) {
                prospect.spendUsd =
                    Math.round((prospect.spendUsd + input.estimatedCostUsd) * 10000) / 10000;
            }
        }
    }
    async readSpend(prospectId) {
        return {
            monthUsd: this.monthSpend,
            dayUsd: this.daySpend,
            leadUsd: prospectId === null ? 0 : (this.prospects.get(prospectId)?.spendUsd ?? 0),
        };
    }
}
function deps(overrides = {}) {
    const store = overrides.store ?? new MemoryStore();
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    return {
        store,
        providers: {
            discovery: [provider],
            personDiscovery: [provider],
            personEnrichment: [provider],
            webResearch: [provider],
            listingDetail: [],
        },
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        now: () => 1758000000000,
        ...overrides,
        // Keep the concrete store on the returned object for assertions.
        ...(overrides.store === undefined ? {} : { store }),
    };
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
function fixtureCompany(orgId) {
    const fixture = prospecting_provider_fixtures_js_1.COMPANY_FIXTURES.find((entry) => entry.provider_org_id === orgId);
    strict_1.default.ok(fixture, `no fixture ${orgId}`);
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
        source: 'fixtures',
        source_reference: orgId,
    };
}
/* ----------------------------------------------- criterion 9: duplicates */
(0, node_test_1.default)('the same business discovered twice produces one company', async () => {
    const context = deps();
    const first = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    const second = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(first.created, true);
    strict_1.default.equal(second.created, false);
    strict_1.default.equal(first.companyId, second.companyId);
    strict_1.default.equal(context.store.companies.size, 1);
    strict_1.default.equal(context.store.prospects.size, 1);
});
(0, node_test_1.default)('two spellings of one business produce one company', async () => {
    // fx-org-020 is fx-org-001 written the way a second provider would write it:
    // a scheme and a www, the legal suffix attached, the phone spaced out.
    const context = deps();
    const first = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    const second = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-020'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(second.created, false);
    strict_1.default.equal(first.companyId, second.companyId);
    strict_1.default.equal(context.store.companies.size, 1);
});
(0, node_test_1.default)('a whole discovery run stores no duplicate companies', async () => {
    const context = deps();
    await (0, prospecting_pipeline_js_1.runDiscoveryBatch)({
        criteria: { ...CRITERIA, industries: [] },
        cursor: null,
        batchSize: 100,
        deps: context,
    });
    // Twenty fixtures, less the one whose trade is outside the ICP — an empty
    // industry list means every ICP industry, not every business on earth, so
    // the workshop is never searched for. Of the nineteen that come back, two
    // are the same business written two ways.
    strict_1.default.equal(context.store.companies.size, 18);
    const companyIds = [...context.store.lookup.values()];
    strict_1.default.equal(new Set(companyIds).size, 18);
});
(0, node_test_1.default)('a second sighting fills gaps without erasing what was known', async () => {
    const context = deps();
    await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    // The duplicate has no Instagram URL; the original does. A plain merge of
    // the new record would null it out.
    await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-020'),
        criteria: CRITERIA,
        deps: context,
    });
    const stored = [...context.store.companies.values()][0];
    strict_1.default.ok(stored.instagram_url, 'the known Instagram URL was erased');
    strict_1.default.equal(stored.legal_name, 'Barbearia Exemplo Central Lda');
});
/* ------------------------------------------ criterion 10: real customers */
(0, node_test_1.default)('a business whose phone matches a merchant is never a lead', async () => {
    const context = deps();
    context.store.merchants = [
        { id: 'merchant_1', name: 'Outro Nome Qualquer', phone: '+258840000101' },
    ];
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(result.status, 'EXISTING_CUSTOMER');
    strict_1.default.equal(result.qualified, false);
    strict_1.default.equal(result.score, null);
    const prospect = context.store.prospects.get(result.prospectId);
    strict_1.default.equal(prospect?.status, 'EXISTING_CUSTOMER');
    strict_1.default.equal(prospect?.suspectedMerchantId, 'merchant_1');
});
(0, node_test_1.default)('a phone match wins over the trade and the city', async () => {
    // An existing customer is recognised as one whatever else is true.
    const context = deps();
    context.store.merchants = [
        { id: 'merchant_1', name: 'Oficina Exemplo Motor', phone: '+258840000118' },
    ];
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-018'),
        criteria: CRITERIA,
        deps: context,
    });
    // Would otherwise have been NOT_A_FIT on the trade.
    strict_1.default.equal(result.status, 'EXISTING_CUSTOMER');
});
(0, node_test_1.default)('a name-only match is flagged for a person, not made terminal', async () => {
    // `businesses` stores no city, so a name match has nothing to disambiguate
    // it. EXISTING_CUSTOMER is terminal and terminal is irreversible, and a name
    // collision must not be able to kill a real lead permanently.
    const context = deps();
    context.store.merchants = [
        { id: 'merchant_9', name: 'Barbearia Exemplo Central', phone: '+258999999999' },
    ];
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(result.status, 'SCORED');
    const prospect = context.store.prospects.get(result.prospectId);
    strict_1.default.equal(prospect?.suspectedMerchantId, 'merchant_9');
});
/* ---------------------------------------------------------- qualification */
(0, node_test_1.default)('a business outside the ICP is stored as NOT_A_FIT with the reason', async () => {
    const context = deps();
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-018'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(result.status, 'NOT_A_FIT');
    strict_1.default.equal(context.store.prospects.get(result.prospectId)?.disqualifyReason, 'NOT_TARGET_INDUSTRY');
});
(0, node_test_1.default)('a business outside the geography is stored as NOT_A_FIT with the reason', async () => {
    const context = deps();
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-019'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(result.status, 'NOT_A_FIT');
    strict_1.default.equal(context.store.prospects.get(result.prospectId)?.disqualifyReason, 'OUT_OF_GEOGRAPHY');
});
(0, node_test_1.default)('widening the configured cities is all it takes to qualify Beira', async () => {
    const context = deps({
        settings: {
            ...prospecting_config_js_1.DEFAULT_SETTINGS,
            geography: {
                ...prospecting_config_js_1.DEFAULT_SETTINGS.geography,
                cities: [...prospecting_config_js_1.DEFAULT_SETTINGS.geography.cities, 'Beira'],
                provinces: [...prospecting_config_js_1.DEFAULT_SETTINGS.geography.provinces, 'Sofala'],
            },
        },
    });
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-019'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(result.status, 'SCORED');
});
(0, node_test_1.default)('the pipeline runs in the fixed order, and the trail evidences it', async () => {
    const context = deps();
    const result = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    strict_1.default.equal(result.status, 'SCORED');
    strict_1.default.ok(result.score);
    strict_1.default.ok(result.score.total > 0);
    const types = context.store.activities.map((entry) => entry.type);
    strict_1.default.deepEqual(types, ['DISCOVERED']);
});
/* ------------------------------------------------ criterion 11: the cap */
(0, node_test_1.default)('enrichment stops at the monthly cap and says which cap stopped it', async () => {
    const context = deps();
    context.store.monthSpend = 49.99;
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-001'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(outcome.refusal, 'MONTHLY_CAP');
    strict_1.default.equal(outcome.status, 'BUDGET_BLOCKED');
    strict_1.default.equal(outcome.contactsFound, 0);
    // Nothing was called, so nothing was charged.
    strict_1.default.equal(context.store.usage.some((row) => row.operation === 'FIND_DECISION_MAKERS'), false);
});
(0, node_test_1.default)('a blocked budget is a state of its own, not a failure', async () => {
    const context = deps();
    context.store.monthSpend = 50;
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-001'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(context.store.prospects.get(stored.prospectId)?.enrichmentStatus, 'BUDGET_BLOCKED');
});
(0, node_test_1.default)('a lead below the threshold is never paid for', async () => {
    const context = deps();
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-015'),
        criteria: CRITERIA,
        deps: context,
    });
    const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-015'),
        leadScore: 40,
        deps: context,
    });
    strict_1.default.equal(outcome.refusal, 'BELOW_THRESHOLD');
    strict_1.default.equal(outcome.status, 'BELOW_THRESHOLD');
    strict_1.default.equal(context.store.usage.length, 0);
});
(0, node_test_1.default)('the per-lead cap stops one lead without stopping the rest', async () => {
    const context = deps();
    const first = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    const prospect = context.store.prospects.get(first.prospectId);
    strict_1.default.ok(prospect);
    prospect.spendUsd = 0.49;
    const blocked = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: first.prospectId,
        company: fixtureCompany('fx-org-001'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(blocked.refusal, 'PER_LEAD_CAP');
    const second = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-003'),
        criteria: CRITERIA,
        deps: context,
    });
    const allowed = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: second.prospectId,
        company: fixtureCompany('fx-org-003'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(allowed.refusal, null);
});
/* -------------------------------------------------------------- enrichment */
(0, node_test_1.default)('a decision maker is found, enriched and stored', async () => {
    const context = deps();
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-001'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(outcome.status, 'COMPLETE');
    strict_1.default.equal(outcome.decisionMakersFound, 1);
    strict_1.default.equal(context.store.contacts.length, 1);
    strict_1.default.equal(context.store.contacts[0].name, 'Arlindo');
    strict_1.default.equal(context.store.contacts[0].isDecisionMaker, true);
    strict_1.default.ok(outcome.spentUsd > 0);
});
(0, node_test_1.default)('a company with no decision maker records NO_RESULT, so it is not paid for twice', async () => {
    const context = deps();
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-007'),
        criteria: CRITERIA,
        deps: context,
    });
    const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-007'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(outcome.status, 'NO_RESULT');
    strict_1.default.equal(outcome.decisionMakersFound, 0);
    strict_1.default.equal(context.store.prospects.get(stored.prospectId)?.enrichmentStatus, 'NO_RESULT');
});
(0, node_test_1.default)('a contact who is not a decision maker is stored but not counted as one', async () => {
    const context = deps();
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-002'),
        criteria: CRITERIA,
        deps: context,
    });
    const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-002'),
        leadScore: 90,
        deps: context,
    });
    strict_1.default.equal(context.store.contacts.length, 1);
    strict_1.default.equal(context.store.contacts[0].isDecisionMaker, false);
    strict_1.default.equal(outcome.decisionMakersFound, 0);
    strict_1.default.equal(outcome.status, 'NO_RESULT');
});
(0, node_test_1.default)('a decision maker with no way to reach them is PARTIAL, not COMPLETE', async () => {
    // fx-per-002 has a verified email, so use one whose only contact is a
    // LinkedIn URL by stripping what the fixture returns.
    const context = deps();
    const emptyEnrichment = new prospecting_provider_fixtures_js_1.FixtureProvider({ key: 'no-enrichment', empty: true });
    const discovery = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const scoped = {
        ...context,
        providers: {
            discovery: [discovery],
            personDiscovery: [discovery],
            personEnrichment: [emptyEnrichment],
            webResearch: [discovery],
            listingDetail: [],
        },
    };
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-010'),
        criteria: CRITERIA,
        deps: scoped,
    });
    const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-010'),
        leadScore: 90,
        deps: scoped,
    });
    // The fixture person already carries a verified email from discovery, so
    // this stays COMPLETE — what is asserted is that a failed enrichment does
    // not erase what discovery already knew.
    strict_1.default.equal(outcome.status, 'COMPLETE');
    strict_1.default.equal(context.store.contacts.length, 1);
});
/* ------------------------------------------------------------- the chain */
(0, node_test_1.default)('a provider outage falls through and the failed attempt is still charged', async () => {
    const store = new MemoryStore();
    const broken = new prospecting_provider_fixtures_js_1.FixtureProvider({ key: 'broken', failWith: 'UNAVAILABLE' });
    const working = new prospecting_provider_fixtures_js_1.FixtureProvider({ key: 'working' });
    const context = {
        store,
        providers: {
            discovery: [broken, working],
            personDiscovery: [broken, working],
            personEnrichment: [working],
            webResearch: [working],
            listingDetail: [],
        },
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        now: () => 1758000000000,
    };
    const outcome = await (0, prospecting_pipeline_js_1.runDiscoveryBatch)({
        criteria: { ...CRITERIA, industries: ['barbershop'] },
        cursor: null,
        batchSize: 10,
        deps: context,
    });
    strict_1.default.ok(outcome.discovered > 0);
    const search = store.usage.filter((row) => row.operation === 'SEARCH_BUSINESSES');
    strict_1.default.equal(search.length, 2);
    strict_1.default.equal(search[0].success, false);
    strict_1.default.equal(search[0].provider, 'broken');
    strict_1.default.equal(search[1].success, true);
});
(0, node_test_1.default)('a provider that is not configured costs nothing at all', async () => {
    const store = new MemoryStore();
    const unconfigured = {
        key: 'unconfigured',
        isConfigured: () => false,
        searchBusinesses: async () => {
            throw new Error('should never be called');
        },
    };
    const working = new prospecting_provider_fixtures_js_1.FixtureProvider({ key: 'working' });
    const context = {
        store,
        providers: {
            discovery: [unconfigured, working],
            personDiscovery: [working],
            personEnrichment: [working],
            webResearch: [working],
            listingDetail: [],
        },
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        now: () => 1758000000000,
    };
    await (0, prospecting_pipeline_js_1.runDiscoveryBatch)({
        criteria: CRITERIA,
        cursor: null,
        batchSize: 5,
        deps: context,
    });
    strict_1.default.equal(store.usage.some((row) => row.provider === 'unconfigured'), false);
});
(0, node_test_1.default)('running out of results is the ordinary end of a search, not a failure', async () => {
    const store = new MemoryStore();
    const empty = new prospecting_provider_fixtures_js_1.FixtureProvider({ key: 'empty', empty: true });
    const context = {
        store,
        providers: {
            discovery: [empty],
            personDiscovery: [empty],
            personEnrichment: [empty],
            webResearch: [empty],
            listingDetail: [],
        },
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        now: () => 1758000000000,
    };
    const outcome = await (0, prospecting_pipeline_js_1.runDiscoveryBatch)({
        criteria: CRITERIA,
        cursor: null,
        batchSize: 10,
        deps: context,
    });
    strict_1.default.equal(outcome.fatalCode, null);
    strict_1.default.equal(outcome.cursor, null);
    strict_1.default.equal(outcome.discovered, 0);
});
(0, node_test_1.default)('discovery is refused outright when the budget is gone', async () => {
    const context = deps();
    context.store.monthSpend = 50;
    const outcome = await (0, prospecting_pipeline_js_1.runDiscoveryBatch)({
        criteria: CRITERIA,
        cursor: null,
        batchSize: 10,
        deps: context,
    });
    strict_1.default.equal(outcome.fatalCode, 'MONTHLY_CAP');
    strict_1.default.equal(outcome.discovered, 0);
    strict_1.default.equal(context.store.usage.length, 0);
});
/* ------------------------------------------------------- reported costs */
(0, node_test_1.default)('a provider that reports its price has it recorded as the actual cost', async () => {
    // AIsa states what it charged through `X-AISA-Price-USD`. That figure must
    // reach the usage row, because it is the one thing in the month's total
    // that is not a guess.
    const store = new MemoryStore();
    const reporting = Object.assign(new prospecting_provider_fixtures_js_1.FixtureProvider({ key: 'aisa' }), {
        lastCostUsd: 0.0184,
        estimatedCostUsd: () => 0.012,
    });
    const context = {
        store,
        providers: {
            discovery: [reporting],
            personDiscovery: [reporting],
            personEnrichment: [reporting],
            webResearch: [reporting],
            listingDetail: [],
        },
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        now: () => 1758000000000,
    };
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    await (0, prospecting_pipeline_js_1.researchCompany)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-001'),
        leadScore: 90,
        deps: context,
    });
    const row = store.usage.find((entry) => entry.operation === 'RESEARCH_COMPANY');
    strict_1.default.ok(row);
    strict_1.default.equal(row.actualCost, 0.0184);
    // Its own pre-authorisation figure, not the table rate.
    strict_1.default.equal(row.cost, 0.012);
});
(0, node_test_1.default)('a provider that reports nothing leaves the actual cost null', async () => {
    // Which is what makes the console label the month "estimado".
    const context = deps();
    const stored = await (0, prospecting_pipeline_js_1.storeDiscovered)({
        company: fixtureCompany('fx-org-001'),
        criteria: CRITERIA,
        deps: context,
    });
    await (0, prospecting_pipeline_js_1.researchCompany)({
        prospectId: stored.prospectId,
        company: fixtureCompany('fx-org-001'),
        leadScore: 90,
        deps: context,
    });
    const row = context.store.usage.find((entry) => entry.operation === 'RESEARCH_COMPANY');
    strict_1.default.ok(row);
    strict_1.default.equal(row.actualCost, null);
    strict_1.default.equal(row.cost, 0.03);
});
/* ---------------------------------------------------------------- signals */
(0, node_test_1.default)('company signals leave what is unknown unknown', () => {
    const signals = (0, prospecting_pipeline_js_1.signalsFromCompany)(fixtureCompany('fx-org-005'));
    strict_1.default.equal(signals.employeeCount, null);
    strict_1.default.equal(signals.runsPromotions, null);
    strict_1.default.equal(signals.growthSignal, null);
    strict_1.default.equal(signals.hasContactChannel, true);
    strict_1.default.equal(signals.socialProfileCount, 1);
});
(0, node_test_1.default)('research folds into the signals it answers, and contacts into theirs', () => {
    const base = (0, prospecting_pipeline_js_1.signalsFromCompany)(fixtureCompany('fx-org-001'));
    const merged = (0, prospecting_pipeline_js_1.signalsFromResearch)(base, {
        findings: [],
        unknowns: [],
        website_reachable: true,
        social_profiles: ['a', 'b', 'c'],
        runs_promotions: true,
        growth_signal: false,
    }, [
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
    ]);
    strict_1.default.equal(merged.runsPromotions, true);
    strict_1.default.equal(merged.growthSignal, false);
    strict_1.default.equal(merged.decisionMakerIdentified, true);
    strict_1.default.equal(merged.reachableContact, true);
    strict_1.default.equal(merged.socialProfileCount, 3);
});
(0, node_test_1.default)('a guessed email does not make a contact reachable', () => {
    const merged = (0, prospecting_pipeline_js_1.signalsFromResearch)((0, prospecting_pipeline_js_1.signalsFromCompany)(fixtureCompany('fx-org-001')), null, [
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
    strict_1.default.equal(merged.decisionMakerIdentified, true);
    strict_1.default.equal(merged.reachableContact, false);
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
    constructor(answer = {}, key = 'places') {
        this.calls = [];
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
    async fetchListingDetail(input) {
        this.calls.push(input.reference);
        return this.answer;
    }
}
async function scoredLead(store, orgId = 'fx-org-001') {
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
function detailDeps(store, detail, settings = prospecting_config_js_1.DEFAULT_SETTINGS) {
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    return {
        store,
        providers: {
            discovery: [provider],
            personDiscovery: [provider],
            personEnrichment: [provider],
            webResearch: [provider],
            listingDetail: [detail],
        },
        settings,
        now: () => 1758000000000,
    };
}
(0, node_test_1.default)('a lead below the threshold never reaches the paid call', async () => {
    const store = new MemoryStore();
    const detail = new RecordingDetailProvider();
    const lead = await scoredLead(store);
    const outcome = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: lead.company,
        // The default threshold is 60.
        leadScore: 45,
        deps: detailDeps(store, detail),
    });
    strict_1.default.equal(outcome.status, 'BELOW_THRESHOLD');
    strict_1.default.equal(outcome.refusal, 'BELOW_THRESHOLD');
    strict_1.default.equal(outcome.spentUsd, 0);
    // The assertion the whole design rests on.
    strict_1.default.deepEqual(detail.calls, []);
    strict_1.default.equal(store.usage.length, 0);
});
(0, node_test_1.default)('a lead above the threshold is asked about exactly once', async () => {
    const store = new MemoryStore();
    const detail = new RecordingDetailProvider();
    const lead = await scoredLead(store);
    const outcome = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: lead.company,
        leadScore: 75,
        deps: detailDeps(store, detail),
    });
    strict_1.default.equal(outcome.status, 'COMPLETE');
    strict_1.default.deepEqual(detail.calls, ['fx-org-001']);
    strict_1.default.equal(store.usage.length, 1);
    strict_1.default.equal(store.usage[0].operation, 'FETCH_LISTING_DETAILS');
});
(0, node_test_1.default)('the daily cap refuses the paid call and says which cap refused it', async () => {
    const store = new MemoryStore();
    store.daySpend = prospecting_config_js_1.DEFAULT_SETTINGS.dailyBudgetUsd;
    const detail = new RecordingDetailProvider();
    const lead = await scoredLead(store);
    const outcome = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: lead.company,
        leadScore: 90,
        deps: detailDeps(store, detail),
    });
    strict_1.default.equal(outcome.refusal, 'DAILY_CAP');
    strict_1.default.equal(outcome.status, 'BUDGET_BLOCKED');
    strict_1.default.deepEqual(detail.calls, []);
});
(0, node_test_1.default)('what the paid call returns is written back and re-scored', async () => {
    const store = new MemoryStore();
    const detail = new RecordingDetailProvider();
    // A fixture with no website, so the detail call has something to add.
    const lead = await scoredLead(store, 'fx-org-008');
    const before = store.prospects.get(lead.prospectId).score;
    const outcome = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: lead.company,
        leadScore: 70,
        deps: detailDeps(store, detail),
    });
    strict_1.default.ok(outcome.fieldsDiscovered.includes('website'));
    strict_1.default.ok(outcome.fieldsDiscovered.includes('phone'));
    const stored = store.companies.get(lead.companyId);
    strict_1.default.equal(stored.website, 'https://barbearia.test');
    strict_1.default.equal(stored.has_opening_hours, true);
    // Re-scored on the evidence that was just paid for, rather than left
    // ranked on what was known before it arrived.
    const after = store.prospects.get(lead.prospectId).score;
    strict_1.default.notEqual(after, before);
    strict_1.default.ok(after !== null && after > 0);
});
(0, node_test_1.default)('a listing that answers with no phone is partial, not complete', async () => {
    const store = new MemoryStore();
    const detail = new RecordingDetailProvider({ phone: null });
    const lead = await scoredLead(store);
    const outcome = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: lead.company,
        leadScore: 75,
        deps: detailDeps(store, detail),
    });
    // Real and worth showing; just not one an operator can open WhatsApp on.
    strict_1.default.equal(outcome.status, 'PARTIAL');
    strict_1.default.notEqual(store.prospects.get(lead.prospectId).status, 'READY_TO_CONTACT');
});
(0, node_test_1.default)('a company with no source reference is NO_RESULT and costs nothing', async () => {
    const store = new MemoryStore();
    const detail = new RecordingDetailProvider();
    const lead = await scoredLead(store);
    const outcome = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: { ...lead.company, source_reference: null },
        leadScore: 95,
        deps: detailDeps(store, detail),
    });
    // Nothing to call. Not a failure, and not a budget problem — calling anyway
    // would spend money to receive a 404.
    strict_1.default.equal(outcome.status, 'NO_RESULT');
    strict_1.default.deepEqual(detail.calls, []);
    strict_1.default.equal(store.usage.length, 0);
});
(0, node_test_1.default)('a reachable lead is moved to READY_TO_CONTACT', async () => {
    const store = new MemoryStore();
    const detail = new RecordingDetailProvider();
    const lead = await scoredLead(store);
    await (0, prospecting_pipeline_js_1.fetchListingDetails)({
        prospectId: lead.prospectId,
        companyId: lead.companyId,
        company: lead.company,
        leadScore: 75,
        deps: detailDeps(store, detail),
    });
    strict_1.default.equal(store.prospects.get(lead.prospectId).status, 'READY_TO_CONTACT');
});
