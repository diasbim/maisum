import type * as admin from 'firebase-admin';
import type express from 'express';

import { recordAuditEvent, type AuditActor } from './admin_audit.js';
import {
  AnalysisError,
  availableChannels,
  LeadAnalysisService,
  OutreachBlockedError,
  OutreachService,
  PROMPT_VERSION,
  scoreDivergence,
  type LeadAnalysis,
} from './prospecting_analysis.js';
import {
  clampLimit,
  clampOffset,
  parseChannel,
  parseIdParam,
  parseListQuery,
  parseNote,
  parseTemplateId,
  parseSearchRequest,
  parseSettingsPatch,
  parseStatus,
  ProspectingApiError,
  prospectingError,
  toJobDto,
  toProspectActivity,
  toProspectCompany,
  toProspectContact,
  toProspectSummary,
  toUsageDto,
  type ProspectingPagingDto,
} from './prospecting_api_contracts.js';
import {
  estimateSearchCost,
  QUALIFY_RATE_BY_MIN_SCORE,
  monthKey,
  round,
  spendIsEstimated,
} from './prospecting_budget.js';
import {
  COMPANY_SIZE_BANDS,
  ENRICHMENT_UNIT_COST_USD,
  ICP_INDUSTRIES,
  OPERATION_COST_USD,
  MAX_LEADS_OPTIONS,
  MIN_SCORE_OPTIONS,
  SCORE_BAND,
  type ProspectingFlags,
  type ProspectingSettings,
} from './prospecting_config.js';
import {
  blocksOutreach,
  ENRICHMENT_STATUS,
  PROSPECT_STATUS,
  PROSPECT_STATUS_LABEL,
  type ProspectStatus,
} from './prospecting_contracts.js';
import {
  fetchListingDetails,
  findDecisionMakers,
  guardSpend,
  researchCompany,
  signalsFromCompany,
  signalsFromResearch,
  type PipelineDeps,
} from './prospecting_pipeline.js';
import { newJob, type ProspectingJob } from './prospecting_jobs.js';
import {
  buildFunnel,
  decisionSignals,
  MIN_SENDS_TO_COMPARE,
  templateResults,
} from './prospecting_funnel.js';
import { scoreProspect } from './prospecting_scoring.js';
import {
  channelsWithTemplate,
  TemplateError,
  TemplateOutreachService,
  type TemplateDraft,
} from './prospecting_templates.js';
import {
  TransitionError,
  type ProspectQuery,
  type StoredActivity,
  type StoredAnalysis,
  type StoredCompany,
  type StoredContact,
  type StoredProspect,
} from './prospecting_store.js';
import type { EnrichmentUsage } from './prospecting_budget.js';

/**
 * The HTTP surface of the prospecting module.
 *
 * It lives outside index.ts for the reason `affiliate_routes.ts` does: that
 * file is already fourteen thousand lines, and because everything these
 * handlers need — the audit actor, the settings, the providers, the model, the
 * clock — is passed in rather than reached for. A handler here cannot invent
 * its own idea of who the caller is, or of what the budget is, because it has
 * no way to ask.
 *
 * Every route is mounted on the admin router, which is already behind
 * `isAdminRequest`. Nothing here re-checks the claim, and nothing here may be
 * mounted anywhere else.
 *
 * The order of the guards in each mutating handler is fixed and deliberate:
 * feature flag, then rate limit, then validation, then the compliance check,
 * then the budget. Anything that costs money is last, and anything that
 * refuses for a reason the operator can act on comes before anything that
 * refuses for a reason they cannot.
 */

/**
 * The same request shape index.ts's auth middleware produces.
 *
 * Declared structurally rather than imported, so this module has no dependency
 * back on index.ts — and kept field for field identical, so a drift in either
 * definition is a compile error at the mount point rather than a cast that
 * quietly hides a missing field. `merchantId` is present and unused: admin
 * routes are not merchant-scoped, and the field is here only because the
 * middleware sets it on every request.
 */
export type ProspectingRequest = express.Request & {
  merchantId: string;
  appUserId?: string;
  appUserRole?: string;
  auth?: admin.auth.DecodedIdToken;
};

/**
 * The request as the middleware left it.
 *
 * Express types a handler's `req` as a bare `Request`, and the fields the auth
 * middleware added are invisible to it. The cast is confined to this one
 * function so that a handler cannot quietly assert some other shape.
 */
function authed(req: express.Request): ProspectingRequest {
  return req as unknown as ProspectingRequest;
}

/**
 * Everything the routes cannot reach for themselves.
 *
 * The store functions are listed one by one rather than passed as a module,
 * so the test can supply eleven small functions instead of a Firestore double,
 * and so adding a twelfth is a visible change to this type.
 */
export type ProspectingRouteDeps = {
  adminRouter: express.Router;
  auditActorFrom: (req: ProspectingRequest) => AuditActor;
  respondServerError: (
    res: express.Response,
    operation: string,
    error: unknown,
  ) => express.Response;
  flags: () => ProspectingFlags;
  readSettings: () => Promise<ProspectingSettings>;
  writeSettings: (input: {
    patch: Partial<ProspectingSettings>;
    actor: string;
    now: number;
  }) => Promise<ProspectingSettings>;
  pipelineDeps: (settings: ProspectingSettings) => PipelineDeps;

  getProspect: (id: string) => Promise<StoredProspect | null>;
  getCompany: (id: string) => Promise<StoredCompany | null>;
  listProspects: (query: ProspectQuery) => Promise<{
    rows: Array<{ prospect: StoredProspect; company: StoredCompany | null }>;
    total: number;
    hasMore: boolean;
    truncated: boolean;
  }>;
  listContacts: (prospectId: string) => Promise<StoredContact[]>;
  listActivities: (prospectId: string, limit?: number) => Promise<StoredActivity[]>;
  latestAnalysis: (prospectId: string) => Promise<StoredAnalysis | null>;
  saveAnalysis: (analysis: StoredAnalysis) => Promise<void>;
  setProspectStatus: (input: {
    prospectId: string;
    to: ProspectStatus;
    actor: string;
    reason?: string | null;
    now: number;
  }) => Promise<StoredProspect>;
  saveScores: (input: {
    prospectId: string;
    total: number;
    businessFit: number;
    digitalPresence: number;
    retentionPotential: number;
    commercialOpportunity: number;
    band: string;
    now: number;
  }) => Promise<void>;
  appendActivity: (input: {
    prospectId: string;
    type: StoredActivity['type'];
    description: string;
    channel?: string | null;
    metadata?: Record<string, unknown>;
    actor: string | null;
    now: number;
  }) => Promise<unknown>;
  saveProspectAnalysisFields: (input: {
    prospectId: string;
    summary: string;
    reasoning: string;
    pitch: string;
    channel: string;
    now: number;
  }) => Promise<void>;

  createJob: (job: ProspectingJob) => Promise<void>;
  getJob: (jobId: string) => Promise<ProspectingJob | null>;
  cancelJob: (jobId: string, now: number) => Promise<ProspectingJob | null>;
  /** Kicks the worker. Returning immediately is the point. */
  scheduleJob: (jobId: string) => Promise<void>;

  readSpend: (prospectId: string | null) => Promise<{
    monthUsd: number;
    dayUsd: number;
    leadUsd: number;
  }>;
  readFunnelCounts: (input: { templateIds: readonly string[] }) => Promise<{
    reachedByStage: Record<number, number>;
    exitsByStatus: Partial<Record<ProspectStatus, number>>;
    byBand: Record<string, { total: number; customers: number }>;
    byTemplate: Record<string, { sent: number; replied: number }>;
  }>;
  /** Records which template a lead was written to with, once. */
  recordOutreachTemplate: (input: {
    prospectId: string;
    templateId: string;
    now: number;
  }) => Promise<string>;
  listUsage: (input: { monthKey?: string; limit: number; offset: number }) => Promise<{
    rows: EnrichmentUsage[];
    hasMore: boolean;
  }>;

  analysisService: () => LeadAnalysisService;
  outreachService: () => TemplateOutreachService;

  /** Returns false when the caller has made too many expensive requests. */
  consumeRateLimit: (input: { actorId: string; action: string }) => Promise<boolean>;

  newId: () => string;
  now?: () => number;
};

/* ------------------------------------------------------------- responses */

function paging(input: {
  limit: number;
  offset: number;
  hasMore: boolean;
  total: number;
  truncated: boolean;
}): ProspectingPagingDto {
  return {
    limit: input.limit,
    offset: input.offset,
    has_more: input.hasMore,
    total: input.total,
    truncated: input.truncated,
  };
}

function fail(res: express.Response, error: ProspectingApiError): express.Response {
  const failure = error.toFailure();
  return res
    .status(failure.status)
    .json({ success: false, code: failure.code, message: failure.message });
}

/**
 * The one place a thrown refusal becomes a response.
 *
 * Anything that is not a `ProspectingApiError` is a bug, and goes to the
 * server-error path where it is logged with its cause and answered with a
 * generic body — never with its message, which for a provider failure could
 * carry a URL or a payload.
 */
function handle(
  res: express.Response,
  operation: string,
  error: unknown,
  respondServerError: ProspectingRouteDeps['respondServerError'],
): express.Response {
  if (error instanceof ProspectingApiError) return fail(res, error);

  if (error instanceof OutreachBlockedError) {
    return fail(res, prospectingError(403, 'outreach_blocked'));
  }

  if (error instanceof TransitionError) {
    return fail(res, prospectingError(409, 'invalid_transition'));
  }

  if (error instanceof AnalysisError) {
    if (error.code === 'NOT_CONFIGURED') {
      return fail(res, prospectingError(503, 'no_provider'));
    }
    if (error.code === 'INVALID_SCHEMA') {
      return fail(res, prospectingError(503, 'model_invalid'));
    }
    return fail(res, prospectingError(503, 'model_unavailable'));
  }

  return respondServerError(res, operation, error);
}

/* ------------------------------------------------------------------ routes */

export function registerProspectingRoutes(deps: ProspectingRouteDeps): void {
  const router = deps.adminRouter;
  const now = deps.now ?? Date.now;

  /**
   * Refuses everything when the module is off.
   *
   * Mounted as middleware on the prefix rather than repeated per route,
   * because a route added later that forgot the check would be a paid surface
   * live in an installation that never asked for it. The answer is an explicit
   * "disabled" rather than a 404, so the portal can explain instead of looking
   * broken — the same choice `customer_feature_flags.ts` made.
   */
  router.use('/prospecting', (_req, res, next) => {
    if (!deps.flags().prospectingEnabled) {
      return fail(res, prospectingError(403, 'prospecting_disabled'));
    }
    return next();
  });

  const actorId = (req: ProspectingRequest): string =>
    req.auth?.uid ?? req.appUserId ?? 'unknown';

  /**
   * The rate limit, on the endpoints that cost money.
   *
   * Not about load — these are four internal users. It is about a retry loop
   * in a browser tab spending a month's budget in a minute, which a person
   * clicking "enriquecer" on a slow connection will produce without meaning
   * to.
   */
  async function limited(
    req: ProspectingRequest,
    res: express.Response,
    action: string,
  ): Promise<boolean> {
    const allowed = await deps.consumeRateLimit({ actorId: actorId(req), action });
    if (!allowed) {
      fail(res, prospectingError(429, 'rate_limited'));
      return false;
    }
    return true;
  }

  /* ------------------------------------------------------------- config */

  /**
   * What the search form offers.
   *
   * Served rather than hard-coded in the portal, so adding a city or an
   * industry is one change in one place and the form picks it up. The portal
   * renders whatever this returns.
   */
  router.get('/prospecting/config', async (_req, res) => {
    try {
      const settings = await deps.readSettings();
      return res.json({
        success: true,
        data: {
          industries: ICP_INDUSTRIES.map((entry) => ({
            business_type: entry.businessType,
            label: entry.label,
            tier: entry.tier,
          })),
          sizes: COMPANY_SIZE_BANDS.map((band) => ({
            key: band.key,
            label: band.label,
          })),
          max_leads_options: MAX_LEADS_OPTIONS,
          min_score_options: MIN_SCORE_OPTIONS,
          /**
           * What the console needs to recompute a search estimate itself.
           *
           * The estimate endpoint answers for one pair of values; the form has
           * twenty combinations and the operator changes them before pressing
           * anything. Sending the inputs rather than an answer lets the figure
           * beside the button move with the form, and keeps the numbers
           * themselves in one place — the console does the arithmetic, never
           * the constants.
           */
          estimate_units: {
            discovery_unit_usd: OPERATION_COST_USD.SEARCH_BUSINESSES,
            enrichment_unit_usd: ENRICHMENT_UNIT_COST_USD,
            qualify_rates: QUALIFY_RATE_BY_MIN_SCORE,
          },
          statuses: PROSPECT_STATUS.map((status) => ({
            value: status,
            label: PROSPECT_STATUS_LABEL[status],
          })),
          bands: SCORE_BAND,
          enrichment_statuses: ENRICHMENT_STATUS,
          cities: settings.geography.cities,
          provinces: settings.geography.provinces,
          country: settings.geography.country,
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_config', error, deps.respondServerError);
    }
  });

  /* ------------------------------------------------------------ estimate */

  router.get('/prospecting/estimate', async (req, res) => {
    try {
      const settings = await deps.readSettings();
      const maxLeads = clampLimit(req.query.maxLeads);
      const minScore = clampLimit(req.query.minScore);
      const spend = await deps.readSpend(null);

      const estimate = estimateSearchCost({ maxLeads, minScore, settings });

      return res.json({
        success: true,
        data: {
          ...estimate,
          min_usd: estimate.minUsd,
          max_usd: estimate.maxUsd,
          likely_usd: estimate.likelyUsd,
          assumed_qualify_rate: estimate.assumedQualifyRate,
          monthly_budget_usd: settings.monthlyBudgetUsd,
          remaining_this_month_usd: round(
            Math.max(0, settings.monthlyBudgetUsd - spend.monthUsd),
          ),
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_estimate', error, deps.respondServerError);
    }
  });

  /* -------------------------------------------------------------- search */

  router.post('/prospecting/search', async (req, res) => {
    try {
      if (!(await limited(authed(req), res, 'search'))) return res;

      const settings = await deps.readSettings();
      const request = parseSearchRequest(req.body, settings);

      const estimate = estimateSearchCost({
        maxLeads: request.maxLeads,
        minScore: request.minScore,
        settings,
      });

      const job = newJob({
        id: deps.newId(),
        type: 'DISCOVERY',
        criteria: {
          industries: request.industries,
          city: request.city,
          province: request.province,
          employeeMin: request.size.min,
          employeeMax: request.size.max,
          minScore: request.minScore,
          maxLeads: request.maxLeads,
        },
        target: request.maxLeads,
        estimatedCostUsd: estimate.likelyUsd,
        actor: actorId(authed(req)),
        now: now(),
      });

      await deps.createJob(job);
      // Returns before the work starts. A search for five hundred businesses
      // is minutes of provider calls, and an operator watching a spinner for
      // that long will reload and start a second one.
      await deps.scheduleJob(job.id);

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.search.started',
        targetType: 'prospecting_job',
        targetId: job.id,
        merchantId: null,
        details: { criteria: job.criteria, estimated_cost_usd: estimate.likelyUsd },
      });

      return res.status(202).json({ success: true, data: toJobDto(job) });
    } catch (error) {
      return handle(res, 'prospecting_search', error, deps.respondServerError);
    }
  });

  /* ---------------------------------------------------------------- jobs */

  router.get('/prospecting/jobs/:jobId', async (req, res) => {
    try {
      const jobId = parseIdParam(req.params.jobId);
      const job = await deps.getJob(jobId);
      if (job === null) return fail(res, prospectingError(404, 'job_not_found'));
      return res.json({ success: true, data: toJobDto(job) });
    } catch (error) {
      return handle(res, 'prospecting_job_get', error, deps.respondServerError);
    }
  });

  router.post('/prospecting/jobs/:jobId/cancel', async (req, res) => {
    try {
      const jobId = parseIdParam(req.params.jobId);
      const job = await deps.cancelJob(jobId, now());
      if (job === null) return fail(res, prospectingError(404, 'job_not_found'));

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.search.cancelled',
        targetType: 'prospecting_job',
        targetId: jobId,
        merchantId: null,
        details: { discovered: job.discovered },
      });

      return res.json({ success: true, data: toJobDto(job) });
    } catch (error) {
      return handle(res, 'prospecting_job_cancel', error, deps.respondServerError);
    }
  });

  /* --------------------------------------------------------------- leads */

  router.get('/prospecting/leads', async (req, res) => {
    try {
      const query = parseListQuery(req.query as Record<string, unknown>);
      const page = await deps.listProspects(query);

      return res.json({
        success: true,
        data: page.rows.map((row) => toProspectSummary(row.prospect, row.company)),
        paging: paging({
          limit: query.limit,
          offset: query.offset,
          hasMore: page.hasMore,
          total: page.total,
          truncated: page.truncated,
        }),
      });
    } catch (error) {
      return handle(res, 'prospecting_leads', error, deps.respondServerError);
    }
  });

  router.get('/prospecting/leads/:prospectId', async (req, res) => {
    try {
      const prospectId = parseIdParam(req.params.prospectId);
      const prospect = await deps.getProspect(prospectId);
      if (prospect === null) return fail(res, prospectingError(404, 'prospect_not_found'));

      const [company, contacts, activities, analysis] = await Promise.all([
        deps.getCompany(prospect.company_id),
        deps.listContacts(prospectId),
        deps.listActivities(prospectId),
        deps.latestAnalysis(prospectId),
      ]);

      const writableChannels = channelsWithTemplate();

      return res.json({
        success: true,
        data: {
          prospect: toProspectSummary(prospect, company),
          company: company === null ? null : toProspectCompany(company),
          contacts: contacts.map(toProspectContact),
          activities: activities.map(toProspectActivity),
          analysis: analysis === null ? null : toAnalysisDto(analysis, prospect),
          // Reachable *and* writable. Being contactable by SMS and having an
          // SMS template are different facts, and offering a channel with no
          // template behind it is a dead end the screen can avoid showing.
          available_channels:
            company === null
              ? []
              : availableChannels(company, contacts).filter((channel) =>
                  writableChannels.includes(channel),
                ),
          outreach_blocked: blocksOutreach(prospect.status),
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_lead_get', error, deps.respondServerError);
    }
  });

  /* ------------------------------------------------- decision makers */

  router.post('/prospecting/leads/:prospectId/find-decision-makers', async (req, res) => {
    try {
      if (!(await limited(authed(req), res, 'enrich'))) return res;

      const prospectId = parseIdParam(req.params.prospectId);
      const { prospect, company } = await loadPair(deps, prospectId);

      const settings = await deps.readSettings();
      const outcome = await findDecisionMakers({
        prospectId,
        company,
        leadScore: prospect.lead_score,
        deps: deps.pipelineDeps(settings),
      });

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.decision_makers.searched',
        targetType: 'prospect',
        targetId: prospectId,
        merchantId: null,
        details: {
          found: outcome.decisionMakersFound,
          status: outcome.status,
          spend_usd: outcome.spentUsd,
        },
      });

      if (outcome.refusal === 'BELOW_THRESHOLD') {
        return fail(res, prospectingError(402, 'below_threshold'));
      }
      if (outcome.refusal !== null) {
        return fail(res, prospectingError(402, 'budget_exhausted'));
      }

      return res.json({
        success: true,
        data: {
          status: outcome.status,
          contacts_found: outcome.contactsFound,
          decision_makers_found: outcome.decisionMakersFound,
          spend_usd: outcome.spentUsd,
          fields_discovered: outcome.fieldsDiscovered,
          error_code: outcome.errorCode,
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_decision_makers', error, deps.respondServerError);
    }
  });

  /* -------------------------------------------------------------- enrich */

  /**
   * The dear half of the listing, then a re-score with what it answered.
   *
   * Re-scoring rather than leaving it to a later step is the point: the detail
   * call answers four criteria the scorer could only mark unknown, and a lead
   * that was 55 before it and 75 after should be ranked at 75 on the list
   * without anyone having to open it.
   *
   * Every write belongs to `fetchListingDetails` — the company fields, the
   * score, the activity, the status. The route audits and answers. Two writers
   * for one action is how a screen ends up showing two "enriquecido" entries
   * for one click.
   */
  router.post('/prospecting/leads/:prospectId/enrich', async (req, res) => {
    try {
      if (!(await limited(authed(req), res, 'enrich'))) return res;

      const prospectId = parseIdParam(req.params.prospectId);
      const { prospect, company } = await loadPair(deps, prospectId);

      const settings = await deps.readSettings();
      const pipeline = deps.pipelineDeps(settings);

      const detail = await fetchListingDetails({
        prospectId,
        companyId: prospect.company_id,
        company,
        leadScore: prospect.lead_score,
        deps: pipeline,
      });

      if (detail.refusal === 'BELOW_THRESHOLD') {
        return fail(res, prospectingError(402, 'below_threshold'));
      }
      if (detail.refusal !== null) {
        return fail(res, prospectingError(402, 'budget_exhausted'));
      }

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.lead.enriched',
        targetType: 'prospect',
        targetId: prospectId,
        merchantId: null,
        details: {
          score: detail.score?.total ?? prospect.lead_score,
          spend_usd: detail.spentUsd,
        },
      });

      return res.json({
        success: true,
        data: {
          score: detail.score?.total ?? prospect.lead_score,
          band: detail.score?.band ?? prospect.band,
          unknowns: detail.score?.unknowns ?? [],
          fields: detail.fieldsDiscovered,
          status: detail.status,
          spend_usd: detail.spentUsd,
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_enrich', error, deps.respondServerError);
    }
  });

  /* ------------------------------------------------------------- analyze */

  router.post('/prospecting/leads/:prospectId/analyze', async (req, res) => {
    try {
      if (!(await limited(authed(req), res, 'analyze'))) return res;

      const prospectId = parseIdParam(req.params.prospectId);
      const { prospect, company } = await loadPair(deps, prospectId);

      const settings = await deps.readSettings();
      const contacts = await deps.listContacts(prospectId);

      const score = scoreProspect(
        signalsFromResearch(signalsFromCompany(company), null, contacts),
        settings.scoring,
        settings.geography,
      );

      const lead = {
        company,
        contacts,
        webResearch: null,
        digitalPresence: {
          hasWebsite: company.website !== null,
          socialProfiles: [
            company.instagram_url,
            company.facebook_url,
            company.linkedin_url,
          ].filter((value): value is string => value !== null),
          hasWhatsApp: company.whatsapp !== null,
        },
        score,
      };

      const service = deps.analysisService();
      const stored = await deps.latestAnalysis(prospectId);

      // A model call is a paid provider call, so it is guarded like one. A
      // cache hit is not — which is why the guard runs against the key the
      // service is about to use rather than unconditionally before it: an
      // operator reopening a lead they analysed yesterday must not be told the
      // budget is gone for a request that would spend nothing.
      const pipeline = deps.pipelineDeps(settings);
      const willCall =
        req.body?.force === true ||
        stored === null ||
        stored.data_hash !== service.cacheKeyFor(lead).dataHash ||
        stored.prompt_version !== PROMPT_VERSION ||
        stored.model !== service.cacheKeyFor(lead).model;

      if (willCall) {
        const decision = await guardSpend({
          operation: 'ANALYZE_LEAD',
          prospectId,
          leadScore: prospect.lead_score,
          deps: pipeline,
        });
        if (!decision.allowed) {
          return fail(
            res,
            prospectingError(
              402,
              decision.refusal === 'BELOW_THRESHOLD' ? 'below_threshold' : 'budget_exhausted',
            ),
          );
        }
      }

      const outcome = await service.analyze({
        lead,
        stored:
          stored === null
            ? null
            : {
                key: {
                  dataHash: stored.data_hash,
                  promptVersion: stored.prompt_version,
                  model: stored.model,
                },
                analysis: stored.analysis as unknown as LeadAnalysis,
              },
        force: req.body?.force === true,
      });

      if (!outcome.fromCache) {
        await pipeline.store.recordUsage({
          provider: 'anthropic',
          operation: 'ANALYZE_LEAD',
          prospectId,
          estimatedCostUsd: OPERATION_COST_USD.ANALYZE_LEAD,
          success: true,
          errorCode: null,
        });

        await deps.saveAnalysis({
          id: deps.newId(),
          prospect_id: prospectId,
          model: outcome.cacheKey.model,
          prompt_version: PROMPT_VERSION,
          data_hash: outcome.cacheKey.dataHash,
          scores: {
            fit: outcome.analysis.fitScore,
            business_fit: outcome.analysis.businessFitScore,
            digital_presence: outcome.analysis.digitalPresenceScore,
            retention_potential: outcome.analysis.retentionPotentialScore,
            commercial_opportunity: outcome.analysis.commercialOpportunityScore,
          },
          analysis: outcome.analysis as unknown as Record<string, unknown>,
          recommended_pitch: outcome.analysis.recommendedPitch,
          recommended_channel: outcome.analysis.recommendedChannel,
          created_at: now(),
        });

        await deps.saveProspectAnalysisFields({
          prospectId,
          summary: outcome.analysis.summary,
          reasoning: outcome.analysis.retentionOpportunity,
          pitch: outcome.analysis.recommendedPitch,
          channel: outcome.analysis.recommendedChannel,
          now: now(),
        });

        await deps.appendActivity({
          prospectId,
          type: 'ANALYZED',
          description: 'Análise gerada.',
          metadata: { model: outcome.cacheKey.model, prompt_version: PROMPT_VERSION },
          actor: actorId(authed(req)),
          now: now(),
        });
      }

      const divergence = scoreDivergence(outcome.analysis, score);

      return res.json({
        success: true,
        data: {
          ...outcome.analysis,
          from_cache: outcome.fromCache,
          engine_score: score.total,
          score_divergence: divergence.delta,
          score_divergence_notable: divergence.notable,
          data_hash: outcome.cacheKey.dataHash,
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_analyze', error, deps.respondServerError);
    }
  });

  /* ------------------------------------------------------------ outreach */

  router.post('/prospecting/leads/:prospectId/generate-outreach', async (req, res) => {
    try {
      if (!deps.flags().outreachEnabled) {
        return fail(res, prospectingError(403, 'outreach_disabled'));
      }
      if (!(await limited(authed(req), res, 'outreach'))) return res;

      const prospectId = parseIdParam(req.params.prospectId);
      const { prospect, company } = await loadPair(deps, prospectId);

      // Checked here as well as inside the service. A guard in only one place
      // is a guard the next endpoint will forget, and this is the one rule
      // that must not have an exception.
      if (blocksOutreach(prospect.status)) {
        return fail(res, prospectingError(403, 'outreach_blocked'));
      }

      const channel = parseChannel((req.body ?? {}).channel);
      const contacts = await deps.listContacts(prospectId);
      const templateId = parseTemplateId((req.body ?? {}).template_id);

      /**
       * No budget guard, because there is nothing to guard.
       *
       * Rendering a template costs nothing, so the spend check that used to
       * sit here has no cap to consult and no usage row to write. What has not
       * moved is the block on `DO_NOT_CONTACT` and `OPTED_OUT`: it is checked
       * above and again inside the service, and it was never a cost rule.
       */
      let draft: TemplateDraft;
      try {
        draft = deps.outreachService().generate({
          channel,
          company,
          contact: contacts.find((contact) => contact.is_decision_maker) ?? null,
          status: prospect.status,
          templateId,
        });
      } catch (error) {
        // A template that cannot be filled is an answerable problem — a missing
        // city, no template for the channel — not a server fault. The console
        // says which, so an operator can fix the lead or the template.
        if (error instanceof TemplateError) {
          return fail(res, prospectingError(409, 'template_unusable'));
        }
        throw error;
      }

      await deps.appendActivity({
        prospectId,
        type: 'OUTREACH_GENERATED',
        description: `Mensagem gerada para ${channel}.`,
        channel,
        // `template_id` is what makes the A/B measurable: reply rates are
        // grouped by it, and without it a second version is unattributable.
        metadata: {
          template_id: draft.templateId,
          truncated: draft.truncated,
          length: draft.body.length,
        },
        actor: actorId(authed(req)),
        now: now(),
      });

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.outreach.generated',
        targetType: 'prospect',
        targetId: prospectId,
        merchantId: null,
        details: { channel, template_id: draft.templateId },
      });

      return res.json({ success: true, data: draft });
    } catch (error) {
      return handle(res, 'prospecting_outreach', error, deps.respondServerError);
    }
  });

  /**
   * Records that a person sent something.
   *
   * The server never sends. This endpoint exists so the timeline can say a
   * message went out, and it is the only thing that writes `OUTREACH_SENT` —
   * which is why it refuses for a blocked status too. A salesperson who sent a
   * message to somebody who opted out has done something the record must not
   * quietly absorb.
   */
  router.post('/prospecting/leads/:prospectId/contact', async (req, res) => {
    try {
      const prospectId = parseIdParam(req.params.prospectId);
      const prospect = await deps.getProspect(prospectId);
      if (prospect === null) return fail(res, prospectingError(404, 'prospect_not_found'));

      if (blocksOutreach(prospect.status)) {
        return fail(res, prospectingError(403, 'outreach_blocked'));
      }

      const channel = parseChannel((req.body ?? {}).channel);
      const note = parseNote((req.body ?? {}).note);
      const templateId = parseTemplateId((req.body ?? {}).template_id);

      /**
       * The A/B attribution, recorded here and not on generate.
       *
       * An operator may draft three versions and send one; only the one that
       * went out can have earned a reply. `recordOutreachTemplate` sets it
       * once, so a follow-up in another template cannot take credit for a
       * reply the first message won — and it answers with whatever the lead
       * ended up attributed to, which is what the timeline should record.
       */
      const attributed =
        templateId === null
          ? null
          : await deps.recordOutreachTemplate({
              prospectId,
              templateId,
              now: now(),
            });

      await deps.appendActivity({
        prospectId,
        type: 'OUTREACH_SENT',
        description: note ?? `Mensagem enviada por ${channel}.`,
        channel,
        metadata: attributed === null ? undefined : { template_id: attributed },
        actor: actorId(authed(req)),
        now: now(),
      });

      const updated = await deps.setProspectStatus({
        prospectId,
        to: 'CONTACTED',
        actor: actorId(authed(req)),
        now: now(),
      });

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.outreach.sent',
        targetType: 'prospect',
        targetId: prospectId,
        merchantId: null,
        details: { channel },
      });

      return res.json({ success: true, data: toProspectSummary(updated, null) });
    } catch (error) {
      return handle(res, 'prospecting_contact', error, deps.respondServerError);
    }
  });

  /* -------------------------------------------------------------- status */

  router.post('/prospecting/leads/:prospectId/status', async (req, res) => {
    try {
      const prospectId = parseIdParam(req.params.prospectId);
      const body = (req.body ?? {}) as Record<string, unknown>;
      const status = parseStatus(body.status);
      const note = parseNote(body.note);

      const updated = await deps.setProspectStatus({
        prospectId,
        to: status,
        actor: actorId(authed(req)),
        reason: note,
        now: now(),
      });

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.lead.status_changed',
        targetType: 'prospect',
        targetId: prospectId,
        merchantId: null,
        details: { to: status, note },
      });

      return res.json({ success: true, data: toProspectSummary(updated, null) });
    } catch (error) {
      return handle(res, 'prospecting_status', error, deps.respondServerError);
    }
  });

  /* --------------------------------------------------------------- usage */

  router.get('/prospecting/usage', async (req, res) => {
    try {
      const settings = await deps.readSettings();
      const limit = clampLimit(req.query.limit);
      const offset = clampOffset(req.query.offset);
      const month =
        typeof req.query.month === 'string' && /^\d{4}-\d{2}$/.test(req.query.month)
          ? req.query.month
          : monthKey(now());

      const [spend, usage] = await Promise.all([
        deps.readSpend(null),
        deps.listUsage({ monthKey: month, limit, offset }),
      ]);

      return res.json({
        success: true,
        data: {
          spend: {
            month_key: month,
            month_usd: spend.monthUsd,
            day_usd: spend.dayUsd,
            monthly_budget_usd: settings.monthlyBudgetUsd,
            daily_budget_usd: settings.dailyBudgetUsd,
            remaining_month_usd: round(
              Math.max(0, settings.monthlyBudgetUsd - spend.monthUsd),
            ),
            remaining_day_usd: round(
              Math.max(0, settings.dailyBudgetUsd - spend.dayUsd),
            ),
            estimated: spendIsEstimated(usage.rows),
            paused: spend.monthUsd >= settings.monthlyBudgetUsd,
          },
          rows: usage.rows.map(toUsageDto),
        },
        paging: paging({
          limit,
          offset,
          hasMore: usage.hasMore,
          total: usage.rows.length,
          truncated: false,
        }),
      });
    } catch (error) {
      return handle(res, 'prospecting_usage', error, deps.respondServerError);
    }
  });

  /* -------------------------------------------------------------- funnel */

  /**
   * The question the MVP exists to answer.
   *
   * Not a vanity dashboard: two of these numbers are a decision rule. A low
   * reply rate says the problem is the message, and the A/B on templates is
   * the response. Bands that convert alike say the rules are not
   * discriminating, and that — and only that — is where a learned ranking has
   * ROI a measurement can show. `decisionSignals` computes both.
   */
  router.get('/prospecting/funnel', async (_req, res) => {
    try {
      const templates = deps.outreachService().templateIds();
      const counts = await deps.readFunnelCounts({ templateIds: templates });
      const funnel = buildFunnel({
        reachedByStage: counts.reachedByStage,
        exitsByStatus: counts.exitsByStatus,
      });

      const priority = counts.byBand.PRIORITY ?? { total: 0, customers: 0 };
      const nurture = counts.byBand.NURTURE ?? { total: 0, customers: 0 };

      return res.json({
        success: true,
        data: {
          total: funnel.total,
          stages: funnel.stages.map((stage) => ({
            status: stage.status,
            label: stage.label,
            reached: stage.reached,
            conversion_from_previous: stage.conversionFromPrevious,
            conversion_from_start: stage.conversionFromStart,
          })),
          exits: funnel.exits.map((exit) => ({
            status: exit.status,
            label: exit.label,
            count: exit.count,
          })),
          bands: {
            priority: { total: priority.total, customers: priority.customers },
            nurture: { total: nurture.total, customers: nurture.customers },
          },
          templates: templateResults(counts.byTemplate).map((entry) => ({
            template_id: entry.templateId,
            sent: entry.sent,
            replied: entry.replied,
            reply_rate: entry.replyRate,
            conclusive: entry.conclusive,
          })),
          min_sends_to_compare: MIN_SENDS_TO_COMPARE,
          signals: decisionSignals({
            funnel,
            priorityCustomers: priority.customers,
            priorityTotal: priority.total,
            nurtureCustomers: nurture.customers,
            nurtureTotal: nurture.total,
          }),
        },
      });
    } catch (error) {
      return handle(res, 'prospecting_funnel', error, deps.respondServerError);
    }
  });

  /* ------------------------------------------------------------ settings */

  router.get('/prospecting/settings', async (_req, res) => {
    try {
      const settings = await deps.readSettings();
      return res.json({ success: true, data: toSettingsDto(settings, deps.flags()) });
    } catch (error) {
      return handle(res, 'prospecting_settings_get', error, deps.respondServerError);
    }
  });

  router.put('/prospecting/settings', async (req, res) => {
    try {
      const patch = parseSettingsPatch(req.body);
      const settings = await deps.writeSettings({
        patch,
        actor: actorId(authed(req)),
        now: now(),
      });

      await recordAuditEvent(deps.auditActorFrom(authed(req)), {
        action: 'prospecting.settings.updated',
        targetType: 'prospecting_settings',
        targetId: 'default',
        merchantId: null,
        details: { fields: Object.keys(patch) },
      });

      return res.json({ success: true, data: toSettingsDto(settings, deps.flags()) });
    } catch (error) {
      return handle(res, 'prospecting_settings_put', error, deps.respondServerError);
    }
  });
}

/* ----------------------------------------------------------------- helpers */

async function loadPair(
  deps: ProspectingRouteDeps,
  prospectId: string,
): Promise<{ prospect: StoredProspect; company: StoredCompany }> {
  const prospect = await deps.getProspect(prospectId);
  if (prospect === null) throw prospectingError(404, 'prospect_not_found');

  const company = await deps.getCompany(prospect.company_id);
  if (company === null) throw prospectingError(404, 'company_not_found');

  return { prospect, company };
}

export function toSettingsDto(
  settings: ProspectingSettings,
  flags: ProspectingFlags,
) {
  return {
    monthly_budget_usd: settings.monthlyBudgetUsd,
    daily_budget_usd: settings.dailyBudgetUsd,
    max_enrichment_cost_per_lead_usd: settings.maxEnrichmentCostPerLeadUsd,
    min_score_for_enrichment: settings.minScoreForEnrichment,
    max_prospects_per_search: settings.maxProspectsPerSearch,
    provider_priority: settings.providerPriority,
    cities: settings.geography.cities,
    provinces: settings.geography.provinces,
    country: settings.geography.country,
    flags: {
      prospecting_enabled: flags.prospectingEnabled,
      auto_enrichment_enabled: flags.autoEnrichmentEnabled,
      outreach_enabled: flags.outreachEnabled,
      apollo_enabled: flags.apolloEnabled,
      aisa_enabled: flags.aisaEnabled,
    },
  };
}

function toAnalysisDto(stored: StoredAnalysis, prospect: StoredProspect) {
  const analysis = stored.analysis as unknown as LeadAnalysis;
  return {
    model: stored.model,
    prompt_version: stored.prompt_version,
    summary: analysis.summary,
    retention_opportunity: analysis.retentionOpportunity,
    recommended_product: analysis.recommendedProduct,
    recommended_pitch: analysis.recommendedPitch,
    recommended_channel: analysis.recommendedChannel,
    evidence: analysis.evidence,
    unknowns: analysis.unknowns,
    ai_fit_score: analysis.fitScore,
    engine_score: prospect.lead_score,
    score_divergence:
      prospect.lead_score === null ? null : analysis.fitScore - prospect.lead_score,
    created_at: stored.created_at,
  };
}
