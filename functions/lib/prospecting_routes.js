"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerProspectingRoutes = registerProspectingRoutes;
exports.toSettingsDto = toSettingsDto;
const admin_audit_js_1 = require("./admin_audit.js");
const prospecting_analysis_js_1 = require("./prospecting_analysis.js");
const prospecting_api_contracts_js_1 = require("./prospecting_api_contracts.js");
const prospecting_budget_js_1 = require("./prospecting_budget.js");
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
const prospecting_pipeline_js_1 = require("./prospecting_pipeline.js");
const prospecting_jobs_js_1 = require("./prospecting_jobs.js");
const prospecting_funnel_js_1 = require("./prospecting_funnel.js");
const prospecting_scoring_js_1 = require("./prospecting_scoring.js");
const prospecting_templates_js_1 = require("./prospecting_templates.js");
const prospecting_store_js_1 = require("./prospecting_store.js");
/**
 * The request as the middleware left it.
 *
 * Express types a handler's `req` as a bare `Request`, and the fields the auth
 * middleware added are invisible to it. The cast is confined to this one
 * function so that a handler cannot quietly assert some other shape.
 */
function authed(req) {
    return req;
}
/* ------------------------------------------------------------- responses */
function paging(input) {
    return {
        limit: input.limit,
        offset: input.offset,
        has_more: input.hasMore,
        total: input.total,
        truncated: input.truncated,
    };
}
function fail(res, error) {
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
function handle(res, operation, error, respondServerError) {
    if (error instanceof prospecting_api_contracts_js_1.ProspectingApiError)
        return fail(res, error);
    if (error instanceof prospecting_analysis_js_1.OutreachBlockedError) {
        return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(403, 'outreach_blocked'));
    }
    if (error instanceof prospecting_store_js_1.TransitionError) {
        return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(409, 'invalid_transition'));
    }
    if (error instanceof prospecting_analysis_js_1.AnalysisError) {
        if (error.code === 'NOT_CONFIGURED') {
            return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(503, 'no_provider'));
        }
        if (error.code === 'INVALID_SCHEMA') {
            return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(503, 'model_invalid'));
        }
        return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(503, 'model_unavailable'));
    }
    return respondServerError(res, operation, error);
}
/* ------------------------------------------------------------------ routes */
function registerProspectingRoutes(deps) {
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
            return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(403, 'prospecting_disabled'));
        }
        return next();
    });
    const actorId = (req) => req.auth?.uid ?? req.appUserId ?? 'unknown';
    /**
     * The rate limit, on the endpoints that cost money.
     *
     * Not about load — these are four internal users. It is about a retry loop
     * in a browser tab spending a month's budget in a minute, which a person
     * clicking "enriquecer" on a slow connection will produce without meaning
     * to.
     */
    async function limited(req, res, action) {
        const allowed = await deps.consumeRateLimit({ actorId: actorId(req), action });
        if (!allowed) {
            fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(429, 'rate_limited'));
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
                    industries: prospecting_config_js_1.ICP_INDUSTRIES.map((entry) => ({
                        business_type: entry.businessType,
                        label: entry.label,
                        tier: entry.tier,
                    })),
                    sizes: prospecting_config_js_1.COMPANY_SIZE_BANDS.map((band) => ({
                        key: band.key,
                        label: band.label,
                    })),
                    max_leads_options: prospecting_config_js_1.MAX_LEADS_OPTIONS,
                    min_score_options: prospecting_config_js_1.MIN_SCORE_OPTIONS,
                    statuses: prospecting_contracts_js_1.PROSPECT_STATUS.map((status) => ({
                        value: status,
                        label: prospecting_contracts_js_1.PROSPECT_STATUS_LABEL[status],
                    })),
                    bands: prospecting_config_js_1.SCORE_BAND,
                    enrichment_statuses: prospecting_contracts_js_1.ENRICHMENT_STATUS,
                    cities: settings.geography.cities,
                    provinces: settings.geography.provinces,
                    country: settings.geography.country,
                },
            });
        }
        catch (error) {
            return handle(res, 'prospecting_config', error, deps.respondServerError);
        }
    });
    /* ------------------------------------------------------------ estimate */
    router.get('/prospecting/estimate', async (req, res) => {
        try {
            const settings = await deps.readSettings();
            const maxLeads = (0, prospecting_api_contracts_js_1.clampLimit)(req.query.maxLeads);
            const minScore = (0, prospecting_api_contracts_js_1.clampLimit)(req.query.minScore);
            const spend = await deps.readSpend(null);
            const estimate = (0, prospecting_budget_js_1.estimateSearchCost)({ maxLeads, minScore, settings });
            return res.json({
                success: true,
                data: {
                    ...estimate,
                    min_usd: estimate.minUsd,
                    max_usd: estimate.maxUsd,
                    likely_usd: estimate.likelyUsd,
                    assumed_qualify_rate: estimate.assumedQualifyRate,
                    monthly_budget_usd: settings.monthlyBudgetUsd,
                    remaining_this_month_usd: (0, prospecting_budget_js_1.round)(Math.max(0, settings.monthlyBudgetUsd - spend.monthUsd)),
                },
            });
        }
        catch (error) {
            return handle(res, 'prospecting_estimate', error, deps.respondServerError);
        }
    });
    /* -------------------------------------------------------------- search */
    router.post('/prospecting/search', async (req, res) => {
        try {
            if (!(await limited(authed(req), res, 'search')))
                return res;
            const settings = await deps.readSettings();
            const request = (0, prospecting_api_contracts_js_1.parseSearchRequest)(req.body, settings);
            const estimate = (0, prospecting_budget_js_1.estimateSearchCost)({
                maxLeads: request.maxLeads,
                minScore: request.minScore,
                settings,
            });
            const job = (0, prospecting_jobs_js_1.newJob)({
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
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
                action: 'prospecting.search.started',
                targetType: 'prospecting_job',
                targetId: job.id,
                merchantId: null,
                details: { criteria: job.criteria, estimated_cost_usd: estimate.likelyUsd },
            });
            return res.status(202).json({ success: true, data: (0, prospecting_api_contracts_js_1.toJobDto)(job) });
        }
        catch (error) {
            return handle(res, 'prospecting_search', error, deps.respondServerError);
        }
    });
    /* ---------------------------------------------------------------- jobs */
    router.get('/prospecting/jobs/:jobId', async (req, res) => {
        try {
            const jobId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.jobId);
            const job = await deps.getJob(jobId);
            if (job === null)
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(404, 'job_not_found'));
            return res.json({ success: true, data: (0, prospecting_api_contracts_js_1.toJobDto)(job) });
        }
        catch (error) {
            return handle(res, 'prospecting_job_get', error, deps.respondServerError);
        }
    });
    router.post('/prospecting/jobs/:jobId/cancel', async (req, res) => {
        try {
            const jobId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.jobId);
            const job = await deps.cancelJob(jobId, now());
            if (job === null)
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(404, 'job_not_found'));
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
                action: 'prospecting.search.cancelled',
                targetType: 'prospecting_job',
                targetId: jobId,
                merchantId: null,
                details: { discovered: job.discovered },
            });
            return res.json({ success: true, data: (0, prospecting_api_contracts_js_1.toJobDto)(job) });
        }
        catch (error) {
            return handle(res, 'prospecting_job_cancel', error, deps.respondServerError);
        }
    });
    /* --------------------------------------------------------------- leads */
    router.get('/prospecting/leads', async (req, res) => {
        try {
            const query = (0, prospecting_api_contracts_js_1.parseListQuery)(req.query);
            const page = await deps.listProspects(query);
            return res.json({
                success: true,
                data: page.rows.map((row) => (0, prospecting_api_contracts_js_1.toProspectSummary)(row.prospect, row.company)),
                paging: paging({
                    limit: query.limit,
                    offset: query.offset,
                    hasMore: page.hasMore,
                    total: page.total,
                    truncated: page.truncated,
                }),
            });
        }
        catch (error) {
            return handle(res, 'prospecting_leads', error, deps.respondServerError);
        }
    });
    router.get('/prospecting/leads/:prospectId', async (req, res) => {
        try {
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const prospect = await deps.getProspect(prospectId);
            if (prospect === null)
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(404, 'prospect_not_found'));
            const [company, contacts, activities, analysis] = await Promise.all([
                deps.getCompany(prospect.company_id),
                deps.listContacts(prospectId),
                deps.listActivities(prospectId),
                deps.latestAnalysis(prospectId),
            ]);
            const writableChannels = (0, prospecting_templates_js_1.channelsWithTemplate)();
            return res.json({
                success: true,
                data: {
                    prospect: (0, prospecting_api_contracts_js_1.toProspectSummary)(prospect, company),
                    company: company === null ? null : (0, prospecting_api_contracts_js_1.toProspectCompany)(company),
                    contacts: contacts.map(prospecting_api_contracts_js_1.toProspectContact),
                    activities: activities.map(prospecting_api_contracts_js_1.toProspectActivity),
                    analysis: analysis === null ? null : toAnalysisDto(analysis, prospect),
                    // Reachable *and* writable. Being contactable by SMS and having an
                    // SMS template are different facts, and offering a channel with no
                    // template behind it is a dead end the screen can avoid showing.
                    available_channels: company === null
                        ? []
                        : (0, prospecting_analysis_js_1.availableChannels)(company, contacts).filter((channel) => writableChannels.includes(channel)),
                    outreach_blocked: (0, prospecting_contracts_js_1.blocksOutreach)(prospect.status),
                },
            });
        }
        catch (error) {
            return handle(res, 'prospecting_lead_get', error, deps.respondServerError);
        }
    });
    /* ------------------------------------------------- decision makers */
    router.post('/prospecting/leads/:prospectId/find-decision-makers', async (req, res) => {
        try {
            if (!(await limited(authed(req), res, 'enrich')))
                return res;
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const { prospect, company } = await loadPair(deps, prospectId);
            const settings = await deps.readSettings();
            const outcome = await (0, prospecting_pipeline_js_1.findDecisionMakers)({
                prospectId,
                company,
                leadScore: prospect.lead_score,
                deps: deps.pipelineDeps(settings),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
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
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(402, 'below_threshold'));
            }
            if (outcome.refusal !== null) {
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(402, 'budget_exhausted'));
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
        }
        catch (error) {
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
            if (!(await limited(authed(req), res, 'enrich')))
                return res;
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const { prospect, company } = await loadPair(deps, prospectId);
            const settings = await deps.readSettings();
            const pipeline = deps.pipelineDeps(settings);
            const detail = await (0, prospecting_pipeline_js_1.fetchListingDetails)({
                prospectId,
                companyId: prospect.company_id,
                company,
                leadScore: prospect.lead_score,
                deps: pipeline,
            });
            if (detail.refusal === 'BELOW_THRESHOLD') {
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(402, 'below_threshold'));
            }
            if (detail.refusal !== null) {
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(402, 'budget_exhausted'));
            }
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
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
        }
        catch (error) {
            return handle(res, 'prospecting_enrich', error, deps.respondServerError);
        }
    });
    /* ------------------------------------------------------------- analyze */
    router.post('/prospecting/leads/:prospectId/analyze', async (req, res) => {
        try {
            if (!(await limited(authed(req), res, 'analyze')))
                return res;
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const { prospect, company } = await loadPair(deps, prospectId);
            const settings = await deps.readSettings();
            const contacts = await deps.listContacts(prospectId);
            const score = (0, prospecting_scoring_js_1.scoreProspect)((0, prospecting_pipeline_js_1.signalsFromResearch)((0, prospecting_pipeline_js_1.signalsFromCompany)(company), null, contacts), settings.scoring, settings.geography);
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
                    ].filter((value) => value !== null),
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
            const willCall = req.body?.force === true ||
                stored === null ||
                stored.data_hash !== service.cacheKeyFor(lead).dataHash ||
                stored.prompt_version !== prospecting_analysis_js_1.PROMPT_VERSION ||
                stored.model !== service.cacheKeyFor(lead).model;
            if (willCall) {
                const decision = await (0, prospecting_pipeline_js_1.guardSpend)({
                    operation: 'ANALYZE_LEAD',
                    prospectId,
                    leadScore: prospect.lead_score,
                    deps: pipeline,
                });
                if (!decision.allowed) {
                    return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(402, decision.refusal === 'BELOW_THRESHOLD' ? 'below_threshold' : 'budget_exhausted'));
                }
            }
            const outcome = await service.analyze({
                lead,
                stored: stored === null
                    ? null
                    : {
                        key: {
                            dataHash: stored.data_hash,
                            promptVersion: stored.prompt_version,
                            model: stored.model,
                        },
                        analysis: stored.analysis,
                    },
                force: req.body?.force === true,
            });
            if (!outcome.fromCache) {
                await pipeline.store.recordUsage({
                    provider: 'anthropic',
                    operation: 'ANALYZE_LEAD',
                    prospectId,
                    estimatedCostUsd: prospecting_config_js_1.OPERATION_COST_USD.ANALYZE_LEAD,
                    success: true,
                    errorCode: null,
                });
                await deps.saveAnalysis({
                    id: deps.newId(),
                    prospect_id: prospectId,
                    model: outcome.cacheKey.model,
                    prompt_version: prospecting_analysis_js_1.PROMPT_VERSION,
                    data_hash: outcome.cacheKey.dataHash,
                    scores: {
                        fit: outcome.analysis.fitScore,
                        business_fit: outcome.analysis.businessFitScore,
                        digital_presence: outcome.analysis.digitalPresenceScore,
                        retention_potential: outcome.analysis.retentionPotentialScore,
                        commercial_opportunity: outcome.analysis.commercialOpportunityScore,
                    },
                    analysis: outcome.analysis,
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
                    metadata: { model: outcome.cacheKey.model, prompt_version: prospecting_analysis_js_1.PROMPT_VERSION },
                    actor: actorId(authed(req)),
                    now: now(),
                });
            }
            const divergence = (0, prospecting_analysis_js_1.scoreDivergence)(outcome.analysis, score);
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
        }
        catch (error) {
            return handle(res, 'prospecting_analyze', error, deps.respondServerError);
        }
    });
    /* ------------------------------------------------------------ outreach */
    router.post('/prospecting/leads/:prospectId/generate-outreach', async (req, res) => {
        try {
            if (!deps.flags().outreachEnabled) {
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(403, 'outreach_disabled'));
            }
            if (!(await limited(authed(req), res, 'outreach')))
                return res;
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const { prospect, company } = await loadPair(deps, prospectId);
            // Checked here as well as inside the service. A guard in only one place
            // is a guard the next endpoint will forget, and this is the one rule
            // that must not have an exception.
            if ((0, prospecting_contracts_js_1.blocksOutreach)(prospect.status)) {
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(403, 'outreach_blocked'));
            }
            const channel = (0, prospecting_api_contracts_js_1.parseChannel)((req.body ?? {}).channel);
            const contacts = await deps.listContacts(prospectId);
            const templateId = (0, prospecting_api_contracts_js_1.parseTemplateId)((req.body ?? {}).template_id);
            /**
             * No budget guard, because there is nothing to guard.
             *
             * Rendering a template costs nothing, so the spend check that used to
             * sit here has no cap to consult and no usage row to write. What has not
             * moved is the block on `DO_NOT_CONTACT` and `OPTED_OUT`: it is checked
             * above and again inside the service, and it was never a cost rule.
             */
            let draft;
            try {
                draft = deps.outreachService().generate({
                    channel,
                    company,
                    contact: contacts.find((contact) => contact.is_decision_maker) ?? null,
                    status: prospect.status,
                    templateId,
                });
            }
            catch (error) {
                // A template that cannot be filled is an answerable problem — a missing
                // city, no template for the channel — not a server fault. The console
                // says which, so an operator can fix the lead or the template.
                if (error instanceof prospecting_templates_js_1.TemplateError) {
                    return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(409, 'template_unusable'));
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
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
                action: 'prospecting.outreach.generated',
                targetType: 'prospect',
                targetId: prospectId,
                merchantId: null,
                details: { channel, template_id: draft.templateId },
            });
            return res.json({ success: true, data: draft });
        }
        catch (error) {
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
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const prospect = await deps.getProspect(prospectId);
            if (prospect === null)
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(404, 'prospect_not_found'));
            if ((0, prospecting_contracts_js_1.blocksOutreach)(prospect.status)) {
                return fail(res, (0, prospecting_api_contracts_js_1.prospectingError)(403, 'outreach_blocked'));
            }
            const channel = (0, prospecting_api_contracts_js_1.parseChannel)((req.body ?? {}).channel);
            const note = (0, prospecting_api_contracts_js_1.parseNote)((req.body ?? {}).note);
            await deps.appendActivity({
                prospectId,
                type: 'OUTREACH_SENT',
                description: note ?? `Mensagem enviada por ${channel}.`,
                channel,
                actor: actorId(authed(req)),
                now: now(),
            });
            const updated = await deps.setProspectStatus({
                prospectId,
                to: 'CONTACTED',
                actor: actorId(authed(req)),
                now: now(),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
                action: 'prospecting.outreach.sent',
                targetType: 'prospect',
                targetId: prospectId,
                merchantId: null,
                details: { channel },
            });
            return res.json({ success: true, data: (0, prospecting_api_contracts_js_1.toProspectSummary)(updated, null) });
        }
        catch (error) {
            return handle(res, 'prospecting_contact', error, deps.respondServerError);
        }
    });
    /* -------------------------------------------------------------- status */
    router.post('/prospecting/leads/:prospectId/status', async (req, res) => {
        try {
            const prospectId = (0, prospecting_api_contracts_js_1.parseIdParam)(req.params.prospectId);
            const body = (req.body ?? {});
            const status = (0, prospecting_api_contracts_js_1.parseStatus)(body.status);
            const note = (0, prospecting_api_contracts_js_1.parseNote)(body.note);
            const updated = await deps.setProspectStatus({
                prospectId,
                to: status,
                actor: actorId(authed(req)),
                reason: note,
                now: now(),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
                action: 'prospecting.lead.status_changed',
                targetType: 'prospect',
                targetId: prospectId,
                merchantId: null,
                details: { to: status, note },
            });
            return res.json({ success: true, data: (0, prospecting_api_contracts_js_1.toProspectSummary)(updated, null) });
        }
        catch (error) {
            return handle(res, 'prospecting_status', error, deps.respondServerError);
        }
    });
    /* --------------------------------------------------------------- usage */
    router.get('/prospecting/usage', async (req, res) => {
        try {
            const settings = await deps.readSettings();
            const limit = (0, prospecting_api_contracts_js_1.clampLimit)(req.query.limit);
            const offset = (0, prospecting_api_contracts_js_1.clampOffset)(req.query.offset);
            const month = typeof req.query.month === 'string' && /^\d{4}-\d{2}$/.test(req.query.month)
                ? req.query.month
                : (0, prospecting_budget_js_1.monthKey)(now());
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
                        remaining_month_usd: (0, prospecting_budget_js_1.round)(Math.max(0, settings.monthlyBudgetUsd - spend.monthUsd)),
                        remaining_day_usd: (0, prospecting_budget_js_1.round)(Math.max(0, settings.dailyBudgetUsd - spend.dayUsd)),
                        estimated: (0, prospecting_budget_js_1.spendIsEstimated)(usage.rows),
                        paused: spend.monthUsd >= settings.monthlyBudgetUsd,
                    },
                    rows: usage.rows.map(prospecting_api_contracts_js_1.toUsageDto),
                },
                paging: paging({
                    limit,
                    offset,
                    hasMore: usage.hasMore,
                    total: usage.rows.length,
                    truncated: false,
                }),
            });
        }
        catch (error) {
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
            const counts = await deps.readFunnelCounts();
            const funnel = (0, prospecting_funnel_js_1.buildFunnel)({
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
                    signals: (0, prospecting_funnel_js_1.decisionSignals)({
                        funnel,
                        priorityCustomers: priority.customers,
                        priorityTotal: priority.total,
                        nurtureCustomers: nurture.customers,
                        nurtureTotal: nurture.total,
                    }),
                },
            });
        }
        catch (error) {
            return handle(res, 'prospecting_funnel', error, deps.respondServerError);
        }
    });
    /* ------------------------------------------------------------ settings */
    router.get('/prospecting/settings', async (_req, res) => {
        try {
            const settings = await deps.readSettings();
            return res.json({ success: true, data: toSettingsDto(settings, deps.flags()) });
        }
        catch (error) {
            return handle(res, 'prospecting_settings_get', error, deps.respondServerError);
        }
    });
    router.put('/prospecting/settings', async (req, res) => {
        try {
            const patch = (0, prospecting_api_contracts_js_1.parseSettingsPatch)(req.body);
            const settings = await deps.writeSettings({
                patch,
                actor: actorId(authed(req)),
                now: now(),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(authed(req)), {
                action: 'prospecting.settings.updated',
                targetType: 'prospecting_settings',
                targetId: 'default',
                merchantId: null,
                details: { fields: Object.keys(patch) },
            });
            return res.json({ success: true, data: toSettingsDto(settings, deps.flags()) });
        }
        catch (error) {
            return handle(res, 'prospecting_settings_put', error, deps.respondServerError);
        }
    });
}
/* ----------------------------------------------------------------- helpers */
async function loadPair(deps, prospectId) {
    const prospect = await deps.getProspect(prospectId);
    if (prospect === null)
        throw (0, prospecting_api_contracts_js_1.prospectingError)(404, 'prospect_not_found');
    const company = await deps.getCompany(prospect.company_id);
    if (company === null)
        throw (0, prospecting_api_contracts_js_1.prospectingError)(404, 'company_not_found');
    return { prospect, company };
}
function toSettingsDto(settings, flags) {
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
function toAnalysisDto(stored, prospect) {
    const analysis = stored.analysis;
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
        score_divergence: prospect.lead_score === null ? null : analysis.fitScore - prospect.lead_score,
        created_at: stored.created_at,
    };
}
