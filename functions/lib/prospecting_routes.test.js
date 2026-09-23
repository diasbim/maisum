"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_analysis_js_1 = require("./prospecting_analysis.js");
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_jobs_js_1 = require("./prospecting_jobs.js");
const prospecting_provider_fixtures_js_1 = require("./prospecting_provider_fixtures.js");
const prospecting_templates_js_1 = require("./prospecting_templates.js");
const prospecting_routes_js_1 = require("./prospecting_routes.js");
const prospecting_store_js_1 = require("./prospecting_store.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
class FakeRouter {
    constructor() {
        this.routes = [];
        this.middleware = [];
    }
    get(path, handler) {
        this.routes.push({ method: 'GET', path, handler });
    }
    post(path, handler) {
        this.routes.push({ method: 'POST', path, handler });
    }
    put(path, handler) {
        this.routes.push({ method: 'PUT', path, handler });
    }
    use(path, handler) {
        this.middleware.push({ path, handler });
    }
    find(method, path) {
        const found = this.routes.find((route) => route.method === method && route.path === path);
        strict_1.default.ok(found, `no route ${method} ${path}`);
        return found.handler;
    }
}
function fakeResponse() {
    let status = 200;
    let body = {};
    const res = {
        status(code) {
            status = code;
            return res;
        },
        json(payload) {
            body = payload;
            return res;
        },
    };
    return { res, answer: () => ({ status, body }) };
}
/* ------------------------------------------------------------- the double */
const NOW = 1758000000000;
const ANALYSIS_JSON = JSON.stringify({
    fitScore: 82,
    summary: 'Barbearia com clientes recorrentes.',
    evidence: [{ claim: 'Publica promoções', type: 'FACT', source: 'https://ig.test/x' }],
    unknowns: ['Número de clientes'],
    retentionOpportunity: 'Clientes mensais.',
    recommendedProduct: 'Fidelização',
    recommendedPitch: 'Bom dia...',
    recommendedChannel: 'WHATSAPP',
});
function company(overrides = {}) {
    return {
        id: 'company_1',
        name: 'Barbearia Exemplo',
        legal_name: null,
        domain: 'barbearia-exemplo.test',
        website: 'https://barbearia-exemplo.test',
        industry: 'barbershop',
        latitude: null,
        longitude: null,
        industry_raw: 'Barbearia',
        employee_count: 6,
        city: 'Maputo',
        province: 'Maputo Cidade',
        country: 'Moçambique',
        address: null,
        phone: '+258840000101',
        email: null,
        linkedin_url: null,
        instagram_url: 'https://instagram.com/x',
        facebook_url: null,
        whatsapp: '+258840000101',
        rating: 4.6,
        review_count: 87,
        has_opening_hours: true,
        has_photos: true,
        business_status: 'OPERATIONAL',
        source: 'fixtures',
        source_reference: 'fx-org-001',
        provider_org_id: 'fx-org-001',
        created_at: NOW,
        updated_at: NOW,
        ...overrides,
    };
}
function prospect(overrides = {}) {
    return {
        id: 'company_1',
        company_id: 'company_1',
        status: 'SCORED',
        source: 'DISCOVERY',
        source_reference: 'fx-org-001',
        lead_score: 75,
        business_fit_score: 35,
        digital_presence_score: 15,
        retention_potential_score: 15,
        commercial_opportunity_score: 10,
        band: 'GOOD',
        scoring_version: prospecting_config_js_1.SCORING_VERSION,
        furthest_stage: 2,
        outreach_template_id: null,
        ai_summary: null,
        ai_reasoning: null,
        recommended_pitch: null,
        recommended_channel: null,
        enrichment_status: 'NOT_STARTED',
        last_enriched_at: null,
        spend_usd: 0,
        decision_maker_count: 1,
        has_reachable_contact: true,
        suspected_merchant_id: null,
        disqualify_reason: null,
        status_source: 'system',
        status_changed_at: NOW,
        last_activity_at: NOW,
        created_at: NOW,
        updated_at: NOW,
        ...overrides,
    };
}
function contact(overrides = {}) {
    return {
        id: 'contact_1',
        prospect_id: 'company_1',
        first_name: 'Arlindo',
        last_name: null,
        job_title: 'Proprietário',
        seniority: 'OWNER',
        email: 'arlindo@barbearia-exemplo.test',
        email_status: 'VERIFIED',
        phone: null,
        linkedin_url: null,
        provider_person_id: 'fx-per-001',
        confidence_score: 0.9,
        is_decision_maker: true,
        created_at: NOW,
        updated_at: NOW,
        ...overrides,
    };
}
const llm = {
    key: 'test',
    model: 'test-model',
    isConfigured: () => true,
    complete: async (input) => input.system.includes('primeira mensagem')
        ? JSON.stringify({ subject: null, body: 'Bom dia. Reparei que...' })
        : ANALYSIS_JSON,
};
function harness(overrides = {}) {
    const router = new FakeRouter();
    const provider = new prospecting_provider_fixtures_js_1.FixtureProvider();
    const state = {
        prospects: new Map([['company_1', overrides.prospect ?? prospect()]]),
        contacts: [contact()],
        activities: [],
        analyses: overrides.analysisStored === undefined
            ? []
            : overrides.analysisStored === null
                ? []
                : [overrides.analysisStored],
        jobs: new Map(),
        audit: [],
        usage: [],
        scheduled: [],
        rateLimitAllows: true,
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        spend: { monthUsd: 0, dayUsd: 0, leadUsd: 0 },
        funnel: { reachedByStage: {}, exitsByStatus: {}, byBand: {}, byTemplate: {} },
    };
    let counter = 0;
    const deps = {
        adminRouter: router,
        auditActorFrom: () => ({
            appUserId: 'admin-1',
            firebaseUid: 'uid-1',
            role: 'ADMIN',
        }),
        respondServerError: (res, _operation, _error) => res
            .status(500)
            .json({ success: false, message: 'Server error' }),
        flags: () => ({
            prospectingEnabled: true,
            autoEnrichmentEnabled: false,
            outreachEnabled: true,
            apolloEnabled: false,
            aisaEnabled: false,
            placesEnabled: true,
            ...overrides.flags,
        }),
        readSettings: async () => state.settings,
        writeSettings: async ({ patch }) => {
            state.settings = { ...state.settings, ...patch };
            return state.settings;
        },
        pipelineDeps: (settings) => ({
            store: {
                claimCompany: async () => ({ companyId: 'company_1', created: false, matchedOn: null }),
                matchExistingCustomer: async () => ({ kind: 'NONE' }),
                createProspect: async () => ({ prospectId: 'company_1', created: false }),
                saveScores: async () => { },
                setStatus: async () => { },
                setEnrichment: async () => { },
                saveContact: async () => { },
                appendActivity: async () => { },
                recordUsage: async (input) => {
                    state.usage.push({ provider: input.provider, operation: input.operation });
                },
                updateCompanyListing: async () => { },
                readSpend: async () => state.spend,
            },
            providers: {
                discovery: [provider],
                personDiscovery: [provider],
                personEnrichment: [provider],
                webResearch: [provider],
                listingDetail: [],
            },
            settings,
            now: () => NOW,
        }),
        getProspect: async (id) => state.prospects.get(id) ?? null,
        getCompany: async (id) => (id === 'company_1' ? company() : null),
        listProspects: async (query) => {
            const all = [...state.prospects.values()].map((entry) => ({
                prospect: entry,
                company: company(),
            }));
            const page = all.slice(query.offset, query.offset + query.limit);
            return {
                rows: page,
                total: all.length,
                hasMore: query.offset + page.length < all.length,
                truncated: false,
            };
        },
        listContacts: async () => state.contacts,
        listActivities: async () => state.activities,
        latestAnalysis: async () => state.analyses[state.analyses.length - 1] ?? null,
        saveAnalysis: async (analysis) => {
            state.analyses.push(analysis);
        },
        setProspectStatus: async ({ prospectId, to }) => {
            const current = state.prospects.get(prospectId);
            strict_1.default.ok(current);
            if (!(0, prospecting_contracts_js_1.canTransition)(current.status, to)) {
                throw new prospecting_store_js_1.TransitionError(current.status, to);
            }
            const updated = { ...current, status: to };
            state.prospects.set(prospectId, updated);
            return updated;
        },
        saveScores: async () => { },
        appendActivity: async (input) => {
            state.activities.push({
                id: `a${counter++}`,
                prospect_id: input.prospectId,
                type: input.type,
                channel: input.channel ?? null,
                description: input.description,
                metadata: input.metadata ?? {},
                created_at: NOW,
                created_by: input.actor,
            });
        },
        saveProspectAnalysisFields: async () => { },
        createJob: async (job) => {
            state.jobs.set(job.id, job);
        },
        getJob: async (id) => state.jobs.get(id) ?? null,
        cancelJob: async (id) => {
            const job = state.jobs.get(id);
            if (job === undefined)
                return null;
            const cancelled = { ...job, status: 'CANCELLED' };
            state.jobs.set(id, cancelled);
            return cancelled;
        },
        scheduleJob: async (id) => {
            state.scheduled.push(id);
        },
        readSpend: async () => state.spend,
        readFunnelCounts: async () => state.funnel,
        recordOutreachTemplate: async ({ prospectId, templateId }) => {
            const stored = state.prospects.get(prospectId);
            if (stored === undefined)
                throw new Error('prospect not found');
            // Set once, exactly as the store's transaction does: the first message
            // sent is the one that can have earned a reply.
            const existing = stored.outreach_template_id;
            if (existing !== null && existing !== '')
                return existing;
            state.prospects.set(prospectId, {
                ...stored,
                outreach_template_id: templateId,
            });
            return templateId;
        },
        listUsage: async () => ({ rows: [], hasMore: false }),
        analysisService: () => new prospecting_analysis_js_1.LeadAnalysisService(llm),
        outreachService: () => new prospecting_templates_js_1.TemplateOutreachService(),
        consumeRateLimit: async () => state.rateLimitAllows,
        newId: () => `id_${counter++}`,
        now: () => NOW,
    };
    (0, prospecting_routes_js_1.registerProspectingRoutes)(deps);
    return { router, deps, state };
}
async function call(handler, req = {}) {
    const { res, answer } = fakeResponse();
    await handler({ params: {}, query: {}, body: {}, ...req }, res);
    return answer();
}
/* -------------------------------------------------------- the flag gate */
(0, node_test_1.default)('every prospecting route sits behind one feature-flag gate', () => {
    const { router } = harness();
    const gate = router.middleware.find((entry) => entry.path === '/prospecting');
    strict_1.default.ok(gate, 'no middleware mounted on /prospecting');
    // Mounted on the prefix, not repeated per route: a route added later that
    // forgot the check would otherwise be a paid surface live in an
    // installation that never asked for it.
    strict_1.default.equal(router.middleware.length, 1);
});
(0, node_test_1.default)('the gate refuses with an explanation rather than a 404', async () => {
    const { router } = harness({ flags: { prospectingEnabled: false } });
    const gate = router.middleware[0].handler;
    const { res, answer } = fakeResponse();
    let nextCalled = false;
    await gate({}, res, () => {
        nextCalled = true;
    });
    strict_1.default.equal(nextCalled, false);
    strict_1.default.equal(answer().status, 403);
    strict_1.default.equal(answer().body.code, 'prospecting_disabled');
});
(0, node_test_1.default)('the gate lets a request through when the module is on', async () => {
    const { router } = harness();
    const gate = router.middleware[0].handler;
    let nextCalled = false;
    await gate({}, fakeResponse().res, () => {
        nextCalled = true;
    });
    strict_1.default.equal(nextCalled, true);
});
/* -------------------------------------------------------------- the list */
(0, node_test_1.default)('the list is paginated, and the envelope matches the console convention', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/leads'), {
        query: { limit: '10' },
    });
    strict_1.default.equal(answer.status, 200);
    strict_1.default.equal(answer.body.success, true);
    const pagingDto = answer.body.paging;
    strict_1.default.equal(pagingDto.limit, 10);
    strict_1.default.equal(pagingDto.offset, 0);
    strict_1.default.equal(pagingDto.has_more, false);
});
(0, node_test_1.default)('an absurd page size is clamped rather than served', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/leads'), {
        query: { limit: '100000' },
    });
    strict_1.default.equal(answer.body.paging.limit, 100);
});
(0, node_test_1.default)('a stale filter in a pasted URL is ignored, not refused', async () => {
    // A query string is something a person pastes into a chat and edits by
    // hand; answering a stale bookmark with a 400 is worse than answering it
    // with an unfiltered list.
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/leads'), {
        query: { status: 'NOT_A_REAL_STATUS', sort: 'nonsense' },
    });
    strict_1.default.equal(answer.status, 200);
});
(0, node_test_1.default)('a lead carries its label and its flags, not just its codes', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/leads'));
    const rows = answer.body.data;
    strict_1.default.equal(rows[0].name, 'Barbearia Exemplo');
    strict_1.default.equal(rows[0].status_label, 'Pontuado');
    strict_1.default.equal(rows[0].industry_label, 'Barbearia');
    strict_1.default.equal(rows[0].band_label, 'Bom');
});
/* ------------------------------------------------------------ the detail */
(0, node_test_1.default)('a missing lead is a 404 with a readable message', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
        params: { prospectId: 'nope' },
    });
    strict_1.default.equal(answer.status, 404);
    strict_1.default.equal(answer.body.code, 'prospect_not_found');
    strict_1.default.equal(answer.body.message, 'Lead não encontrado.');
});
(0, node_test_1.default)('an id that is not an id is refused before anything is read', async () => {
    const { router } = harness();
    for (const bad of ['../../etc', 'a/b', '', 'x'.repeat(200)]) {
        const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
            params: { prospectId: bad },
        });
        strict_1.default.equal(answer.status, 400, bad);
        strict_1.default.equal(answer.body.code, 'invalid_id');
    }
});
(0, node_test_1.default)('the detail carries the contact with its email marked usable or not', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
        params: { prospectId: 'company_1' },
    });
    const data = answer.body.data;
    const contacts = data.contacts;
    strict_1.default.equal(contacts[0].email_usable, true);
    strict_1.default.equal(contacts[0].email_status_label, 'Verificado');
    strict_1.default.equal(data.outreach_blocked, false);
    // SMS is dropped although the lead is reachable on it: there is no SMS
    // template, and offering the channel would send the operator down a dead
    // end. Add one and it comes back with no change here.
    strict_1.default.deepEqual(data.available_channels, ['WHATSAPP', 'EMAIL']);
});
(0, node_test_1.default)('a guessed email is carried but not marked usable', async () => {
    const { router, state } = harness();
    state.contacts = [contact({ email: 'guess@x.test', email_status: 'GUESSED' })];
    const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
        params: { prospectId: 'company_1' },
    });
    const contacts = answer.body.data.contacts;
    strict_1.default.equal(contacts[0].email, 'guess@x.test');
    strict_1.default.equal(contacts[0].email_usable, false);
    strict_1.default.equal(contacts[0].email_status_label, 'Estimado');
});
/* ------------------------------------------------------------- the search */
(0, node_test_1.default)('a search validates every field and names the one that failed', async () => {
    const { router } = harness();
    const handler = router.find('POST', '/prospecting/search');
    const cases = [
        [{ industries: ['mining'], maxLeads: 50, minScore: 60 }, 'invalid_industries'],
        [{ industries: [], maxLeads: 37, minScore: 60 }, 'invalid_max_leads'],
        [{ industries: [], maxLeads: 50, minScore: 55 }, 'invalid_min_score'],
        [{ industries: [], maxLeads: 50, minScore: 60, size: 'huge' }, 'invalid_size'],
        [{ industries: [], maxLeads: 50, minScore: 60, city: '<script>' }, 'invalid_location'],
    ];
    for (const [body, code] of cases) {
        const answer = await call(handler, { body });
        strict_1.default.equal(answer.status, 400, JSON.stringify(body));
        strict_1.default.equal(answer.body.code, code);
    }
});
(0, node_test_1.default)('a valid search returns a job id immediately and schedules the work', async () => {
    const { router, state } = harness();
    const answer = await call(router.find('POST', '/prospecting/search'), {
        body: { industries: ['barbershop'], city: 'Maputo', maxLeads: 50, minScore: 60 },
    });
    strict_1.default.equal(answer.status, 202);
    const job = answer.body.data;
    strict_1.default.equal(job.status, 'QUEUED');
    strict_1.default.equal(job.target, 50);
    strict_1.default.equal(job.progress_label, '0 / 50 negócios descobertos');
    strict_1.default.equal(state.scheduled.length, 1);
    strict_1.default.equal(state.scheduled[0], job.id);
});
(0, node_test_1.default)('a search is capped by the configured maximum', async () => {
    const { router, state } = harness();
    state.settings = { ...prospecting_config_js_1.DEFAULT_SETTINGS, maxProspectsPerSearch: 100 };
    const answer = await call(router.find('POST', '/prospecting/search'), {
        body: { industries: [], maxLeads: 500, minScore: 60 },
    });
    strict_1.default.equal(answer.body.data.target, 100);
});
(0, node_test_1.default)('an expensive endpoint is rate limited', async () => {
    const { router, state } = harness();
    state.rateLimitAllows = false;
    const answer = await call(router.find('POST', '/prospecting/search'), {
        body: { industries: [], maxLeads: 50, minScore: 60 },
    });
    strict_1.default.equal(answer.status, 429);
    strict_1.default.equal(answer.body.code, 'rate_limited');
    strict_1.default.equal(state.jobs.size, 0, 'no job should have been created');
});
/* -------------------------------------------------------------- estimate */
(0, node_test_1.default)('the estimate is a range and says the budget is what really caps it', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/estimate'), {
        query: { maxLeads: '100', minScore: '60' },
    });
    const data = answer.body.data;
    strict_1.default.ok(data.max_usd > data.min_usd);
    strict_1.default.equal(data.verified, false);
    strict_1.default.equal(data.monthly_budget_usd, 50);
    strict_1.default.equal(data.remaining_this_month_usd, 50);
});
(0, node_test_1.default)('what is left of the month subtracts what is already spent', async () => {
    const { router, state } = harness();
    state.spend.monthUsd = 12.5;
    const answer = await call(router.find('GET', '/prospecting/estimate'), {
        query: { maxLeads: '100', minScore: '60' },
    });
    const data = answer.body.data;
    strict_1.default.equal(data.remaining_this_month_usd, 37.5);
    // And nothing else in the same response says otherwise. The estimate used
    // to carry its own `remainingThisMonthUsd`, computed from the settings
    // alone, so it answered "50" beside the route's "37.5" — two numbers for
    // one question, the wrong one being the reassuring one.
    for (const [key, value] of Object.entries(data)) {
        if (/remaining/i.test(key))
            strict_1.default.equal(value, 37.5, key + ' disagrees');
    }
});
/* --------------------------------------------------------------- status */
(0, node_test_1.default)('a legal transition is applied and audited', async () => {
    const { router, state } = harness();
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
        params: { prospectId: 'company_1' },
        body: { status: 'READY_TO_CONTACT' },
    });
    strict_1.default.equal(answer.status, 200);
    strict_1.default.equal(state.prospects.get('company_1')?.status, 'READY_TO_CONTACT');
});
(0, node_test_1.default)('an illegal transition is a 409, not a silent no-op', async () => {
    const { router } = harness({ prospect: prospect({ status: 'CUSTOMER' }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
        params: { prospectId: 'company_1' },
        body: { status: 'RAW' },
    });
    strict_1.default.equal(answer.status, 409);
    strict_1.default.equal(answer.body.code, 'invalid_transition');
});
(0, node_test_1.default)('a status that is not in the vocabulary is a 400', async () => {
    const { router } = harness();
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
        params: { prospectId: 'company_1' },
        body: { status: 'WON' },
    });
    strict_1.default.equal(answer.status, 400);
    strict_1.default.equal(answer.body.code, 'invalid_status');
});
(0, node_test_1.default)('a terminal lead admits no transition at all', async () => {
    for (const terminal of ['DO_NOT_CONTACT', 'OPTED_OUT', 'EXISTING_CUSTOMER']) {
        const { router } = harness({ prospect: prospect({ status: terminal }) });
        const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
            params: { prospectId: 'company_1' },
            body: { status: 'CONTACTED' },
        });
        strict_1.default.equal(answer.status, 409, terminal);
    }
});
/* ------------------------------------------------- criterion 12: outreach */
(0, node_test_1.default)('outreach is refused for DO_NOT_CONTACT, and nothing is generated', async () => {
    const { router, state } = harness({ prospect: prospect({ status: 'DO_NOT_CONTACT' }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } });
    strict_1.default.equal(answer.status, 403);
    strict_1.default.equal(answer.body.code, 'outreach_blocked');
    strict_1.default.equal(state.activities.some((entry) => entry.type === 'OUTREACH_GENERATED'), false);
});
(0, node_test_1.default)('outreach is refused for OPTED_OUT too', async () => {
    const { router } = harness({ prospect: prospect({ status: 'OPTED_OUT' }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'EMAIL' } });
    strict_1.default.equal(answer.status, 403);
});
(0, node_test_1.default)('recording a sent message is refused for a blocked lead as well', async () => {
    // A guard on generation alone would still let a person log a message they
    // should never have sent.
    const { router, state } = harness({ prospect: prospect({ status: 'OPTED_OUT' }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/contact'), {
        params: { prospectId: 'company_1' },
        body: { channel: 'WHATSAPP' },
    });
    strict_1.default.equal(answer.status, 403);
    strict_1.default.equal(answer.body.code, 'outreach_blocked');
    strict_1.default.equal(state.activities.length, 0);
});
(0, node_test_1.default)('the outreach flag turns generation off without turning the module off', async () => {
    const { router } = harness({ flags: { outreachEnabled: false } });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } });
    strict_1.default.equal(answer.status, 403);
    strict_1.default.equal(answer.body.code, 'outreach_disabled');
});
(0, node_test_1.default)('a draft is generated, recorded as generated, and never as sent', async () => {
    const stored = {
        id: 'an_1',
        prospect_id: 'company_1',
        model: 'test-model',
        prompt_version: 3,
        data_hash: 'abc',
        scores: {},
        analysis: (0, prospecting_analysis_js_1.parseAnalysis)(ANALYSIS_JSON),
        recommended_pitch: 'Bom dia...',
        recommended_channel: 'WHATSAPP',
        created_at: NOW,
    };
    const { router, state } = harness({ analysisStored: stored });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } });
    strict_1.default.equal(answer.status, 200);
    const draft = answer.body.data;
    strict_1.default.equal(draft.channel, 'WHATSAPP');
    strict_1.default.equal(draft.locale, 'pt-MZ');
    const types = state.activities.map((entry) => entry.type);
    strict_1.default.ok(types.includes('OUTREACH_GENERATED'));
    strict_1.default.equal(types.includes('OUTREACH_SENT'), false);
});
(0, node_test_1.default)('a channel outside the four is refused', async () => {
    const { router } = harness();
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'PIGEON' } });
    strict_1.default.equal(answer.status, 400);
    strict_1.default.equal(answer.body.code, 'invalid_channel');
});
(0, node_test_1.default)('recording a sent message moves the lead and writes the timeline entry', async () => {
    const { router, state } = harness({ prospect: prospect({ status: 'READY_TO_CONTACT' }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/contact'), {
        params: { prospectId: 'company_1' },
        body: { channel: 'WHATSAPP', note: 'Enviei pelo telefone da loja.' },
    });
    strict_1.default.equal(answer.status, 200);
    strict_1.default.equal(state.prospects.get('company_1')?.status, 'CONTACTED');
    strict_1.default.equal(state.activities[0].type, 'OUTREACH_SENT');
    strict_1.default.equal(state.activities[0].description, 'Enviei pelo telefone da loja.');
});
/* -------------------------------------------------------------- analysis */
(0, node_test_1.default)('an analysis is generated, stored, and reported against the engine score', async () => {
    const { router, state } = harness();
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/analyze'), {
        params: { prospectId: 'company_1' },
    });
    strict_1.default.equal(answer.status, 200);
    const data = answer.body.data;
    strict_1.default.equal(data.from_cache, false);
    strict_1.default.equal(typeof data.engine_score, 'number');
    strict_1.default.equal(typeof data.score_divergence, 'number');
    strict_1.default.equal(state.analyses.length, 1);
    strict_1.default.ok(state.activities.some((entry) => entry.type === 'ANALYZED'));
});
(0, node_test_1.default)('a second analysis of unchanged data is served from the cache', async () => {
    const { router, state } = harness();
    const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');
    await call(handler, { params: { prospectId: 'company_1' } });
    const second = await call(handler, { params: { prospectId: 'company_1' } });
    strict_1.default.equal(second.body.data.from_cache, true);
    strict_1.default.equal(state.analyses.length, 1, 'a second analysis was stored');
});
(0, node_test_1.default)('a model call is charged like any other paid call', async () => {
    const { router, state } = harness();
    const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');
    await call(handler, { params: { prospectId: 'company_1' } });
    strict_1.default.deepEqual(state.usage, [{ provider: 'anthropic', operation: 'ANALYZE_LEAD' }]);
    // A cache hit calls nothing, so it charges nothing. A module that counted
    // the model's cost only when it happened to remember to would be spending
    // silently in the one place nobody was watching.
    await call(handler, { params: { prospectId: 'company_1' } });
    strict_1.default.equal(state.usage.length, 1);
});
(0, node_test_1.default)('an analysis is refused when the budget is gone', async () => {
    const { router, state } = harness();
    state.spend = { monthUsd: 50, dayUsd: 0, leadUsd: 0 };
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/analyze'), {
        params: { prospectId: 'company_1' },
    });
    strict_1.default.equal(answer.status, 402);
    strict_1.default.equal(answer.body.code, 'budget_exhausted');
    strict_1.default.equal(state.analyses.length, 0);
});
(0, node_test_1.default)('re-reading a cached analysis is never refused for budget', async () => {
    // A cache hit spends nothing, so an operator reopening yesterday's lead must
    // not be told the budget is gone for a request that would not have cost
    // anything.
    const { router, state } = harness();
    const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');
    await call(handler, { params: { prospectId: 'company_1' } });
    state.spend = { monthUsd: 50, dayUsd: 5, leadUsd: 0.5 };
    const second = await call(handler, { params: { prospectId: 'company_1' } });
    strict_1.default.equal(second.status, 200);
    strict_1.default.equal(second.body.data.from_cache, true);
});
/**
 * The inverse of what this test used to assert, and deliberately so.
 *
 * Generating a message used to call a model and was guarded like any other
 * paid call: budget gone, 402. A template render costs nothing, so there is no
 * cap to consult — and an operator whose month is spent must still be able to
 * write to the leads they already paid to find. Pinning it here means a future
 * change that puts a paid model back behind this route fails loudly rather
 * than quietly reintroducing a bill.
 */
(0, node_test_1.default)('generating outreach costs nothing and works with the budget exhausted', async () => {
    const { router, state } = harness();
    state.spend = { monthUsd: 50, dayUsd: 5, leadUsd: 0.5 };
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } });
    strict_1.default.equal(answer.status, 200);
    const data = answer.body.data;
    strict_1.default.equal(data.template_id ?? data.templateId, 'barbershop-whatsapp-v1');
    strict_1.default.ok(String(data.body).includes('Barbearia Exemplo'));
    // No usage row, because nothing was billable.
    strict_1.default.deepEqual(state.usage, []);
    strict_1.default.ok(state.activities.some((entry) => entry.type === 'OUTREACH_GENERATED'));
});
(0, node_test_1.default)('an analysis is no longer required to write to a lead', async () => {
    // The old route refused with 409 unless a stored analysis existed, because
    // the prompt was built from it. A template needs the company, not a model's
    // opinion of it.
    const { router } = harness({ analysisStored: null });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } });
    strict_1.default.equal(answer.status, 200);
});
(0, node_test_1.default)('the generated message records which template produced it', async () => {
    const { router, state } = harness();
    await call(router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'), { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } });
    const activity = state.activities.find((entry) => entry.type === 'OUTREACH_GENERATED');
    strict_1.default.ok(activity);
    // Without this, a second template version is unattributable and the A/B
    // measures nothing.
    strict_1.default.equal(activity.metadata.template_id, 'barbershop-whatsapp-v1');
});
(0, node_test_1.default)('force re-runs the analysis', async () => {
    const { router, state } = harness();
    const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');
    await call(handler, { params: { prospectId: 'company_1' } });
    const forced = await call(handler, {
        params: { prospectId: 'company_1' },
        body: { force: true },
    });
    strict_1.default.equal(forced.body.data.from_cache, false);
    strict_1.default.equal(state.analyses.length, 2);
});
/* -------------------------------------------------------------- settings */
(0, node_test_1.default)('settings are readable and carry the flags with them', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/settings'));
    const data = answer.body.data;
    strict_1.default.equal(data.monthly_budget_usd, 50);
    strict_1.default.equal(data.min_score_for_enrichment, 60);
    strict_1.default.deepEqual(data.flags.prospecting_enabled, true);
});
(0, node_test_1.default)('a budget that would empty an account is refused', async () => {
    const { router } = harness();
    const handler = router.find('PUT', '/prospecting/settings');
    for (const body of [
        { monthlyBudgetUsd: 1000000 },
        { monthlyBudgetUsd: -1 },
        { minScoreForEnrichment: 0 },
        { minScoreForEnrichment: 101 },
        { maxProspectsPerSearch: 0 },
    ]) {
        const answer = await call(handler, { body });
        strict_1.default.equal(answer.status, 400, JSON.stringify(body));
        strict_1.default.equal(answer.body.code, 'invalid_setting');
    }
});
(0, node_test_1.default)('a valid settings change is applied', async () => {
    const { router, state } = harness();
    const answer = await call(router.find('PUT', '/prospecting/settings'), {
        body: { monthlyBudgetUsd: 25, minScoreForEnrichment: 70 },
    });
    strict_1.default.equal(answer.status, 200);
    strict_1.default.equal(state.settings.monthlyBudgetUsd, 25);
    strict_1.default.equal(state.settings.minScoreForEnrichment, 70);
});
(0, node_test_1.default)('an empty settings body is a refusal rather than a no-op success', async () => {
    const { router } = harness();
    const answer = await call(router.find('PUT', '/prospecting/settings'), { body: {} });
    strict_1.default.equal(answer.status, 400);
});
/* ------------------------------------------------- criterion 11: the cap */
(0, node_test_1.default)('enrichment answers 402 with the reason when the budget is gone', async () => {
    const { router, state } = harness();
    state.spend = { monthUsd: 50, dayUsd: 0, leadUsd: 0 };
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/find-decision-makers'), { params: { prospectId: 'company_1' } });
    strict_1.default.equal(answer.status, 402);
    strict_1.default.equal(answer.body.code, 'budget_exhausted');
    strict_1.default.ok(String(answer.body.message).includes('pausa'));
});
(0, node_test_1.default)('a lead below the threshold is told so, not told the budget ran out', async () => {
    const { router } = harness({ prospect: prospect({ lead_score: 30 }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/find-decision-makers'), { params: { prospectId: 'company_1' } });
    strict_1.default.equal(answer.status, 402);
    strict_1.default.equal(answer.body.code, 'below_threshold');
});
/* ------------------------------------------------------------------ usage */
(0, node_test_1.default)('usage reports the spend against the budget and whether it is estimated', async () => {
    const { router, state } = harness();
    state.spend = { monthUsd: 12.5, dayUsd: 1.25, leadUsd: 0 };
    const answer = await call(router.find('GET', '/prospecting/usage'));
    const spend = answer.body.data.spend;
    strict_1.default.equal(spend.month_usd, 12.5);
    strict_1.default.equal(spend.remaining_month_usd, 37.5);
    strict_1.default.equal(spend.remaining_day_usd, 3.75);
    strict_1.default.equal(spend.paused, false);
});
(0, node_test_1.default)('usage says the module is paused once the cap is reached', async () => {
    const { router, state } = harness();
    state.spend = { monthUsd: 50, dayUsd: 5, leadUsd: 0 };
    const answer = await call(router.find('GET', '/prospecting/usage'));
    const spend = answer.body.data.spend;
    strict_1.default.equal(spend.paused, true);
    strict_1.default.equal(spend.remaining_month_usd, 0);
});
/* ------------------------------------------------------------------ jobs */
(0, node_test_1.default)('a job is readable by id and 404s when it is not there', async () => {
    const { router, state } = harness();
    const job = (0, prospecting_jobs_js_1.newJob)({
        id: 'job_1',
        type: 'DISCOVERY',
        criteria: {},
        target: 50,
        estimatedCostUsd: 1,
        actor: 'admin',
        now: NOW,
    });
    state.jobs.set('job_1', job);
    const found = await call(router.find('GET', '/prospecting/jobs/:jobId'), {
        params: { jobId: 'job_1' },
    });
    strict_1.default.equal(found.status, 200);
    strict_1.default.equal(found.body.data.id, 'job_1');
    const missing = await call(router.find('GET', '/prospecting/jobs/:jobId'), {
        params: { jobId: 'job_2' },
    });
    strict_1.default.equal(missing.status, 404);
    strict_1.default.equal(missing.body.code, 'job_not_found');
});
/* ---------------------------------------------------------------- config */
(0, node_test_1.default)('the form options come from the server, so a new city needs no deploy', async () => {
    const { router } = harness();
    const answer = await call(router.find('GET', '/prospecting/config'));
    const data = answer.body.data;
    strict_1.default.ok(data.industries.length > 0);
    strict_1.default.deepEqual(data.cities, ['Maputo', 'Matola']);
    strict_1.default.deepEqual(data.max_leads_options, [25, 50, 100, 250, 500]);
    strict_1.default.deepEqual(data.min_score_options, [40, 60, 70, 80]);
});
