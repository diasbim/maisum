import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LeadAnalysisService,
  OutreachService,
  parseAnalysis,
  type LeadAnalysis,
  type LlmPort,
} from './prospecting_analysis.js';
import {
  DEFAULT_SETTINGS,
  SCORING_VERSION,
  type ProspectingFlags,
} from './prospecting_config.js';
import type { ProspectStatus } from './prospecting_contracts.js';
import { newJob, type ProspectingJob } from './prospecting_jobs.js';
import { FixtureProvider } from './prospecting_provider_fixtures.js';
import { TemplateOutreachService } from './prospecting_templates.js';
import {
  registerProspectingRoutes,
  type ProspectingRouteDeps,
} from './prospecting_routes.js';
import {
  TransitionError,
  type StoredActivity,
  type StoredAnalysis,
  type StoredCompany,
  type StoredContact,
  type StoredProspect,
} from './prospecting_store.js';
import { canTransition } from './prospecting_contracts.js';

/**
 * The routes against a recording router.
 *
 * No supertest and no HTTP: `registerProspectingRoutes` takes the router as a
 * dependency, so a router that records its handlers is enough to call one
 * directly with a request object and read what it answered. That is the same
 * property the affiliate routes rely on, and it is why these tests run in
 * milliseconds without an emulator.
 */

type Handler = (req: unknown, res: unknown, next?: () => void) => unknown;

type Recorded = { method: string; path: string; handler: Handler };

class FakeRouter {
  readonly routes: Recorded[] = [];
  readonly middleware: Array<{ path: string; handler: Handler }> = [];

  get(path: string, handler: Handler) {
    this.routes.push({ method: 'GET', path, handler });
  }

  post(path: string, handler: Handler) {
    this.routes.push({ method: 'POST', path, handler });
  }

  put(path: string, handler: Handler) {
    this.routes.push({ method: 'PUT', path, handler });
  }

  use(path: string, handler: Handler) {
    this.middleware.push({ path, handler });
  }

  find(method: string, path: string): Handler {
    const found = this.routes.find(
      (route) => route.method === method && route.path === path,
    );
    assert.ok(found, `no route ${method} ${path}`);
    return found.handler;
  }
}

type Answer = { status: number; body: Record<string, unknown> };

function fakeResponse(): { res: unknown; answer: () => Answer } {
  let status = 200;
  let body: Record<string, unknown> = {};

  const res = {
    status(code: number) {
      status = code;
      return res;
    },
    json(payload: Record<string, unknown>) {
      body = payload;
      return res;
    },
  };

  return { res, answer: () => ({ status, body }) };
}

/* ------------------------------------------------------------- the double */

const NOW = 1_758_000_000_000;

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

function company(overrides: Partial<StoredCompany> = {}): StoredCompany {
  return {
    id: 'company_1',
    name: 'Barbearia Exemplo',
    legal_name: null,
    domain: 'barbearia-exemplo.test',
    website: 'https://barbearia-exemplo.test',
    industry: 'barbershop',
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

function prospect(overrides: Partial<StoredProspect> = {}): StoredProspect {
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
    scoring_version: SCORING_VERSION,
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

function contact(overrides: Partial<StoredContact> = {}): StoredContact {
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

const llm: LlmPort = {
  key: 'test',
  model: 'test-model',
  isConfigured: () => true,
  complete: async (input) =>
    input.system.includes('primeira mensagem')
      ? JSON.stringify({ subject: null, body: 'Bom dia. Reparei que...' })
      : ANALYSIS_JSON,
};

type Harness = {
  router: FakeRouter;
  deps: ProspectingRouteDeps;
  state: {
    prospects: Map<string, StoredProspect>;
    contacts: StoredContact[];
    activities: StoredActivity[];
    analyses: StoredAnalysis[];
    jobs: Map<string, ProspectingJob>;
    audit: Array<{ action: string }>;
    usage: Array<{ provider: string; operation: string }>;
    scheduled: string[];
    rateLimitAllows: boolean;
    settings: typeof DEFAULT_SETTINGS;
    spend: { monthUsd: number; dayUsd: number; leadUsd: number };
    funnel: {
      reachedByStage: Record<number, number>;
      exitsByStatus: Partial<Record<ProspectStatus, number>>;
      byBand: Record<string, { total: number; customers: number }>;
      byTemplate: Record<string, { sent: number; replied: number }>;
    };
  };
};

function harness(
  overrides: {
    flags?: Partial<ProspectingFlags>;
    prospect?: StoredProspect;
    analysisStored?: StoredAnalysis | null;
  } = {},
): Harness {
  const router = new FakeRouter();
  const provider = new FixtureProvider();

  const state: Harness['state'] = {
    prospects: new Map([[ 'company_1', overrides.prospect ?? prospect() ]]),
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
    settings: DEFAULT_SETTINGS,
    spend: { monthUsd: 0, dayUsd: 0, leadUsd: 0 },
    funnel: { reachedByStage: {}, exitsByStatus: {}, byBand: {}, byTemplate: {} },
  };

  let counter = 0;

  const deps: ProspectingRouteDeps = {
    adminRouter: router as never,
    auditActorFrom: () => ({
      appUserId: 'admin-1',
      firebaseUid: 'uid-1',
      role: 'ADMIN',
    }),
    respondServerError: (res, _operation, _error) =>
      (res as { status: (code: number) => { json: (b: unknown) => unknown } })
        .status(500)
        .json({ success: false, message: 'Server error' }) as never,
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
        matchExistingCustomer: async () => ({ kind: 'NONE' as const }),
        createProspect: async () => ({ prospectId: 'company_1', created: false }),
        saveScores: async () => {},
        setStatus: async () => {},
        setEnrichment: async () => {},
        saveContact: async () => {},
        appendActivity: async () => {},
        recordUsage: async (input) => {
          state.usage.push({ provider: input.provider, operation: input.operation });
        },
        updateCompanyListing: async () => {},
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
      assert.ok(current);
      if (!canTransition(current.status, to)) {
        throw new TransitionError(current.status, to);
      }
      const updated = { ...current, status: to };
      state.prospects.set(prospectId, updated);
      return updated;
    },
    saveScores: async () => {},
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
    saveProspectAnalysisFields: async () => {},

    createJob: async (job) => {
      state.jobs.set(job.id, job);
    },
    getJob: async (id) => state.jobs.get(id) ?? null,
    cancelJob: async (id) => {
      const job = state.jobs.get(id);
      if (job === undefined) return null;
      const cancelled = { ...job, status: 'CANCELLED' as const };
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
      if (stored === undefined) throw new Error('prospect not found');
      // Set once, exactly as the store's transaction does: the first message
      // sent is the one that can have earned a reply.
      const existing = stored.outreach_template_id;
      if (existing !== null && existing !== '') return existing;
      state.prospects.set(prospectId, {
        ...stored,
        outreach_template_id: templateId,
      });
      return templateId;
    },
    listUsage: async () => ({ rows: [], hasMore: false }),

    analysisService: () => new LeadAnalysisService(llm),
    outreachService: () => new TemplateOutreachService(),

    consumeRateLimit: async () => state.rateLimitAllows,

    newId: () => `id_${counter++}`,
    now: () => NOW,
  };

  registerProspectingRoutes(deps);
  return { router, deps, state };
}

async function call(
  handler: Handler,
  req: Record<string, unknown> = {},
): Promise<Answer> {
  const { res, answer } = fakeResponse();
  await handler({ params: {}, query: {}, body: {}, ...req }, res);
  return answer();
}

/* -------------------------------------------------------- the flag gate */

test('every prospecting route sits behind one feature-flag gate', () => {
  const { router } = harness();
  const gate = router.middleware.find((entry) => entry.path === '/prospecting');
  assert.ok(gate, 'no middleware mounted on /prospecting');

  // Mounted on the prefix, not repeated per route: a route added later that
  // forgot the check would otherwise be a paid surface live in an
  // installation that never asked for it.
  assert.equal(router.middleware.length, 1);
});

test('the gate refuses with an explanation rather than a 404', async () => {
  const { router } = harness({ flags: { prospectingEnabled: false } });
  const gate = router.middleware[0].handler;
  const { res, answer } = fakeResponse();

  let nextCalled = false;
  await gate({}, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(answer().status, 403);
  assert.equal(answer().body.code, 'prospecting_disabled');
});

test('the gate lets a request through when the module is on', async () => {
  const { router } = harness();
  const gate = router.middleware[0].handler;
  let nextCalled = false;
  await gate({}, fakeResponse().res, () => {
    nextCalled = true;
  });
  assert.equal(nextCalled, true);
});

/* -------------------------------------------------------------- the list */

test('the list is paginated, and the envelope matches the console convention', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/leads'), {
    query: { limit: '10' },
  });

  assert.equal(answer.status, 200);
  assert.equal(answer.body.success, true);
  const pagingDto = answer.body.paging as Record<string, unknown>;
  assert.equal(pagingDto.limit, 10);
  assert.equal(pagingDto.offset, 0);
  assert.equal(pagingDto.has_more, false);
});

test('an absurd page size is clamped rather than served', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/leads'), {
    query: { limit: '100000' },
  });
  assert.equal((answer.body.paging as Record<string, unknown>).limit, 100);
});

test('a stale filter in a pasted URL is ignored, not refused', async () => {
  // A query string is something a person pastes into a chat and edits by
  // hand; answering a stale bookmark with a 400 is worse than answering it
  // with an unfiltered list.
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/leads'), {
    query: { status: 'NOT_A_REAL_STATUS', sort: 'nonsense' },
  });
  assert.equal(answer.status, 200);
});

test('a lead carries its label and its flags, not just its codes', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/leads'));
  const rows = answer.body.data as Array<Record<string, unknown>>;

  assert.equal(rows[0].name, 'Barbearia Exemplo');
  assert.equal(rows[0].status_label, 'Pontuado');
  assert.equal(rows[0].industry_label, 'Barbearia');
  assert.equal(rows[0].band_label, 'Bom');
});

/* ------------------------------------------------------------ the detail */

test('a missing lead is a 404 with a readable message', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
    params: { prospectId: 'nope' },
  });

  assert.equal(answer.status, 404);
  assert.equal(answer.body.code, 'prospect_not_found');
  assert.equal(answer.body.message, 'Lead não encontrado.');
});

test('an id that is not an id is refused before anything is read', async () => {
  const { router } = harness();
  for (const bad of ['../../etc', 'a/b', '', 'x'.repeat(200)]) {
    const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
      params: { prospectId: bad },
    });
    assert.equal(answer.status, 400, bad);
    assert.equal(answer.body.code, 'invalid_id');
  }
});

test('the detail carries the contact with its email marked usable or not', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
    params: { prospectId: 'company_1' },
  });

  const data = answer.body.data as Record<string, unknown>;
  const contacts = data.contacts as Array<Record<string, unknown>>;
  assert.equal(contacts[0].email_usable, true);
  assert.equal(contacts[0].email_status_label, 'Verificado');
  assert.equal(data.outreach_blocked, false);
  // SMS is dropped although the lead is reachable on it: there is no SMS
  // template, and offering the channel would send the operator down a dead
  // end. Add one and it comes back with no change here.
  assert.deepEqual(data.available_channels, ['WHATSAPP', 'EMAIL']);
});

test('a guessed email is carried but not marked usable', async () => {
  const { router, state } = harness();
  state.contacts = [contact({ email: 'guess@x.test', email_status: 'GUESSED' })];

  const answer = await call(router.find('GET', '/prospecting/leads/:prospectId'), {
    params: { prospectId: 'company_1' },
  });

  const contacts = (answer.body.data as Record<string, unknown>).contacts as Array<
    Record<string, unknown>
  >;
  assert.equal(contacts[0].email, 'guess@x.test');
  assert.equal(contacts[0].email_usable, false);
  assert.equal(contacts[0].email_status_label, 'Estimado');
});

/* ------------------------------------------------------------- the search */

test('a search validates every field and names the one that failed', async () => {
  const { router } = harness();
  const handler = router.find('POST', '/prospecting/search');

  const cases: Array<[Record<string, unknown>, string]> = [
    [{ industries: ['mining'], maxLeads: 50, minScore: 60 }, 'invalid_industries'],
    [{ industries: [], maxLeads: 37, minScore: 60 }, 'invalid_max_leads'],
    [{ industries: [], maxLeads: 50, minScore: 55 }, 'invalid_min_score'],
    [{ industries: [], maxLeads: 50, minScore: 60, size: 'huge' }, 'invalid_size'],
    [{ industries: [], maxLeads: 50, minScore: 60, city: '<script>' }, 'invalid_location'],
  ];

  for (const [body, code] of cases) {
    const answer = await call(handler, { body });
    assert.equal(answer.status, 400, JSON.stringify(body));
    assert.equal(answer.body.code, code);
  }
});

test('a valid search returns a job id immediately and schedules the work', async () => {
  const { router, state } = harness();
  const answer = await call(router.find('POST', '/prospecting/search'), {
    body: { industries: ['barbershop'], city: 'Maputo', maxLeads: 50, minScore: 60 },
  });

  assert.equal(answer.status, 202);
  const job = answer.body.data as Record<string, unknown>;
  assert.equal(job.status, 'QUEUED');
  assert.equal(job.target, 50);
  assert.equal(job.progress_label, '0 / 50 negócios descobertos');
  assert.equal(state.scheduled.length, 1);
  assert.equal(state.scheduled[0], job.id);
});

test('a search is capped by the configured maximum', async () => {
  const { router, state } = harness();
  state.settings = { ...DEFAULT_SETTINGS, maxProspectsPerSearch: 100 };

  const answer = await call(router.find('POST', '/prospecting/search'), {
    body: { industries: [], maxLeads: 500, minScore: 60 },
  });

  assert.equal((answer.body.data as Record<string, unknown>).target, 100);
});

test('an expensive endpoint is rate limited', async () => {
  const { router, state } = harness();
  state.rateLimitAllows = false;

  const answer = await call(router.find('POST', '/prospecting/search'), {
    body: { industries: [], maxLeads: 50, minScore: 60 },
  });

  assert.equal(answer.status, 429);
  assert.equal(answer.body.code, 'rate_limited');
  assert.equal(state.jobs.size, 0, 'no job should have been created');
});

/* -------------------------------------------------------------- estimate */

test('the estimate is a range and says the budget is what really caps it', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/estimate'), {
    query: { maxLeads: '100', minScore: '60' },
  });

  const data = answer.body.data as Record<string, unknown>;
  assert.ok((data.max_usd as number) > (data.min_usd as number));
  assert.equal(data.verified, false);
  assert.equal(data.monthly_budget_usd, 50);
  assert.equal(data.remaining_this_month_usd, 50);
});

test('what is left of the month subtracts what is already spent', async () => {
  const { router, state } = harness();
  state.spend.monthUsd = 12.5;

  const answer = await call(router.find('GET', '/prospecting/estimate'), {
    query: { maxLeads: '100', minScore: '60' },
  });
  const data = answer.body.data as Record<string, unknown>;

  assert.equal(data.remaining_this_month_usd, 37.5);

  // And nothing else in the same response says otherwise. The estimate used
  // to carry its own `remainingThisMonthUsd`, computed from the settings
  // alone, so it answered "50" beside the route's "37.5" — two numbers for
  // one question, the wrong one being the reassuring one.
  for (const [key, value] of Object.entries(data)) {
    if (/remaining/i.test(key)) assert.equal(value, 37.5, key + ' disagrees');
  }
});

/* --------------------------------------------------------------- status */

test('a legal transition is applied and audited', async () => {
  const { router, state } = harness();
  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
    params: { prospectId: 'company_1' },
    body: { status: 'READY_TO_CONTACT' },
  });

  assert.equal(answer.status, 200);
  assert.equal(state.prospects.get('company_1')?.status, 'READY_TO_CONTACT');
});

test('an illegal transition is a 409, not a silent no-op', async () => {
  const { router } = harness({ prospect: prospect({ status: 'CUSTOMER' }) });
  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
    params: { prospectId: 'company_1' },
    body: { status: 'RAW' },
  });

  assert.equal(answer.status, 409);
  assert.equal(answer.body.code, 'invalid_transition');
});

test('a status that is not in the vocabulary is a 400', async () => {
  const { router } = harness();
  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
    params: { prospectId: 'company_1' },
    body: { status: 'WON' },
  });

  assert.equal(answer.status, 400);
  assert.equal(answer.body.code, 'invalid_status');
});

test('a terminal lead admits no transition at all', async () => {
  for (const terminal of ['DO_NOT_CONTACT', 'OPTED_OUT', 'EXISTING_CUSTOMER'] as const) {
    const { router } = harness({ prospect: prospect({ status: terminal }) });
    const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/status'), {
      params: { prospectId: 'company_1' },
      body: { status: 'CONTACTED' },
    });
    assert.equal(answer.status, 409, terminal);
  }
});

/* ------------------------------------------------- criterion 12: outreach */

test('outreach is refused for DO_NOT_CONTACT, and nothing is generated', async () => {
  const { router, state } = harness({ prospect: prospect({ status: 'DO_NOT_CONTACT' }) });
  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } },
  );

  assert.equal(answer.status, 403);
  assert.equal(answer.body.code, 'outreach_blocked');
  assert.equal(
    state.activities.some((entry) => entry.type === 'OUTREACH_GENERATED'),
    false,
  );
});

test('outreach is refused for OPTED_OUT too', async () => {
  const { router } = harness({ prospect: prospect({ status: 'OPTED_OUT' }) });
  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'EMAIL' } },
  );
  assert.equal(answer.status, 403);
});

test('recording a sent message is refused for a blocked lead as well', async () => {
  // A guard on generation alone would still let a person log a message they
  // should never have sent.
  const { router, state } = harness({ prospect: prospect({ status: 'OPTED_OUT' }) });
  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/contact'), {
    params: { prospectId: 'company_1' },
    body: { channel: 'WHATSAPP' },
  });

  assert.equal(answer.status, 403);
  assert.equal(answer.body.code, 'outreach_blocked');
  assert.equal(state.activities.length, 0);
});

test('the outreach flag turns generation off without turning the module off', async () => {
  const { router } = harness({ flags: { outreachEnabled: false } });
  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } },
  );
  assert.equal(answer.status, 403);
  assert.equal(answer.body.code, 'outreach_disabled');
});

test('a draft is generated, recorded as generated, and never as sent', async () => {
  const stored: StoredAnalysis = {
    id: 'an_1',
    prospect_id: 'company_1',
    model: 'test-model',
    prompt_version: 3,
    data_hash: 'abc',
    scores: {},
    analysis: parseAnalysis(ANALYSIS_JSON) as unknown as Record<string, unknown>,
    recommended_pitch: 'Bom dia...',
    recommended_channel: 'WHATSAPP',
    created_at: NOW,
  };

  const { router, state } = harness({ analysisStored: stored });
  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } },
  );

  assert.equal(answer.status, 200);
  const draft = answer.body.data as Record<string, unknown>;
  assert.equal(draft.channel, 'WHATSAPP');
  assert.equal(draft.locale, 'pt-MZ');

  const types = state.activities.map((entry) => entry.type);
  assert.ok(types.includes('OUTREACH_GENERATED'));
  assert.equal(types.includes('OUTREACH_SENT'), false);
});

test('a channel outside the four is refused', async () => {
  const { router } = harness();
  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'PIGEON' } },
  );
  assert.equal(answer.status, 400);
  assert.equal(answer.body.code, 'invalid_channel');
});

test('recording a sent message moves the lead and writes the timeline entry', async () => {
  const { router, state } = harness({ prospect: prospect({ status: 'READY_TO_CONTACT' }) });
  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/contact'), {
    params: { prospectId: 'company_1' },
    body: { channel: 'WHATSAPP', note: 'Enviei pelo telefone da loja.' },
  });

  assert.equal(answer.status, 200);
  assert.equal(state.prospects.get('company_1')?.status, 'CONTACTED');
  assert.equal(state.activities[0].type, 'OUTREACH_SENT');
  assert.equal(state.activities[0].description, 'Enviei pelo telefone da loja.');
});

/* -------------------------------------------------------------- analysis */

test('an analysis is generated, stored, and reported against the engine score', async () => {
  const { router, state } = harness();
  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/analyze'), {
    params: { prospectId: 'company_1' },
  });

  assert.equal(answer.status, 200);
  const data = answer.body.data as Record<string, unknown>;
  assert.equal(data.from_cache, false);
  assert.equal(typeof data.engine_score, 'number');
  assert.equal(typeof data.score_divergence, 'number');
  assert.equal(state.analyses.length, 1);
  assert.ok(state.activities.some((entry) => entry.type === 'ANALYZED'));
});

test('a second analysis of unchanged data is served from the cache', async () => {
  const { router, state } = harness();
  const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');

  await call(handler, { params: { prospectId: 'company_1' } });
  const second = await call(handler, { params: { prospectId: 'company_1' } });

  assert.equal((second.body.data as Record<string, unknown>).from_cache, true);
  assert.equal(state.analyses.length, 1, 'a second analysis was stored');
});

test('a model call is charged like any other paid call', async () => {
  const { router, state } = harness();
  const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');

  await call(handler, { params: { prospectId: 'company_1' } });

  assert.deepEqual(state.usage, [{ provider: 'anthropic', operation: 'ANALYZE_LEAD' }]);

  // A cache hit calls nothing, so it charges nothing. A module that counted
  // the model's cost only when it happened to remember to would be spending
  // silently in the one place nobody was watching.
  await call(handler, { params: { prospectId: 'company_1' } });
  assert.equal(state.usage.length, 1);
});

test('an analysis is refused when the budget is gone', async () => {
  const { router, state } = harness();
  state.spend = { monthUsd: 50, dayUsd: 0, leadUsd: 0 };

  const answer = await call(router.find('POST', '/prospecting/leads/:prospectId/analyze'), {
    params: { prospectId: 'company_1' },
  });

  assert.equal(answer.status, 402);
  assert.equal(answer.body.code, 'budget_exhausted');
  assert.equal(state.analyses.length, 0);
});

test('re-reading a cached analysis is never refused for budget', async () => {
  // A cache hit spends nothing, so an operator reopening yesterday's lead must
  // not be told the budget is gone for a request that would not have cost
  // anything.
  const { router, state } = harness();
  const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');

  await call(handler, { params: { prospectId: 'company_1' } });
  state.spend = { monthUsd: 50, dayUsd: 5, leadUsd: 0.5 };

  const second = await call(handler, { params: { prospectId: 'company_1' } });
  assert.equal(second.status, 200);
  assert.equal((second.body.data as Record<string, unknown>).from_cache, true);
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
test('generating outreach costs nothing and works with the budget exhausted', async () => {
  const { router, state } = harness();
  state.spend = { monthUsd: 50, dayUsd: 5, leadUsd: 0.5 };

  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } },
  );

  assert.equal(answer.status, 200);
  const data = answer.body.data as Record<string, unknown>;
  assert.equal(data.template_id ?? data.templateId, 'barbershop-whatsapp-v1');
  assert.ok(String(data.body).includes('Barbearia Exemplo'));

  // No usage row, because nothing was billable.
  assert.deepEqual(state.usage, []);
  assert.ok(state.activities.some((entry) => entry.type === 'OUTREACH_GENERATED'));
});

test('an analysis is no longer required to write to a lead', async () => {
  // The old route refused with 409 unless a stored analysis existed, because
  // the prompt was built from it. A template needs the company, not a model's
  // opinion of it.
  const { router } = harness({ analysisStored: null });

  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } },
  );

  assert.equal(answer.status, 200);
});

test('the generated message records which template produced it', async () => {
  const { router, state } = harness();

  await call(
    router.find('POST', '/prospecting/leads/:prospectId/generate-outreach'),
    { params: { prospectId: 'company_1' }, body: { channel: 'WHATSAPP' } },
  );

  const activity = state.activities.find(
    (entry) => entry.type === 'OUTREACH_GENERATED',
  );
  assert.ok(activity);
  // Without this, a second template version is unattributable and the A/B
  // measures nothing.
  assert.equal(
    (activity.metadata as Record<string, unknown>).template_id,
    'barbershop-whatsapp-v1',
  );
});

test('force re-runs the analysis', async () => {
  const { router, state } = harness();
  const handler = router.find('POST', '/prospecting/leads/:prospectId/analyze');

  await call(handler, { params: { prospectId: 'company_1' } });
  const forced = await call(handler, {
    params: { prospectId: 'company_1' },
    body: { force: true },
  });

  assert.equal((forced.body.data as Record<string, unknown>).from_cache, false);
  assert.equal(state.analyses.length, 2);
});

/* -------------------------------------------------------------- settings */

test('settings are readable and carry the flags with them', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/settings'));
  const data = answer.body.data as Record<string, unknown>;

  assert.equal(data.monthly_budget_usd, 50);
  assert.equal(data.min_score_for_enrichment, 60);
  assert.deepEqual((data.flags as Record<string, unknown>).prospecting_enabled, true);
});

test('a budget that would empty an account is refused', async () => {
  const { router } = harness();
  const handler = router.find('PUT', '/prospecting/settings');

  for (const body of [
    { monthlyBudgetUsd: 1_000_000 },
    { monthlyBudgetUsd: -1 },
    { minScoreForEnrichment: 0 },
    { minScoreForEnrichment: 101 },
    { maxProspectsPerSearch: 0 },
  ]) {
    const answer = await call(handler, { body });
    assert.equal(answer.status, 400, JSON.stringify(body));
    assert.equal(answer.body.code, 'invalid_setting');
  }
});

test('a valid settings change is applied', async () => {
  const { router, state } = harness();
  const answer = await call(router.find('PUT', '/prospecting/settings'), {
    body: { monthlyBudgetUsd: 25, minScoreForEnrichment: 70 },
  });

  assert.equal(answer.status, 200);
  assert.equal(state.settings.monthlyBudgetUsd, 25);
  assert.equal(state.settings.minScoreForEnrichment, 70);
});

test('an empty settings body is a refusal rather than a no-op success', async () => {
  const { router } = harness();
  const answer = await call(router.find('PUT', '/prospecting/settings'), { body: {} });
  assert.equal(answer.status, 400);
});

/* ------------------------------------------------- criterion 11: the cap */

test('enrichment answers 402 with the reason when the budget is gone', async () => {
  const { router, state } = harness();
  state.spend = { monthUsd: 50, dayUsd: 0, leadUsd: 0 };

  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/find-decision-makers'),
    { params: { prospectId: 'company_1' } },
  );

  assert.equal(answer.status, 402);
  assert.equal(answer.body.code, 'budget_exhausted');
  assert.ok(String(answer.body.message).includes('pausa'));
});

test('a lead below the threshold is told so, not told the budget ran out', async () => {
  const { router } = harness({ prospect: prospect({ lead_score: 30 }) });
  const answer = await call(
    router.find('POST', '/prospecting/leads/:prospectId/find-decision-makers'),
    { params: { prospectId: 'company_1' } },
  );

  assert.equal(answer.status, 402);
  assert.equal(answer.body.code, 'below_threshold');
});

/* ------------------------------------------------------------------ usage */

test('usage reports the spend against the budget and whether it is estimated', async () => {
  const { router, state } = harness();
  state.spend = { monthUsd: 12.5, dayUsd: 1.25, leadUsd: 0 };

  const answer = await call(router.find('GET', '/prospecting/usage'));
  const spend = (answer.body.data as Record<string, unknown>).spend as Record<string, unknown>;

  assert.equal(spend.month_usd, 12.5);
  assert.equal(spend.remaining_month_usd, 37.5);
  assert.equal(spend.remaining_day_usd, 3.75);
  assert.equal(spend.paused, false);
});

test('usage says the module is paused once the cap is reached', async () => {
  const { router, state } = harness();
  state.spend = { monthUsd: 50, dayUsd: 5, leadUsd: 0 };

  const answer = await call(router.find('GET', '/prospecting/usage'));
  const spend = (answer.body.data as Record<string, unknown>).spend as Record<string, unknown>;

  assert.equal(spend.paused, true);
  assert.equal(spend.remaining_month_usd, 0);
});

/* ------------------------------------------------------------------ jobs */

test('a job is readable by id and 404s when it is not there', async () => {
  const { router, state } = harness();
  const job = newJob({
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
  assert.equal(found.status, 200);
  assert.equal((found.body.data as Record<string, unknown>).id, 'job_1');

  const missing = await call(router.find('GET', '/prospecting/jobs/:jobId'), {
    params: { jobId: 'job_2' },
  });
  assert.equal(missing.status, 404);
  assert.equal(missing.body.code, 'job_not_found');
});

/* ---------------------------------------------------------------- config */

test('the form options come from the server, so a new city needs no deploy', async () => {
  const { router } = harness();
  const answer = await call(router.find('GET', '/prospecting/config'));
  const data = answer.body.data as Record<string, unknown>;

  assert.ok((data.industries as unknown[]).length > 0);
  assert.deepEqual(data.cities, ['Maputo', 'Matola']);
  assert.deepEqual(data.max_leads_options, [25, 50, 100, 250, 500]);
  assert.deepEqual(data.min_score_options, [40, 60, 70, 80]);
});
