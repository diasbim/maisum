"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_PAGE = exports.MAX_PAGE = exports.PROSPECTING_MESSAGE = exports.ProspectingApiError = void 0;
exports.prospectingError = prospectingError;
exports.parseBodyObject = parseBodyObject;
exports.parseIdParam = parseIdParam;
exports.parseIndustries = parseIndustries;
exports.parseLocation = parseLocation;
exports.parseCompanySize = parseCompanySize;
exports.parseMaxLeads = parseMaxLeads;
exports.parseMinScore = parseMinScore;
exports.parseSearchRequest = parseSearchRequest;
exports.parseStatus = parseStatus;
exports.parseChannel = parseChannel;
exports.parseTemplateId = parseTemplateId;
exports.parseNote = parseNote;
exports.parseListQuery = parseListQuery;
exports.clampLimit = clampLimit;
exports.clampOffset = clampOffset;
exports.parseSettingsPatch = parseSettingsPatch;
exports.toProspectSummary = toProspectSummary;
exports.toProspectCompany = toProspectCompany;
exports.toProspectContact = toProspectContact;
exports.toProspectActivity = toProspectActivity;
exports.toJobDto = toJobDto;
exports.toUsageDto = toUsageDto;
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
const prospecting_jobs_js_1 = require("./prospecting_jobs.js");
class ProspectingApiError extends Error {
    constructor(failure) {
        super(failure.message);
        this.name = 'ProspectingApiError';
        this.status = failure.status;
        this.code = failure.code;
    }
    toFailure() {
        return { status: this.status, code: this.code, message: this.message };
    }
}
exports.ProspectingApiError = ProspectingApiError;
/**
 * Every message this API can show, in one table.
 *
 * Mozambican Portuguese, and each one says what to do rather than what went
 * wrong internally. None names a provider, a key or an internal id.
 */
exports.PROSPECTING_MESSAGE = {
    invalid_body: 'Pedido inválido.',
    invalid_industries: 'Escolha pelo menos um tipo de negócio da lista.',
    invalid_location: 'Indique uma localização válida.',
    invalid_size: 'Escolha uma dimensão de empresa da lista.',
    invalid_max_leads: 'Escolha quantos negócios procurar a partir da lista.',
    invalid_min_score: 'Escolha uma pontuação mínima a partir da lista.',
    invalid_status: 'Estado inválido.',
    invalid_transition: 'Não é possível mudar o estado do lead para esse.',
    invalid_channel: 'Escolha um canal: WhatsApp, email, SMS ou LinkedIn.',
    invalid_setting: 'Valor de configuração inválido.',
    invalid_id: 'Identificador inválido.',
    prospect_not_found: 'Lead não encontrado.',
    company_not_found: 'Negócio não encontrado.',
    job_not_found: 'Trabalho não encontrado.',
    outreach_blocked: 'Este negócio pediu para não ser contactado. Não é possível gerar mensagens.',
    outreach_disabled: 'A geração de mensagens está desligada.',
    prospecting_disabled: 'A prospeção está desligada nesta instalação.',
    budget_exhausted: 'O orçamento de prospeção foi atingido. O enriquecimento pago está em pausa.',
    below_threshold: 'Este lead está abaixo da pontuação mínima para enriquecimento pago.',
    no_provider: 'Nenhum fornecedor de dados está configurado. Fale com quem gere a instalação.',
    model_unavailable: 'O modelo não respondeu. Tente de novo daqui a pouco.',
    model_invalid: 'A resposta do modelo não pôde ser lida. Tente de novo.',
    rate_limited: 'Demasiados pedidos. Tente daqui a pouco.',
    no_contact: 'Não foi encontrado nenhum decisor para este negócio.',
    // Deliberately says what to do rather than which variable was null. The
    // detail is worth logging and is not worth putting in front of somebody who
    // can act on exactly one of the two causes.
    template_unusable: 'Não foi possível preencher o modelo de mensagem: faltam dados do negócio. Complete a ficha ou escolha outro modelo.',
};
function prospectingError(status, code) {
    return new ProspectingApiError({
        status,
        code,
        message: exports.PROSPECTING_MESSAGE[code],
    });
}
/* -------------------------------------------------------------- validation */
function parseBodyObject(raw) {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        throw prospectingError(400, 'invalid_body');
    }
    return raw;
}
function parseIdParam(raw) {
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_id');
    const value = raw.trim();
    // Firestore ids, and nothing that could be a path segment or a traversal.
    if (value === '' || value.length > 128 || !/^[A-Za-z0-9_-]+$/.test(value)) {
        throw prospectingError(400, 'invalid_id');
    }
    return value;
}
/**
 * The industries a search may ask for.
 *
 * Checked against the ICP table rather than accepted as free text, because an
 * unrecognised industry would be passed to the provider as a keyword and spend
 * a search's budget returning nothing. An empty list is legal and means every
 * ICP industry.
 */
function parseIndustries(raw) {
    if (raw === undefined || raw === null)
        return [];
    if (!Array.isArray(raw))
        throw prospectingError(400, 'invalid_industries');
    const allowed = new Set(prospecting_config_js_1.ICP_INDUSTRIES.map((entry) => entry.businessType));
    const industries = [];
    for (const entry of raw) {
        if (typeof entry !== 'string')
            throw prospectingError(400, 'invalid_industries');
        const value = entry.trim().toLowerCase();
        if (!allowed.has(value))
            throw prospectingError(400, 'invalid_industries');
        if (!industries.includes(value))
            industries.push(value);
    }
    return industries;
}
/**
 * A place name.
 *
 * Not checked against the configured cities: a search for a city MaisUm does
 * not yet sell in is a legitimate thing to run — the qualifier is what decides
 * what to do with the results, and it reads the same settings. Refusing here
 * would mean the only way to look at a new market is to change a setting
 * first.
 */
function parseLocation(raw) {
    if (raw === undefined || raw === null || raw === '')
        return null;
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_location');
    const value = raw.trim().replace(/\s+/g, ' ');
    if (value === '')
        return null;
    if (value.length > 80 || !/^[\p{L}\p{M}0-9'\-. ]+$/u.test(value)) {
        throw prospectingError(400, 'invalid_location');
    }
    return value;
}
function parseCompanySize(raw) {
    if (raw === undefined || raw === null || raw === '')
        return { min: null, max: null };
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_size');
    const band = (0, prospecting_config_js_1.findSizeBand)(raw.trim());
    if (band === null)
        throw prospectingError(400, 'invalid_size');
    return { min: band.min, max: band.max };
}
/**
 * How many leads to look for.
 *
 * Must be one of the offered options, and is then clamped to the configured
 * `maxProspectsPerSearch` — a setting that exists precisely so an operator
 * cannot start a five-hundred-lead run when the month's budget will not carry
 * it. Clamping rather than refusing, because the smaller number is what the
 * operator would have chosen had the form shown them the cap.
 */
function parseMaxLeads(raw, settings) {
    if (typeof raw !== 'number' || !Number.isInteger(raw)) {
        throw prospectingError(400, 'invalid_max_leads');
    }
    if (!prospecting_config_js_1.MAX_LEADS_OPTIONS.includes(raw)) {
        throw prospectingError(400, 'invalid_max_leads');
    }
    return Math.min(raw, settings.maxProspectsPerSearch);
}
function parseMinScore(raw) {
    if (typeof raw !== 'number' || !Number.isInteger(raw)) {
        throw prospectingError(400, 'invalid_min_score');
    }
    if (!prospecting_config_js_1.MIN_SCORE_OPTIONS.includes(raw)) {
        throw prospectingError(400, 'invalid_min_score');
    }
    return raw;
}
function parseSearchRequest(raw, settings) {
    const body = parseBodyObject(raw);
    return {
        industries: parseIndustries(body.industries),
        city: parseLocation(body.city),
        province: parseLocation(body.province),
        size: parseCompanySize(body.size),
        maxLeads: parseMaxLeads(body.maxLeads, settings),
        minScore: parseMinScore(body.minScore),
    };
}
function parseStatus(raw) {
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_status');
    const value = raw.trim().toUpperCase();
    if (!(0, prospecting_contracts_js_1.isProspectStatus)(value))
        throw prospectingError(400, 'invalid_status');
    return value;
}
function parseChannel(raw) {
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_channel');
    const value = raw.trim().toUpperCase();
    if (!prospecting_contracts_js_1.OUTREACH_CHANNEL.includes(value)) {
        throw prospectingError(400, 'invalid_channel');
    }
    return value;
}
/**
 * An optional template id, for regenerating one arm of an A/B.
 *
 * Absent means "pick the best fit", which is the ordinary case. A present but
 * unrecognised id is refused by the service rather than quietly falling back:
 * an operator who asked for v2 and silently received v1 would attribute v1's
 * reply to v2, which is the one thing the A/B exists to get right.
 */
function parseTemplateId(raw) {
    if (raw === undefined || raw === null || raw === '')
        return null;
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_body');
    const value = raw.trim().slice(0, 80);
    if (!/^[a-z0-9-]+$/.test(value))
        throw prospectingError(400, 'invalid_body');
    return value;
}
function parseNote(raw) {
    if (raw === undefined || raw === null || raw === '')
        return null;
    if (typeof raw !== 'string')
        throw prospectingError(400, 'invalid_body');
    const value = raw.trim().slice(0, 500);
    return value === '' ? null : value;
}
/* ------------------------------------------------------------- list query */
const SORTS = ['score', 'newest', 'enriched', 'contacted'];
exports.MAX_PAGE = 100;
exports.DEFAULT_PAGE = 25;
/**
 * The list filters, from the query string.
 *
 * Unlike the body parsers, an unrecognised filter value is dropped rather than
 * refused. A query string is something a person pastes into a chat and edits
 * by hand, and a console that answers a stale bookmark with a 400 is worse
 * than one that answers it with an unfiltered list.
 */
function parseListQuery(query) {
    const pick = (raw, allowed) => {
        if (typeof raw !== 'string')
            return undefined;
        const value = raw.trim().toUpperCase();
        return allowed.includes(value) ? value : undefined;
    };
    const text = (raw) => {
        if (typeof raw !== 'string')
            return undefined;
        const value = raw.trim();
        return value === '' ? undefined : value.slice(0, 80);
    };
    const sortRaw = typeof query.sort === 'string' ? query.sort.trim() : '';
    const sort = SORTS.includes(sortRaw)
        ? sortRaw
        : 'score';
    return {
        status: pick(query.status, prospecting_contracts_js_1.PROSPECT_STATUS),
        band: pick(query.band, prospecting_config_js_1.SCORE_BAND),
        enrichmentStatus: pick(query.enrichment, prospecting_contracts_js_1.ENRICHMENT_STATUS),
        source: pick(query.source, prospecting_contracts_js_1.PROSPECT_SOURCE),
        industry: text(query.industry)?.toLowerCase(),
        city: text(query.city),
        contact: query.contact === 'with' || query.contact === 'without'
            ? query.contact
            : undefined,
        search: text(query.search),
        sort,
        limit: clampLimit(query.limit),
        offset: clampOffset(query.offset),
    };
}
function clampLimit(raw) {
    const parsed = Number.parseInt(String(raw ?? ''), 10);
    if (!Number.isFinite(parsed) || parsed <= 0)
        return exports.DEFAULT_PAGE;
    return Math.min(exports.MAX_PAGE, parsed);
}
function clampOffset(raw) {
    const parsed = Number.parseInt(String(raw ?? ''), 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}
/* ---------------------------------------------------------------- settings */
/**
 * A settings patch, with every number bounded.
 *
 * The bounds are not about typos. A monthly budget of a million is a working
 * configuration that empties an account, and a minimum score of zero turns
 * "enrich only what qualifies" off entirely while looking like an ordinary
 * setting. Both are refused here rather than being somebody's discovery at the
 * end of the month.
 */
function parseSettingsPatch(raw) {
    const body = parseBodyObject(raw);
    const patch = {};
    const money = (value, max) => {
        if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > max) {
            throw prospectingError(400, 'invalid_setting');
        }
        return Math.round(value * 100) / 100;
    };
    if (body.monthlyBudgetUsd !== undefined) {
        patch.monthlyBudgetUsd = money(body.monthlyBudgetUsd, 5000);
    }
    if (body.dailyBudgetUsd !== undefined) {
        patch.dailyBudgetUsd = money(body.dailyBudgetUsd, 1000);
    }
    if (body.maxEnrichmentCostPerLeadUsd !== undefined) {
        patch.maxEnrichmentCostPerLeadUsd = money(body.maxEnrichmentCostPerLeadUsd, 50);
    }
    if (body.minScoreForEnrichment !== undefined) {
        const value = body.minScoreForEnrichment;
        if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 100) {
            throw prospectingError(400, 'invalid_setting');
        }
        patch.minScoreForEnrichment = value;
    }
    if (body.maxProspectsPerSearch !== undefined) {
        const value = body.maxProspectsPerSearch;
        if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 1000) {
            throw prospectingError(400, 'invalid_setting');
        }
        patch.maxProspectsPerSearch = value;
    }
    if (body.providerPriority !== undefined) {
        if (!Array.isArray(body.providerPriority)) {
            throw prospectingError(400, 'invalid_setting');
        }
        const keys = body.providerPriority.map((entry) => {
            if (typeof entry !== 'string' || !/^[a-z0-9_-]{1,32}$/.test(entry.trim())) {
                throw prospectingError(400, 'invalid_setting');
            }
            return entry.trim();
        });
        patch.providerPriority = keys;
    }
    if (body.cities !== undefined) {
        if (!Array.isArray(body.cities))
            throw prospectingError(400, 'invalid_setting');
        const cities = body.cities.map((entry) => {
            const value = parseLocation(entry);
            if (value === null)
                throw prospectingError(400, 'invalid_setting');
            return value;
        });
        patch.geography = { ...(patch.geography ?? {}), cities };
    }
    if (Object.keys(patch).length === 0)
        throw prospectingError(400, 'invalid_setting');
    return patch;
}
/* ------------------------------------------------------------------ mappers */
function industryLabel(businessType) {
    if (businessType === null)
        return null;
    return (prospecting_config_js_1.ICP_INDUSTRIES.find((entry) => entry.businessType === businessType)?.label ?? null);
}
const BAND_LABEL = {
    PRIORITY: 'Prioritário',
    GOOD: 'Bom',
    NURTURE: 'A cultivar',
    LOW_FIT: 'Fraco encaixe',
};
function toProspectSummary(prospect, company) {
    const band = prospect.band;
    return {
        id: prospect.id,
        company_id: prospect.company_id,
        name: company?.name ?? '(negócio sem nome)',
        industry: company?.industry ?? null,
        industry_label: industryLabel(company?.industry ?? null),
        city: company?.city ?? null,
        province: company?.province ?? null,
        lead_score: prospect.lead_score,
        band: prospect.band,
        band_label: band !== null && band in BAND_LABEL ? BAND_LABEL[band] : null,
        retention_potential_score: prospect.retention_potential_score,
        decision_maker_count: prospect.decision_maker_count,
        has_reachable_contact: prospect.has_reachable_contact,
        status: prospect.status,
        status_label: prospecting_contracts_js_1.PROSPECT_STATUS_LABEL[prospect.status] ?? prospect.status,
        source: prospect.source,
        enrichment_status: prospect.enrichment_status,
        enrichment_status_label: prospecting_contracts_js_1.ENRICHMENT_STATUS_LABEL[prospect.enrichment_status] ?? prospect.enrichment_status,
        suspected_merchant_id: prospect.suspected_merchant_id,
        spend_usd: prospect.spend_usd,
        last_activity_at: prospect.last_activity_at,
        created_at: prospect.created_at,
    };
}
function toProspectCompany(company) {
    return {
        id: company.id,
        name: company.name,
        legal_name: company.legal_name,
        domain: company.domain,
        website: company.website,
        industry: company.industry,
        industry_label: industryLabel(company.industry),
        employee_count: company.employee_count,
        city: company.city,
        province: company.province,
        country: company.country,
        address: company.address,
        phone: company.phone,
        email: company.email,
        whatsapp: company.whatsapp,
        linkedin_url: company.linkedin_url,
        instagram_url: company.instagram_url,
        facebook_url: company.facebook_url,
        source: company.source,
    };
}
/**
 * A contact, with the difference between a verified and a guessed address
 * carried as a boolean the UI cannot ignore.
 *
 * `email_usable` exists because a screen that shows an address and a small
 * grey label beside it will be read as "here is the email". The flag is what a
 * copy button is disabled on.
 */
function toProspectContact(contact) {
    return {
        id: contact.id,
        first_name: contact.first_name,
        last_name: contact.last_name,
        job_title: contact.job_title,
        seniority: contact.seniority,
        email: contact.email,
        email_status: contact.email_status,
        email_status_label: contact.email_status === 'VERIFIED'
            ? 'Verificado'
            : contact.email_status === 'GUESSED'
                ? 'Estimado'
                : contact.email_status === 'INVALID'
                    ? 'Inválido'
                    : contact.email_status === 'UNVERIFIED'
                        ? 'Por verificar'
                        : 'Desconhecido',
        email_usable: contact.email !== null && contact.email_status === 'VERIFIED',
        phone: contact.phone,
        linkedin_url: contact.linkedin_url,
        is_decision_maker: contact.is_decision_maker,
        confidence_score: contact.confidence_score,
    };
}
function toProspectActivity(activity) {
    return {
        id: activity.id,
        type: activity.type,
        channel: activity.channel,
        description: activity.description,
        metadata: activity.metadata,
        created_at: activity.created_at,
        created_by: activity.created_by,
    };
}
function toJobDto(job) {
    return {
        id: job.id,
        type: job.type,
        status: job.status,
        status_label: prospecting_jobs_js_1.JOB_STATUS_LABEL[job.status] ?? job.status,
        progress_label: (0, prospecting_jobs_js_1.progressLabel)(job),
        progress: (0, prospecting_jobs_js_1.progressFraction)(job),
        target: job.target,
        discovered: job.discovered,
        duplicates: job.duplicates,
        qualified: job.qualified,
        disqualified: job.disqualified,
        enriched: job.enriched,
        failed: job.failed,
        estimated_cost_usd: job.estimated_cost_usd,
        spent_usd: job.spent_usd,
        error_code: job.error_code,
        created_at: job.created_at,
        finished_at: job.finished_at,
    };
}
function toUsageDto(row) {
    return {
        id: row.id,
        provider: row.provider,
        operation: row.operation,
        prospect_id: row.prospect_id,
        estimated_cost: row.estimated_cost,
        actual_cost: row.actual_cost,
        success: row.success,
        error_code: row.error_code,
        created_at: row.created_at,
    };
}
