"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DISQUALIFY_REASON_LABEL = exports.DISQUALIFY_REASON = exports.SCORE_DIMENSION_LABEL = exports.SCORE_DIMENSION = exports.UNKNOWN_SIGNALS = void 0;
exports.isTargetGeography = isTargetGeography;
exports.scoreProspect = scoreProspect;
exports.qualify = qualify;
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_normalization_js_1 = require("./prospecting_normalization.js");
/**
 * The signals for a business nothing is known about yet.
 *
 * Every observation is `null` and every count is zero, so a lead that has only
 * been discovered scores whatever its trade and its city are worth and nothing
 * more. Callers spread this and override, which means a field added to the
 * type cannot be silently forgotten by an existing caller.
 */
exports.UNKNOWN_SIGNALS = {
    businessType: null,
    employeeCount: null,
    city: null,
    province: null,
    country: null,
    websiteUrl: null,
    socialProfileCount: 0,
    hasContactChannel: false,
    runsPromotions: null,
    loyaltyUseCase: null,
    growthSignal: null,
    decisionMakerIdentified: false,
    reachableContact: false,
    rating: null,
    reviewCount: null,
    hasOpeningHours: null,
    hasPhotos: null,
    isOperational: null,
};
/* ---------------------------------------------------------------- outputs */
exports.SCORE_DIMENSION = [
    'BUSINESS_FIT',
    'DIGITAL_PRESENCE',
    'RETENTION_POTENTIAL',
    'COMMERCIAL_OPPORTUNITY',
];
exports.SCORE_DIMENSION_LABEL = {
    BUSINESS_FIT: 'Encaixe do negócio',
    DIGITAL_PRESENCE: 'Presença digital',
    RETENTION_POTENTIAL: 'Potencial de retenção',
    COMMERCIAL_OPPORTUNITY: 'Oportunidade comercial',
};
/* ---------------------------------------------------------------- helpers */
function criterion(input) {
    const known = input.met !== null;
    return {
        key: input.key,
        label: input.label,
        dimension: input.dimension,
        points: input.points,
        awarded: input.met === true ? input.points : 0,
        basis: known ? (input.basis ?? 'FACT') : 'UNKNOWN',
        evidence: known ? (input.evidence ?? null) : null,
    };
}
/**
 * A dimension's contribution, capped, with the switched-off criteria dropped.
 *
 * The cap is applied to the sum rather than trusted to the criteria adding up,
 * because the config permits a table whose criteria exceed its own maximum and
 * a score above the dimension's stated ceiling would break every band.
 *
 * A criterion worth zero points is removed rather than scored. Zero is how the
 * config turns a criterion off — see `DEFAULT_SCORING` — and a disabled
 * criterion has no business in the breakdown: it would show as a row worth
 * nothing, usually marked UNKNOWN, telling an operator about a gap they cannot
 * close and the module no longer cares about. It would also inflate
 * `unknowns`, which is read as a to-do list.
 */
function dimension(name, max, criteria) {
    const active = criteria.filter((entry) => entry.points > 0);
    const raw = active.reduce((sum, entry) => sum + entry.awarded, 0);
    return {
        dimension: name,
        score: Math.max(0, Math.min(max, raw)),
        max,
        criteria: active,
    };
}
/**
 * Whether a place is one MaisUm currently sells in.
 *
 * City first, then province, so a lead in a Matola suburb the city list does
 * not enumerate still counts through "Maputo" province. The country is checked
 * only when it is stated: a provider that returns no country for a business
 * whose city is Maputo has not said the business is elsewhere.
 */
function isTargetGeography(signals, geography) {
    const city = (0, prospecting_normalization_js_1.normalizeCity)(signals.city);
    const province = (0, prospecting_normalization_js_1.normalizeCity)(signals.province);
    const country = (0, prospecting_normalization_js_1.normalizeCity)(signals.country);
    if (city === '' && province === '' && country === '')
        return null;
    if (country !== '') {
        const target = (0, prospecting_normalization_js_1.normalizeCity)(geography.country);
        const code = geography.countryCode.toLowerCase();
        if (country !== target && country !== code)
            return false;
    }
    if (city !== '' && geography.cities.some((entry) => (0, prospecting_normalization_js_1.normalizeCity)(entry) === city)) {
        return true;
    }
    if (province !== '' &&
        geography.provinces.some((entry) => (0, prospecting_normalization_js_1.normalizeCity)(entry) === province)) {
        return true;
    }
    // The country matched but neither the city nor the province did, or neither
    // was stated. Not target geography, and not unknown either — something about
    // the place was known and it did not match.
    return false;
}
/* ------------------------------------------------------------------ engine */
function scoreProspect(signals, config, geography) {
    const icp = (0, prospecting_config_js_1.findIcpIndustry)(signals.businessType);
    const fit = config.businessFit;
    const digital = config.digitalPresence;
    const retention = config.retentionPotential;
    const commercial = config.commercialOpportunity;
    const businessFit = dimension('BUSINESS_FIT', fit.max, [
        criterion({
            key: 'target_industry',
            label: 'Setor-alvo',
            dimension: 'BUSINESS_FIT',
            points: fit.targetIndustry,
            met: signals.businessType === null ? null : icp !== null,
            evidence: icp !== null ? `${icp.label} (tier ${icp.tier})` : signals.businessType,
        }),
        criterion({
            key: 'recurring_customer_model',
            label: 'Cliente que volta',
            dimension: 'BUSINESS_FIT',
            points: fit.recurringCustomerModel,
            met: icp === null ? null : icp.recurringModel,
            // True of the trade, not observed at this shop.
            basis: 'INFERENCE',
            evidence: icp !== null ? `${icp.label} tem clientes recorrentes` : null,
        }),
        criterion({
            key: 'employee_count',
            label: `Entre ${fit.employeeRange.min} e ${fit.employeeRange.max} pessoas`,
            dimension: 'BUSINESS_FIT',
            points: fit.employeeCountInRange,
            met: signals.employeeCount === null
                ? null
                : signals.employeeCount >= fit.employeeRange.min &&
                    signals.employeeCount <= fit.employeeRange.max,
            evidence: signals.employeeCount === null
                ? null
                : `${signals.employeeCount} pessoas`,
        }),
        criterion({
            key: 'target_geography',
            label: 'Geografia-alvo',
            dimension: 'BUSINESS_FIT',
            points: fit.targetGeography,
            met: isTargetGeography(signals, geography),
            evidence: [signals.city, signals.province, signals.country]
                .filter((part) => typeof part === 'string' && part.trim() !== '')
                .join(', ') || null,
        }),
        criterion({
            key: 'rating_at_least',
            label: `Avaliação ${fit.minRating.toFixed(1)} ou mais`,
            dimension: 'BUSINESS_FIT',
            points: fit.ratingAtLeast,
            // A rating says the business is worth walking into, which is what makes
            // it worth selling to. Not a judgement about the shop's quality — a
            // filter against listings that are dead or disputed.
            met: signals.rating === null ? null : signals.rating >= fit.minRating,
            evidence: signals.rating === null ? null : `${signals.rating.toFixed(1)} / 5`,
        }),
    ]);
    const hasWebsite = signals.websiteUrl !== null && signals.websiteUrl.trim() !== '';
    const digitalPresence = dimension('DIGITAL_PRESENCE', digital.max, [
        criterion({
            key: 'website',
            label: 'Tem site',
            dimension: 'DIGITAL_PRESENCE',
            points: digital.website,
            // Absence of a website is a finding, not a gap in knowledge: discovery
            // looks for one, and not finding one is the answer.
            met: hasWebsite,
            evidence: signals.websiteUrl,
        }),
        criterion({
            key: 'active_social',
            label: 'Redes sociais',
            dimension: 'DIGITAL_PRESENCE',
            points: digital.activeSocial,
            met: signals.socialProfileCount > 0,
            evidence: `${signals.socialProfileCount} perfis`,
        }),
        criterion({
            key: 'contact_channel',
            label: 'Canal de contacto público',
            dimension: 'DIGITAL_PRESENCE',
            points: digital.contactChannel,
            met: signals.hasContactChannel,
            evidence: null,
        }),
        criterion({
            key: 'strong_presence',
            label: 'Presença consolidada',
            dimension: 'DIGITAL_PRESENCE',
            points: digital.strongPresence,
            met: hasWebsite && signals.socialProfileCount >= digital.strongPresenceProfiles,
            evidence: `site ${hasWebsite ? 'sim' : 'não'}, ${signals.socialProfileCount} perfis`,
        }),
        criterion({
            key: 'opening_hours',
            label: 'Horário publicado',
            dimension: 'DIGITAL_PRESENCE',
            points: digital.openingHours,
            // A timetable is somebody maintaining the listing. A shop that keeps its
            // hours current is a shop that answers the number printed beside them.
            met: signals.hasOpeningHours,
            evidence: null,
        }),
        criterion({
            key: 'photos',
            label: 'Fotografias do espaço',
            dimension: 'DIGITAL_PRESENCE',
            points: digital.photos,
            met: signals.hasPhotos,
            evidence: null,
        }),
    ]);
    /**
     * Review count as evidence of traffic, one criterion per threshold.
     *
     * Generated from the table rather than written out, because the thresholds
     * are the numbers most likely to move once a campaign has run against real
     * Maputo listings — and a threshold that takes a deploy to change is a
     * threshold nobody changes.
     *
     * What this measures is how many customers pass through, not how good the
     * shop is: a barbershop with thirty reviews has thirty people worth bringing
     * back, which is the entire product. The rating criterion above is the
     * quality question, and it is deliberately a separate five points.
     */
    const reviewCriteria = retention.reviewThresholds.map((threshold) => criterion({
        key: `review_volume_${threshold}`,
        label: `${threshold} ou mais avaliações`,
        dimension: 'RETENTION_POTENTIAL',
        points: retention.reviewVolume,
        met: signals.reviewCount === null ? null : signals.reviewCount >= threshold,
        evidence: signals.reviewCount === null ? null : `${signals.reviewCount} avaliações`,
    }));
    const retentionPotential = dimension('RETENTION_POTENTIAL', retention.max, [
        criterion({
            key: 'recurring_service',
            label: 'Serviço recorrente',
            dimension: 'RETENTION_POTENTIAL',
            points: retention.recurringService,
            met: icp === null ? null : icp.recurringModel,
            basis: 'INFERENCE',
            evidence: icp !== null ? `${icp.label}` : null,
        }),
        criterion({
            key: 'multiple_services',
            label: 'Vários serviços',
            dimension: 'RETENTION_POTENTIAL',
            points: retention.multipleServices,
            met: icp === null ? null : icp.multipleServices,
            basis: 'INFERENCE',
            evidence: icp !== null ? `${icp.label}` : null,
        }),
        criterion({
            key: 'promotions',
            label: 'Faz promoções',
            dimension: 'RETENTION_POTENTIAL',
            points: retention.promotions,
            met: signals.runsPromotions,
            evidence: null,
        }),
        criterion({
            key: 'loyalty_use_case',
            label: 'Caso de uso de fidelização',
            dimension: 'RETENTION_POTENTIAL',
            points: retention.loyaltyUseCase,
            /**
             * Observed if anything observed it; inferred from the trade otherwise.
             *
             * This used to read the signal alone, which meant it was UNKNOWN for
             * every lead once web research stopped running. But a trade that sells
             * the same thing repeatedly *and* sells more than one thing has
             * something a points scheme can reward — that is a fact about
             * barbershops, and the ICP table already states both halves of it.
             * `??` and not `||`, so an explicit "no" from a source that looked
             * survives rather than being overruled by the table.
             */
            met: signals.loyaltyUseCase ??
                (icp === null ? null : icp.recurringModel && icp.multipleServices),
            basis: signals.loyaltyUseCase === null ? 'INFERENCE' : 'FACT',
            evidence: signals.loyaltyUseCase === null && icp !== null ? icp.label : null,
        }),
        ...reviewCriteria,
    ]);
    const commercialOpportunity = dimension('COMMERCIAL_OPPORTUNITY', commercial.max, [
        criterion({
            key: 'decision_maker',
            label: 'Decisor identificado',
            dimension: 'COMMERCIAL_OPPORTUNITY',
            points: commercial.decisionMakerIdentified,
            met: signals.decisionMakerIdentified,
            evidence: null,
        }),
        criterion({
            key: 'reachable_contact',
            label: 'Contacto utilizável',
            dimension: 'COMMERCIAL_OPPORTUNITY',
            points: commercial.reachableContact,
            met: signals.reachableContact,
            evidence: null,
        }),
        criterion({
            key: 'growth_signal',
            label: 'Sinal de crescimento',
            dimension: 'COMMERCIAL_OPPORTUNITY',
            points: commercial.growthSignal,
            met: signals.growthSignal,
            evidence: null,
        }),
        criterion({
            key: 'operational',
            label: 'Negócio em atividade',
            dimension: 'COMMERCIAL_OPPORTUNITY',
            points: commercial.operational,
            // Cheap and decisive: a listing marked closed is a lead that costs a
            // call to discover is worthless. Scored rather than disqualified,
            // because "temporarily closed" is a real state for a shop that
            // reopens, and throwing it away would lose it permanently.
            met: signals.isOperational,
            evidence: null,
        }),
    ]);
    const dimensions = [
        businessFit,
        digitalPresence,
        retentionPotential,
        commercialOpportunity,
    ];
    const total = dimensions.reduce((sum, entry) => sum + entry.score, 0);
    return {
        total,
        band: (0, prospecting_config_js_1.bandFor)(total, config),
        businessFit: businessFit.score,
        digitalPresence: digitalPresence.score,
        retentionPotential: retentionPotential.score,
        commercialOpportunity: commercialOpportunity.score,
        dimensions,
        unknowns: dimensions
            .flatMap((entry) => entry.criteria)
            .filter((entry) => entry.basis === 'UNKNOWN')
            .map((entry) => entry.label),
    };
}
/* -------------------------------------------------------------- qualifying */
/**
 * Why a discovered business is not worth scoring at all.
 *
 * Qualification runs before scoring and is cheap and absolute, where scoring
 * is graded. A business outside the target country is not a low-scoring lead,
 * it is not a lead; spending an analysis call to discover that would be
 * spending money to learn something the address already said.
 */
exports.DISQUALIFY_REASON = [
    'OUT_OF_GEOGRAPHY',
    'NOT_TARGET_INDUSTRY',
    'NO_IDENTIFYING_DATA',
];
exports.DISQUALIFY_REASON_LABEL = {
    OUT_OF_GEOGRAPHY: 'Fora da geografia-alvo',
    NOT_TARGET_INDUSTRY: 'Setor fora do perfil',
    NO_IDENTIFYING_DATA: 'Sem dados que identifiquem o negócio',
};
/**
 * Whether a discovered business enters the pipeline.
 *
 * Deliberately lenient on the two things that are commonly unknown at
 * discovery. A business whose trade the provider did not state is *not*
 * disqualified — it is scored without the industry points, and an operator can
 * see that the trade is unknown. Only a stated, non-ICP trade is refused.
 * Rejecting on absence would throw away the leads that are hardest to find and
 * therefore least likely to already be somebody's customer.
 */
function qualify(signals, geography) {
    if (signals.name === null || signals.name.trim() === '') {
        return { qualified: false, reason: 'NO_IDENTIFYING_DATA' };
    }
    if (isTargetGeography(signals, geography) === false) {
        return { qualified: false, reason: 'OUT_OF_GEOGRAPHY' };
    }
    if (signals.businessType !== null && (0, prospecting_config_js_1.findIcpIndustry)(signals.businessType) === null) {
        return { qualified: false, reason: 'NOT_TARGET_INDUSTRY' };
    }
    return { qualified: true };
}
