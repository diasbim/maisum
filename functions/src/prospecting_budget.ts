import {
  ENRICHMENT_UNIT_COST_USD,
  ESTIMATES_VERIFIED,
  OPERATION_COST_USD,
  type ProspectingSettings,
} from './prospecting_config.js';
import type { ProviderOperation } from './prospecting_contracts.js';

/**
 * The guard in front of every paid call.
 *
 * "Never spend silently" is two obligations, and this file is the first:
 * nothing is charged that the configured caps do not admit, and the refusal
 * says which cap refused it. The second obligation — that every call that does
 * happen leaves a usage row with an estimated and an actual cost — belongs to
 * the store, which writes the row in the same transaction that consumes the
 * budget.
 *
 * Everything here is pure. The spend totals are passed in, so a test can put
 * the month at $49.99 and ask what a five-cent call does without an emulator,
 * and the transaction that actually reads those totals has no policy in it at
 * all.
 */

/* ------------------------------------------------------------------ period */

/**
 * Maputo, not UTC.
 *
 * A daily cap that resets at midnight UTC resets at two in the morning for the
 * person it constrains, which means a day's budget is spread over two of their
 * working days and the screen showing "spent today" disagrees with what they
 * did today. Mozambique is UTC+2 year round with no daylight saving, so a
 * fixed offset is correct rather than merely convenient.
 */
export const BUDGET_UTC_OFFSET_MINUTES = 120;

function localParts(atMillis: number): { year: number; month: number; day: number } {
  const shifted = new Date(atMillis + BUDGET_UTC_OFFSET_MINUTES * 60_000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/** `2026-09`, the key a month's spend is accumulated under. */
export function monthKey(atMillis: number): string {
  const { year, month } = localParts(atMillis);
  return `${year}-${String(month).padStart(2, '0')}`;
}

/** `2026-09-20`, the key a day's spend is accumulated under. */
export function dayKey(atMillis: number): string {
  const { year, month, day } = localParts(atMillis);
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/* ---------------------------------------------------------------- decision */

/**
 * Why a paid call was refused.
 *
 * Four reasons, and the UI says something different for each. `BELOW_THRESHOLD`
 * is not a budget problem at all — the lead simply is not worth paying for
 * yet, and telling an operator "budget reached" when the real answer is "this
 * lead scored 43" would send them to the settings screen to raise a cap that
 * was never the obstacle.
 */
export const SPEND_REFUSAL = [
  'BELOW_THRESHOLD',
  'MONTHLY_CAP',
  'DAILY_CAP',
  'PER_LEAD_CAP',
] as const;
export type SpendRefusal = (typeof SPEND_REFUSAL)[number];

export const SPEND_REFUSAL_MESSAGE: Record<SpendRefusal, string> = {
  BELOW_THRESHOLD:
    'Este negócio está abaixo da pontuação mínima para enriquecimento pago.',
  MONTHLY_CAP:
    'O orçamento mensal de prospeção foi atingido. O enriquecimento pago está em pausa.',
  DAILY_CAP:
    'O orçamento diário de prospeção foi atingido. Recomeça amanhã.',
  PER_LEAD_CAP:
    'Este negócio já atingiu o custo máximo por lead.',
};

export type SpendDecision =
  | { allowed: true; estimatedCostUsd: number }
  | {
      allowed: false;
      refusal: SpendRefusal;
      message: string;
      /** How much room is left under the cap that refused. Never negative. */
      remainingUsd: number;
    };

export type SpendRequest = {
  operation: ProviderOperation;
  /**
   * The lead's current score, or null for an operation that is not about one
   * lead — a discovery search has no score to be above.
   */
  leadScore: number | null;
  spentThisMonthUsd: number;
  spentTodayUsd: number;
  /** What this one lead has already cost. Zero for a search. */
  spentOnLeadUsd: number;
  settings: ProspectingSettings;
  /** Overrides the table, for an operation whose price the caller knows. */
  estimatedCostUsd?: number;
};

/**
 * Whether one paid call may happen.
 *
 * The checks run cheapest-refusal-first, and the order is not cosmetic: a lead
 * below the threshold is refused before the budget is even consulted, so a
 * screen full of low-scoring leads does not report a budget problem.
 *
 * Every cap is compared against the spend *after* this call, not before. A
 * month at $49.98 with a $50 cap admits a two-cent call and refuses a
 * five-cent one; the alternative — checking whether the cap is already reached
 * — permits a single call of any size to overshoot it, which for a bulk
 * enrichment of two hundred leads is not a rounding error.
 */
export function evaluateSpend(request: SpendRequest): SpendDecision {
  const { settings } = request;
  const estimatedCostUsd =
    request.estimatedCostUsd ?? OPERATION_COST_USD[request.operation];

  // Strictly above, not "at least". A lead sitting exactly on the threshold
  // is the case the threshold exists to decide, and a run against Maputo
  // showed which way it should fall: twenty discovered, every business with
  // no rating and no reviews scoring exactly the 60 it was being measured
  // against, and a gate that passed all twenty while reporting that it had
  // filtered. See `minScoreForEnrichment`.
  if (
    request.leadScore !== null &&
    request.leadScore <= settings.minScoreForEnrichment
  ) {
    return {
      allowed: false,
      refusal: 'BELOW_THRESHOLD',
      message: SPEND_REFUSAL_MESSAGE.BELOW_THRESHOLD,
      remainingUsd: 0,
    };
  }

  const caps: Array<{ refusal: SpendRefusal; spent: number; cap: number }> = [
    {
      refusal: 'PER_LEAD_CAP',
      spent: request.spentOnLeadUsd,
      cap: settings.maxEnrichmentCostPerLeadUsd,
    },
    {
      refusal: 'DAILY_CAP',
      spent: request.spentTodayUsd,
      cap: settings.dailyBudgetUsd,
    },
    {
      refusal: 'MONTHLY_CAP',
      spent: request.spentThisMonthUsd,
      cap: settings.monthlyBudgetUsd,
    },
  ];

  for (const entry of caps) {
    // A per-lead cap of zero is the one way to say "no paid enrichment at all",
    // and it must refuse rather than be treated as unset.
    if (round(entry.spent + estimatedCostUsd) > round(entry.cap)) {
      return {
        allowed: false,
        refusal: entry.refusal,
        message: SPEND_REFUSAL_MESSAGE[entry.refusal],
        remainingUsd: Math.max(0, round(entry.cap - entry.spent)),
      };
    }
  }

  return { allowed: true, estimatedCostUsd };
}

/**
 * Cents, kept as cents.
 *
 * Costs are added in floating point across hundreds of calls, and
 * `0.1 + 0.2 > 0.3` is enough to refuse a call that the cap admits or admit
 * one it does not. Rounding both sides of every comparison to the tenth of a
 * cent removes the whole class of problem without introducing a money type for
 * six additions.
 */
export function round(value: number): number {
  return Math.round(value * 10_000) / 10_000;
}

/* ---------------------------------------------------------------- estimate */

export type SearchEstimateInput = {
  maxLeads: number;
  minScore: number;
  settings: ProspectingSettings;
};

export type SearchEstimate = {
  /** Discovery only: every business found is searched for, none enriched. */
  minUsd: number;
  /** Every discovered business clears the threshold and is fully enriched. */
  maxUsd: number;
  /** The share assumed to clear the threshold, for the mid figure. */
  assumedQualifyRate: number;
  likelyUsd: number;
  /**
   * False while the unit prices have not been checked against an invoice. The
   * screen shows the caveat rather than the number alone.
   */
  verified: boolean;
  /**
   * What actually limits the spend, whatever the estimate turns out to be.
   *
   * The cap only, never what is left of it: this function is given settings
   * and not the month's spend, so any "remaining" it produced would be the
   * full budget every time — a figure that reads like an answer and is wrong
   * by exactly the amount already spent. The caller holds the spend and
   * computes it there.
   */
  monthlyBudgetUsd: number;
};

/**
 * What a search might cost, as a range.
 *
 * A point estimate would be a fiction: the cost depends on how many of the
 * discovered businesses clear the score threshold, which is not knowable until
 * they have been discovered and scored — and scoring is free. So the floor is
 * discovery alone and the ceiling is everything enriched, with a middle figure
 * that states the assumption it rests on rather than hiding it.
 *
 * `assumedQualifyRate` moves with the threshold because it must: asking for
 * leads scoring 80+ will qualify far fewer of the same discovered businesses
 * than asking for 40+. The rates are judgement, not measurement, and they are
 * the first thing to replace once a month of real runs exists.
 */
/**
 * How many discovered leads are assumed to clear the threshold, by threshold.
 *
 * A step table rather than a curve, and exported rather than inlined for two
 * reasons: these are assumptions an operator is entitled to disagree with, and
 * the console recomputes the estimate as the form changes. Sending it the
 * table instead of a second copy of these numbers is what keeps the two from
 * drifting — the console owns the arithmetic, never the constants.
 *
 * Ordered high to low; the first threshold the score meets wins.
 */
export const QUALIFY_RATE_BY_MIN_SCORE: ReadonlyArray<{
  minScore: number;
  rate: number;
}> = [
  { minScore: 80, rate: 0.1 },
  { minScore: 70, rate: 0.2 },
  { minScore: 60, rate: 0.35 },
  { minScore: 0, rate: 0.6 },
];

export function qualifyRateFor(minScore: number): number {
  return (
    QUALIFY_RATE_BY_MIN_SCORE.find((entry) => minScore >= entry.minScore)?.rate ?? 0.6
  );
}

export function estimateSearchCost(input: SearchEstimateInput): SearchEstimate {
  const leads = Math.max(0, Math.floor(input.maxLeads));
  const discovery = round(leads * OPERATION_COST_USD.SEARCH_BUSINESSES);
  const fullEnrichment = round(leads * ENRICHMENT_UNIT_COST_USD);

  const assumedQualifyRate = qualifyRateFor(input.minScore);

  return {
    minUsd: discovery,
    maxUsd: round(discovery + fullEnrichment),
    assumedQualifyRate,
    likelyUsd: round(discovery + fullEnrichment * assumedQualifyRate),
    verified: ESTIMATES_VERIFIED,
    monthlyBudgetUsd: input.settings.monthlyBudgetUsd,
  };
}

/* ------------------------------------------------------------------- usage */

/**
 * One paid call, as it is stored.
 *
 * `estimatedCost` and `actualCost` are both kept, and they are different
 * numbers. The estimate is what the guard above admitted; the actual is what
 * the provider reported, which for most providers is absent — in which case
 * `actualCost` stays null and the month's total is computed from estimates,
 * with the screen saying so. Overwriting the estimate with itself and calling
 * it actual would turn a guess into a figure somebody plans against.
 *
 * A failed call still writes a row. Providers charge for calls that return
 * nothing, and a usage log that only recorded successes would understate the
 * month by exactly the amount nobody expected to be spending.
 */
export type EnrichmentUsage = {
  id: string;
  provider: string;
  operation: ProviderOperation;
  prospect_id: string | null;
  estimated_cost: number;
  actual_cost: number | null;
  credits_used: number | null;
  success: boolean;
  error_code: string | null;
  correlation_id: string;
  month_key: string;
  day_key: string;
  created_at: number;
};

/** What a month's rows add up to. Estimates when the provider reported none. */
export function totalSpend(rows: readonly EnrichmentUsage[]): number {
  return round(
    rows.reduce((sum, row) => sum + (row.actual_cost ?? row.estimated_cost), 0),
  );
}

/** True when any row in the period lacked a reported cost. */
export function spendIsEstimated(rows: readonly EnrichmentUsage[]): boolean {
  return rows.some((row) => row.actual_cost === null);
}
