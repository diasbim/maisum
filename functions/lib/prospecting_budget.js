"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SPEND_REFUSAL_MESSAGE = exports.SPEND_REFUSAL = exports.BUDGET_UTC_OFFSET_MINUTES = void 0;
exports.monthKey = monthKey;
exports.dayKey = dayKey;
exports.evaluateSpend = evaluateSpend;
exports.round = round;
exports.estimateSearchCost = estimateSearchCost;
exports.totalSpend = totalSpend;
exports.spendIsEstimated = spendIsEstimated;
const prospecting_config_js_1 = require("./prospecting_config.js");
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
exports.BUDGET_UTC_OFFSET_MINUTES = 120;
function localParts(atMillis) {
    const shifted = new Date(atMillis + exports.BUDGET_UTC_OFFSET_MINUTES * 60000);
    return {
        year: shifted.getUTCFullYear(),
        month: shifted.getUTCMonth() + 1,
        day: shifted.getUTCDate(),
    };
}
/** `2026-09`, the key a month's spend is accumulated under. */
function monthKey(atMillis) {
    const { year, month } = localParts(atMillis);
    return `${year}-${String(month).padStart(2, '0')}`;
}
/** `2026-09-20`, the key a day's spend is accumulated under. */
function dayKey(atMillis) {
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
exports.SPEND_REFUSAL = [
    'BELOW_THRESHOLD',
    'MONTHLY_CAP',
    'DAILY_CAP',
    'PER_LEAD_CAP',
];
exports.SPEND_REFUSAL_MESSAGE = {
    BELOW_THRESHOLD: 'Este negócio está abaixo da pontuação mínima para enriquecimento pago.',
    MONTHLY_CAP: 'O orçamento mensal de prospeção foi atingido. O enriquecimento pago está em pausa.',
    DAILY_CAP: 'O orçamento diário de prospeção foi atingido. Recomeça amanhã.',
    PER_LEAD_CAP: 'Este negócio já atingiu o custo máximo por lead.',
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
function evaluateSpend(request) {
    const { settings } = request;
    const estimatedCostUsd = request.estimatedCostUsd ?? prospecting_config_js_1.OPERATION_COST_USD[request.operation];
    if (request.leadScore !== null &&
        request.leadScore < settings.minScoreForEnrichment) {
        return {
            allowed: false,
            refusal: 'BELOW_THRESHOLD',
            message: exports.SPEND_REFUSAL_MESSAGE.BELOW_THRESHOLD,
            remainingUsd: 0,
        };
    }
    const caps = [
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
                message: exports.SPEND_REFUSAL_MESSAGE[entry.refusal],
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
function round(value) {
    return Math.round(value * 10000) / 10000;
}
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
function estimateSearchCost(input) {
    const leads = Math.max(0, Math.floor(input.maxLeads));
    const discovery = round(leads * prospecting_config_js_1.OPERATION_COST_USD.SEARCH_BUSINESSES);
    const fullEnrichment = round(leads * prospecting_config_js_1.ENRICHMENT_UNIT_COST_USD);
    const assumedQualifyRate = input.minScore >= 80 ? 0.1 : input.minScore >= 70 ? 0.2 : input.minScore >= 60 ? 0.35 : 0.6;
    return {
        minUsd: discovery,
        maxUsd: round(discovery + fullEnrichment),
        assumedQualifyRate,
        likelyUsd: round(discovery + fullEnrichment * assumedQualifyRate),
        verified: prospecting_config_js_1.ESTIMATES_VERIFIED,
        monthlyBudgetUsd: input.settings.monthlyBudgetUsd,
    };
}
/** What a month's rows add up to. Estimates when the provider reported none. */
function totalSpend(rows) {
    return round(rows.reduce((sum, row) => sum + (row.actual_cost ?? row.estimated_cost), 0));
}
/** True when any row in the period lacked a reported cost. */
function spendIsEstimated(rows) {
    return rows.some((row) => row.actual_cost === null);
}
