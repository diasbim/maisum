import {
  bandFor,
  findIcpIndustry,
  type ScoreBand,
  type ScoringConfig,
  type TargetGeography,
} from './prospecting_config.js';
import { normalizeCity } from './prospecting_normalization.js';
import type { ClaimType } from './prospecting_contracts.js';

/**
 * The scoring engine.
 *
 * Pure, in the strict sense: it reads its inputs and its config and returns a
 * number and a list of reasons. It touches no clock, no database and no
 * provider, which is what lets `prospecting_scoring.test.ts` check every
 * criterion in isolation rather than asserting about a total.
 *
 * The output is a breakdown, not a score. Four numbers and a band would be a
 * verdict an operator has to take on trust; the breakdown says which criteria
 * fired, what each was worth, and — for every one that did not — whether it
 * was *not true* or merely *not known*. That distinction is the module's whole
 * discipline, and it has to survive into the score rather than being stated
 * next to it: a business with no known employee count and a business known to
 * have two hundred employees both score zero on that criterion, and an
 * operator deciding whether to spend money on the lead needs to know which one
 * they are looking at.
 */

/* ----------------------------------------------------------------- inputs */

/**
 * What is known about a business, as three-valued facts.
 *
 * `null` means unknown, and is never read as false. That is why the booleans
 * that come from observation are `boolean | null` while the ones derived from
 * the ICP table are plain booleans — the table is a fact about the trade and
 * is always known once the trade is.
 */
export type ScoringSignals = {
  /** Matches `businesses.business_type`; null when the trade is unknown. */
  businessType: string | null;
  employeeCount: number | null;
  city: string | null;
  province: string | null;
  country: string | null;

  websiteUrl: string | null;
  /** Distinct social profiles found, not guessed at. */
  socialProfileCount: number;
  /** A phone, WhatsApp or verified email the business publishes. */
  hasContactChannel: boolean;

  /** Observed on a page or a profile. Null when nothing was looked at. */
  runsPromotions: boolean | null;
  /** The trade has something a loyalty scheme can reward. Null when unknown. */
  loyaltyUseCase: boolean | null;
  /** Hiring, a new branch, a funding note. Null when nothing was looked at. */
  growthSignal: boolean | null;

  decisionMakerIdentified: boolean;
  /** A contact with a verified email or a phone. Guessed emails do not count. */
  reachableContact: boolean;

  /**
   * The public rating, 0–5, or null when the listing carries none.
   *
   * Null is not a bad rating. A shop with no reviews yet and a shop rated 2.1
   * are different businesses, and the three-valued discipline that governs
   * every other signal governs these four too.
   */
  rating: number | null;
  /** How many people rated it. Evidence of customer traffic, not of quality. */
  reviewCount: number | null;
  /** A published timetable. Null when the listing was not read. */
  hasOpeningHours: boolean | null;
  hasPhotos: boolean | null;
  /** Trading, as opposed to closed or moved. Null when not stated. */
  isOperational: boolean | null;
};

/**
 * The signals for a business nothing is known about yet.
 *
 * Every observation is `null` and every count is zero, so a lead that has only
 * been discovered scores whatever its trade and its city are worth and nothing
 * more. Callers spread this and override, which means a field added to the
 * type cannot be silently forgotten by an existing caller.
 */
export const UNKNOWN_SIGNALS: ScoringSignals = {
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

export const SCORE_DIMENSION = [
  'BUSINESS_FIT',
  'DIGITAL_PRESENCE',
  'RETENTION_POTENTIAL',
  'COMMERCIAL_OPPORTUNITY',
] as const;
export type ScoreDimension = (typeof SCORE_DIMENSION)[number];

export const SCORE_DIMENSION_LABEL: Record<ScoreDimension, string> = {
  BUSINESS_FIT: 'Encaixe do negócio',
  DIGITAL_PRESENCE: 'Presença digital',
  RETENTION_POTENTIAL: 'Potencial de retenção',
  COMMERCIAL_OPPORTUNITY: 'Oportunidade comercial',
};

/**
 * One criterion, and why it did or did not count.
 *
 * `basis` is the three-valued answer: `FACT` when the input was known and the
 * criterion was evaluated against it, `UNKNOWN` when the input was absent.
 * `INFERENCE` is used where the criterion is true of the trade rather than of
 * this shop — "barbershops have returning customers" is a sound inference from
 * a known business type, and labelling it a fact about *this* barbershop would
 * be the exact overreach the module is built to avoid.
 */
export type CriterionResult = {
  key: string;
  label: string;
  dimension: ScoreDimension;
  /** What the criterion is worth when it fires. */
  points: number;
  /** What it contributed. Zero when it did not fire. */
  awarded: number;
  basis: ClaimType;
  /** What the decision was made from. Null when nothing was known. */
  evidence: string | null;
};

export type DimensionScore = {
  dimension: ScoreDimension;
  score: number;
  max: number;
  criteria: CriterionResult[];
};

export type ScoreResult = {
  total: number;
  band: ScoreBand;
  businessFit: number;
  digitalPresence: number;
  retentionPotential: number;
  commercialOpportunity: number;
  dimensions: DimensionScore[];
  /** Criteria that could not be evaluated, for the "what we don't know" panel. */
  unknowns: string[];
};

/* ---------------------------------------------------------------- helpers */

function criterion(
  input: {
    key: string;
    label: string;
    dimension: ScoreDimension;
    points: number;
    /** True fires, false does not, null means the input was unknown. */
    met: boolean | null;
    basis?: ClaimType;
    evidence?: string | null;
  },
): CriterionResult {
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
function dimension(
  name: ScoreDimension,
  max: number,
  criteria: CriterionResult[],
): DimensionScore {
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
export function isTargetGeography(
  signals: Pick<ScoringSignals, 'city' | 'province' | 'country'>,
  geography: TargetGeography,
): boolean | null {
  const city = normalizeCity(signals.city);
  const province = normalizeCity(signals.province);
  const country = normalizeCity(signals.country);

  if (city === '' && province === '' && country === '') return null;

  if (country !== '') {
    const target = normalizeCity(geography.country);
    const code = geography.countryCode.toLowerCase();
    if (country !== target && country !== code) return false;
  }

  if (city !== '' && geography.cities.some((entry) => normalizeCity(entry) === city)) {
    return true;
  }
  if (
    province !== '' &&
    geography.provinces.some((entry) => normalizeCity(entry) === province)
  ) {
    return true;
  }

  // The country matched but neither the city nor the province did, or neither
  // was stated. Not target geography, and not unknown either — something about
  // the place was known and it did not match.
  return false;
}

/* ------------------------------------------------------------------ engine */

export function scoreProspect(
  signals: ScoringSignals,
  config: ScoringConfig,
  geography: TargetGeography,
): ScoreResult {
  const icp = findIcpIndustry(signals.businessType);
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
      met:
        signals.employeeCount === null
          ? null
          : signals.employeeCount >= fit.employeeRange.min &&
            signals.employeeCount <= fit.employeeRange.max,
      evidence:
        signals.employeeCount === null
          ? null
          : `${signals.employeeCount} pessoas`,
    }),
    criterion({
      key: 'target_geography',
      label: 'Geografia-alvo',
      dimension: 'BUSINESS_FIT',
      points: fit.targetGeography,
      met: isTargetGeography(signals, geography),
      evidence:
        [signals.city, signals.province, signals.country]
          .filter((part): part is string => typeof part === 'string' && part.trim() !== '')
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
      met:
        hasWebsite && signals.socialProfileCount >= digital.strongPresenceProfiles,
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
  const reviewCriteria = retention.reviewThresholds.map((threshold) =>
    criterion({
      key: `review_volume_${threshold}`,
      label: `${threshold} ou mais avaliações`,
      dimension: 'RETENTION_POTENTIAL',
      points: retention.reviewVolume,
      met: signals.reviewCount === null ? null : signals.reviewCount >= threshold,
      evidence:
        signals.reviewCount === null ? null : `${signals.reviewCount} avaliações`,
    }),
  );

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
      met:
        signals.loyaltyUseCase ??
        (icp === null ? null : icp.recurringModel && icp.multipleServices),
      basis: signals.loyaltyUseCase === null ? 'INFERENCE' : 'FACT',
      evidence: signals.loyaltyUseCase === null && icp !== null ? icp.label : null,
    }),
    ...reviewCriteria,
  ]);

  const commercialOpportunity = dimension(
    'COMMERCIAL_OPPORTUNITY',
    commercial.max,
    [
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
    ],
  );

  const dimensions = [
    businessFit,
    digitalPresence,
    retentionPotential,
    commercialOpportunity,
  ];
  const total = dimensions.reduce((sum, entry) => sum + entry.score, 0);

  return {
    total,
    band: bandFor(total, config),
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
export const DISQUALIFY_REASON = [
  'OUT_OF_GEOGRAPHY',
  'NOT_TARGET_INDUSTRY',
  'NO_IDENTIFYING_DATA',
] as const;
export type DisqualifyReason = (typeof DISQUALIFY_REASON)[number];

export const DISQUALIFY_REASON_LABEL: Record<DisqualifyReason, string> = {
  OUT_OF_GEOGRAPHY: 'Fora da geografia-alvo',
  NOT_TARGET_INDUSTRY: 'Setor fora do perfil',
  NO_IDENTIFYING_DATA: 'Sem dados que identifiquem o negócio',
};

export type QualificationResult =
  | { qualified: true }
  | { qualified: false; reason: DisqualifyReason };

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
export function qualify(
  signals: Pick<
    ScoringSignals,
    'businessType' | 'city' | 'province' | 'country'
  > & { name: string | null },
  geography: TargetGeography,
): QualificationResult {
  if (signals.name === null || signals.name.trim() === '') {
    return { qualified: false, reason: 'NO_IDENTIFYING_DATA' };
  }

  if (isTargetGeography(signals, geography) === false) {
    return { qualified: false, reason: 'OUT_OF_GEOGRAPHY' };
  }

  if (signals.businessType !== null && findIcpIndustry(signals.businessType) === null) {
    return { qualified: false, reason: 'NOT_TARGET_INDUSTRY' };
  }

  return { qualified: true };
}
