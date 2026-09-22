"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OUTREACH_MAX_CHARS = exports.DEFAULT_OUTREACH_LOCALE = exports.MIN_SCORE_OPTIONS = exports.MAX_LEADS_OPTIONS = exports.COMPANY_SIZE_BANDS = exports.DEFAULT_SETTINGS = exports.ENRICHMENT_UNIT_COST_USD = exports.ESTIMATES_VERIFIED = exports.OPERATION_COST_USD = exports.DEFAULT_SCORING = exports.SCORE_BAND_LABEL = exports.SCORE_BAND = exports.SCORING_VERSION = exports.DEFAULT_GEOGRAPHY = exports.ICP_INDUSTRIES = void 0;
exports.findIcpIndustry = findIcpIndustry;
exports.bandFor = bandFor;
exports.findSizeBand = findSizeBand;
exports.resolveProspectingFlags = resolveProspectingFlags;
const prospecting_dedup_js_1 = require("./prospecting_dedup.js");
exports.ICP_INDUSTRIES = [
    {
        businessType: 'barbershop',
        label: 'Barbearia',
        tier: 1,
        recurringModel: true,
        multipleServices: true,
        keywords: ['barbearia', 'barber', 'barbeiro', 'barbershop'],
    },
    {
        businessType: 'salon',
        label: 'Salão de beleza',
        tier: 1,
        recurringModel: true,
        multipleServices: true,
        keywords: ['salão de beleza', 'salao', 'cabeleireiro', 'beauty salon', 'hair'],
    },
    {
        businessType: 'spa',
        label: 'Spa e estética',
        tier: 2,
        recurringModel: true,
        multipleServices: true,
        keywords: ['spa', 'estética', 'estetica', 'clínica de estética', 'massagem'],
    },
    {
        businessType: 'gym',
        label: 'Ginásio e fitness',
        tier: 2,
        recurringModel: true,
        multipleServices: false,
        keywords: ['ginásio', 'ginasio', 'gym', 'fitness', 'academia'],
    },
    {
        businessType: 'car_wash',
        label: 'Lavagem automóvel',
        tier: 2,
        recurringModel: true,
        multipleServices: true,
        keywords: ['lavagem auto', 'car wash', 'lavagem automóvel', 'lava jato'],
    },
    {
        businessType: 'restaurant',
        label: 'Restaurante',
        tier: 2,
        recurringModel: true,
        multipleServices: true,
        keywords: ['restaurante', 'restaurant', 'churrasqueira'],
    },
    {
        businessType: 'cafe',
        label: 'Café e pastelaria',
        tier: 2,
        recurringModel: true,
        multipleServices: true,
        keywords: ['café', 'cafe', 'pastelaria', 'coffee'],
    },
];
function findIcpIndustry(businessType) {
    if (businessType === null)
        return null;
    const normalized = businessType.trim().toLowerCase();
    return (exports.ICP_INDUSTRIES.find((entry) => entry.businessType === normalized) ?? null);
}
exports.DEFAULT_GEOGRAPHY = {
    country: 'Moçambique',
    countryCode: 'MZ',
    phoneCountryCode: '+258',
    provinces: ['Maputo', 'Maputo Cidade'],
    cities: ['Maputo', 'Matola'],
};
/**
 * Which weighting a stored score was produced by.
 *
 * Bumped whenever a change to `DEFAULT_SCORING` would give the same business a
 * different number. Stored beside every score, for one reason: the weights are
 * data an admin can edit, and the moment that is true a bare score cannot
 * answer "were August's leads worse, or did the table move?". Two numbers from
 * different versions are not comparable and the module should be able to say
 * so rather than averaging them.
 *
 * Version 2 is the redistribution away from the sources the module no longer
 * calls — see the note on `DEFAULT_SCORING`. Everything written before it was
 * version 1.
 */
exports.SCORING_VERSION = 2;
exports.SCORE_BAND = ['PRIORITY', 'GOOD', 'NURTURE', 'LOW_FIT'];
exports.SCORE_BAND_LABEL = {
    PRIORITY: 'Prioritário',
    GOOD: 'Bom',
    NURTURE: 'A cultivar',
    LOW_FIT: 'Fraco encaixe',
};
/**
 * The weights, sized to the data the pipeline can actually get.
 *
 * Six criteria are worth zero: `employeeCountInRange`, `activeSocial`,
 * `strongPresence`, `promotions`, `decisionMakerIdentified` and `growthSignal`.
 * They are not dead config. Each was fed by a source the module no longer
 * calls — a people database for the decision maker, a web crawl for the
 * promotions — and a criterion whose input never arrives scores every lead the
 * same way: zero, marked UNKNOWN. Four of those against a 100-point table put
 * the reachable maximum at 65, which does not stop leads being ranked but does
 * stop any of them reaching a band calibrated for 100. **A criterion that can
 * never fire is not rigour; it is a band that quietly means something else.**
 *
 * So the points move to criteria the current source does feed, and the totals
 * stay: 40 / 20 / 30 / 10. The bands above keep their meaning because a
 * perfect lead still scores 100, and the zeroed fields stay in the type so a
 * settings document written before this change still parses — and so that
 * restoring any of them, when a source for it comes back, is a number in the
 * admin screen rather than a deploy.
 *
 * `scoreProspect` skips a zero-weight criterion entirely rather than showing
 * it as worth nothing, which is why the breakdown does not fill with rows an
 * operator can do nothing about.
 */
exports.DEFAULT_SCORING = {
    businessFit: {
        max: 40,
        targetIndustry: 20,
        recurringCustomerModel: 10,
        employeeCountInRange: 0,
        targetGeography: 5,
        employeeRange: { min: 3, max: 20 },
        ratingAtLeast: 5,
        minRating: 4,
    },
    digitalPresence: {
        max: 20,
        website: 5,
        activeSocial: 0,
        contactChannel: 5,
        strongPresence: 0,
        strongPresenceProfiles: 2,
        openingHours: 5,
        photos: 5,
    },
    retentionPotential: {
        max: 30,
        recurringService: 10,
        multipleServices: 5,
        promotions: 0,
        loyaltyUseCase: 5,
        reviewVolume: 5,
        /**
         * Ten and thirty, not fifty and a hundred.
         *
         * A busy barbershop in the Alto-Maé may carry eight Google reviews. The
         * thresholds that separate a real business from a dead listing in a mature
         * market would reject the entire target market here, and a criterion that
         * rejects everything is the 65-point ceiling again in another costume.
         * These are the first numbers to revise once a campaign has run.
         */
        reviewThresholds: [10, 30],
    },
    commercialOpportunity: {
        max: 10,
        decisionMakerIdentified: 0,
        reachableContact: 5,
        growthSignal: 0,
        operational: 5,
    },
    bands: [
        { band: 'PRIORITY', min: 80 },
        { band: 'GOOD', min: 60 },
        { band: 'NURTURE', min: 40 },
        { band: 'LOW_FIT', min: 0 },
    ],
};
function bandFor(score, config) {
    for (const entry of config.bands) {
        if (score >= entry.min)
            return entry.band;
    }
    // The table is expected to end at zero; if someone removes that row, a score
    // is still banded rather than returning undefined into a stored field.
    return 'LOW_FIT';
}
/* -------------------------------------------------------------- budgeting */
/**
 * What one provider call is expected to cost, in USD.
 *
 * Estimates, and named as such everywhere they are used: the actual cost comes
 * back from the adapter when the provider reports one, and the usage row keeps
 * both. They exist for two jobs — telling an operator what a search will cost
 * before they run it, and refusing a call that would take the month past its
 * cap. Both are better served by a number that is roughly right than by no
 * number at all, but neither may be presented as a bill.
 *
 * Apollo prices by credit rather than by call, and a credit's dollar value
 * depends on the plan. These are the figures to revise first once a real
 * invoice exists; until then `ESTIMATES_VERIFIED` is false and the UI says so.
 */
exports.OPERATION_COST_USD = {
    /**
     * One page of twenty listings.
     *
     * Places bills a search by the fields the mask asks for, and this is the
     * cheap mask — see `SEARCH_FIELD_MASK`. Adding a field to that constant
     * moves the tier, and this number with it.
     */
    SEARCH_BUSINESSES: 0.02,
    /**
     * The dear half, and the only per-lead cost left.
     *
     * Charged once per business that clears `minScoreForEnrichment`, never per
     * business discovered. That gate is the entire cost design: a campaign that
     * turns up a thousand shops pays this for the three hundred worth calling.
     */
    FETCH_LISTING_DETAILS: 0.03,
    ENRICH_COMPANY: 0.05,
    FIND_DECISION_MAKERS: 0.05,
    ENRICH_PERSON: 0.1,
    RESEARCH_COMPANY: 0.03,
    // Not emitted any more — the analysis is not run and outreach is templated.
    // Kept because historical usage rows name them and a spend report that
    // cannot price last quarter's rows is not a report. Zero would be worse
    // than stale: it would silently rewrite what those months cost.
    ANALYZE_LEAD: 0.05,
    GENERATE_OUTREACH: 0.02,
};
/**
 * Whether the numbers above came from a real invoice.
 *
 * False, and read by the search screen: the estimate is shown with the caveat
 * attached rather than as a figure to plan against, and the sentence that
 * matters — that the configured cap is what actually limits spending — is
 * shown beside it.
 */
exports.ESTIMATES_VERIFIED = false;
/**
 * The full cost of taking one qualifying lead from scored to ready.
 *
 * One call now, where it used to be four: contact discovery, person
 * enrichment, web research and a model call, at $0.23 the lead. The phone
 * number and the website come from the listing the lead was found in, so a
 * business goes from scored to ready for the price of asking about it twice.
 *
 * Used for the search estimate, where the number of leads that will clear the
 * threshold is itself unknown — so the estimate is a range, and this is its
 * upper unit.
 */
exports.ENRICHMENT_UNIT_COST_USD = exports.OPERATION_COST_USD.FETCH_LISTING_DETAILS;
exports.DEFAULT_SETTINGS = {
    monthlyBudgetUsd: 50,
    dailyBudgetUsd: 5,
    maxEnrichmentCostPerLeadUsd: 0.5,
    minScoreForEnrichment: 60,
    /**
     * Ten points. Enough to put a business with no evidence below a threshold
     * of 60 from the 60 it would otherwise score, and not so much that a single
     * missing field buries a lead that is fine on everything else.
     */
    noRatingPenalty: 10,
    bayesianPriorCount: 10,
    dedupRadiusMetres: prospecting_dedup_js_1.DEFAULT_DEDUP_RADIUS_METRES,
    maxProspectsPerSearch: 500,
    /**
     * The order the discovery and contact chains are walked.
     *
     * Places first, fixtures behind it, and Apollo absent by default. Apollo is
     * still wired and still works — an installation that wants decision makers
     * and headcount puts `'apollo'` back at the head of this list and turns its
     * flag on. It is out of the default because it is the expensive half of the
     * old pipeline and the MVP is answering whether prospecting converts at all
     * before paying for that.
     *
     * AIsa is deliberately absent for a different reason: it is a search gateway
     * with no people database behind it, so it serves web research only and is
     * wired into that chain directly rather than through this list. Putting it
     * here would add a provider to two chains it can only fail in, and every
     * failure is a call.
     */
    providerPriority: ['places', 'fixtures'],
    geography: exports.DEFAULT_GEOGRAPHY,
    scoring: exports.DEFAULT_SCORING,
};
/** The sizes the search form offers, and what each means in employees. */
exports.COMPANY_SIZE_BANDS = [
    { key: '1-5', label: '1–5 pessoas', min: 1, max: 5 },
    { key: '6-20', label: '6–20 pessoas', min: 6, max: 20 },
    { key: '21-50', label: '21–50 pessoas', min: 21, max: 50 },
    { key: '50+', label: 'Mais de 50', min: 51, max: null },
];
function findSizeBand(key) {
    return exports.COMPANY_SIZE_BANDS.find((band) => band.key === key) ?? null;
}
/** What the max-leads selector offers. Bounded by `maxProspectsPerSearch`. */
exports.MAX_LEADS_OPTIONS = [25, 50, 100, 250, 500];
/** What the minimum-score selector offers. */
exports.MIN_SCORE_OPTIONS = [40, 60, 70, 80];
/* ---------------------------------------------------------------- outreach */
/**
 * The language a message is written in unless the contact's data says another.
 *
 * pt-MZ, because the businesses being sold to are in Maputo and Matola and the
 * rest of the product already speaks it. A contact whose stored locale differs
 * overrides this; nothing else does, and in particular the provider's guess at
 * a country is not a statement about what language a person reads.
 */
exports.DEFAULT_OUTREACH_LOCALE = 'pt-MZ';
/**
 * How long a generated message may be, per channel.
 *
 * WhatsApp is the shortest because it is read on a phone between customers.
 * These are enforced on the model's output rather than requested in the
 * prompt: a model asked for 400 characters and given no check will sometimes
 * write 900, and the person reviewing it should not be the limit.
 */
exports.OUTREACH_MAX_CHARS = {
    WHATSAPP: 600,
    SMS: 300,
    EMAIL: 1400,
    LINKEDIN: 900,
};
function resolveProspectingFlags(environment) {
    const on = (value) => value === 'true';
    return {
        prospectingEnabled: on(environment.AI_PROSPECTING_ENABLED),
        // Defaults off in the example env, and stays off: automatic enrichment is
        // the one path that spends money without a person having asked for it.
        autoEnrichmentEnabled: on(environment.AUTO_ENRICHMENT_ENABLED),
        outreachEnabled: on(environment.AI_OUTREACH_ENABLED),
        apolloEnabled: on(environment.PROSPECTING_APOLLO_ENABLED),
        aisaEnabled: on(environment.PROSPECTING_AISA_ENABLED),
        placesEnabled: on(environment.PROSPECTING_PLACES_ENABLED),
    };
}
