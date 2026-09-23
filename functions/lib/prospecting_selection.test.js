"use strict";
/**
 * Who gets the paid slots — the whole pipeline's money decision, in one test.
 *
 * Deduplication, the gate and the ranking are each tested on their own. This
 * asserts what they do together over the twenty listings of the real Maputo
 * run, because that is the thing that went wrong: every part behaved as
 * written and the five paid calls still bought three businesses.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const prospecting_dedup_fixture_js_1 = require("./prospecting_dedup_fixture.js");
const prospecting_dedup_js_1 = require("./prospecting_dedup.js");
const prospecting_scoring_js_1 = require("./prospecting_scoring.js");
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_budget_js_1 = require("./prospecting_budget.js");
const SLOTS = 5;
const DETAIL_COST = prospecting_config_js_1.OPERATION_COST_USD.FETCH_LISTING_DETAILS;
/** Discovery through to the ranked list of leads worth paying for. */
function selection() {
    const { kept, duplicates } = (0, prospecting_dedup_js_1.dedupeCandidates)(prospecting_dedup_fixture_js_1.MAPUTO_RUN, {
        radiusMetres: prospecting_config_js_1.DEFAULT_SETTINGS.dedupRadiusMetres,
    });
    const meanRating = (0, prospecting_scoring_js_1.meanRatingOf)(kept);
    const context = {
        meanRating,
        priorCount: prospecting_config_js_1.DEFAULT_SETTINGS.bayesianPriorCount,
        noRatingPenalty: prospecting_config_js_1.DEFAULT_SETTINGS.noRatingPenalty,
    };
    const scored = kept.map((row) => ({
        row,
        score: (0, prospecting_scoring_js_1.scoreProspect)({
            ...prospecting_scoring_js_1.UNKNOWN_SIGNALS,
            businessType: 'barbershop',
            city: 'Maputo',
            country: prospecting_config_js_1.DEFAULT_GEOGRAPHY.country,
            rating: row.rating,
            reviewCount: row.reviewCount,
            isOperational: true,
        }, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, context),
    }));
    const passing = scored.filter((entry) => (0, prospecting_budget_js_1.evaluateSpend)({
        operation: 'FETCH_LISTING_DETAILS',
        leadScore: entry.score.total,
        settings: prospecting_config_js_1.DEFAULT_SETTINGS,
        spentThisMonthUsd: 0,
        spentTodayUsd: 0,
        spentOnLeadUsd: 0,
    }).allowed);
    passing.sort((left, right) => (0, prospecting_scoring_js_1.compareForRank)({
        score: left.score.total,
        reviewCount: left.row.reviewCount,
        rating: left.row.rating,
        name: left.row.name,
    }, {
        score: right.score.total,
        reviewCount: right.row.reviewCount,
        rating: right.row.rating,
        name: right.row.name,
    }));
    return { duplicates, scored, passing, rejected: scored.length - passing.length };
}
(0, node_test_1.default)('the five paid slots go to five different businesses', () => {
    // Before: three of the five were the same shop, reached through three
    // spellings of its apostrophe, and $0.06 of $0.17 bought one phone number.
    const slots = selection().passing.slice(0, SLOTS);
    const distinct = new Set(slots.map((entry) => (0, prospecting_dedup_js_1.matchName)(entry.row.name)));
    strict_1.default.equal(slots.length, SLOTS);
    strict_1.default.equal(distinct.size, SLOTS);
});
(0, node_test_1.default)('the businesses the old run skipped are now inside the slots', () => {
    // Tchetcho's carries 107 reviews and was skipped in favour of a duplicate.
    const names = selection()
        .passing.slice(0, SLOTS)
        .map((entry) => entry.row.name);
    for (const expected of ['Tchetcho', 'Tsemeta', 'KUBILA', 'Gentleman']) {
        strict_1.default.ok(names.some((name) => name.includes(expected)), `${expected} devia estar entre os pagos: ${names.join(', ')}`);
    }
});
(0, node_test_1.default)('a business with no reviews does not reach the paid stage', () => {
    const { passing } = selection();
    for (const blank of ['Tongas studio', 'REI DO ESTILO', 'Celdz', 'Golden cut']) {
        strict_1.default.ok(!passing.some((entry) => entry.row.name === blank), `${blank} não tem avaliações e não devia ser pago`);
    }
});
(0, node_test_1.default)('the gate now rejects something, which is the point of having one', () => {
    // The real run reported "20 discovered, 0 rejected" — a filter that passes
    // everything reads as working and is not.
    strict_1.default.ok(selection().rejected > 0);
});
(0, node_test_1.default)('the same money now reaches more businesses', () => {
    const { duplicates } = selection();
    const before = { paidCalls: SLOTS, distinctBusinesses: 3 };
    const after = {
        paidCalls: SLOTS,
        distinctBusinesses: new Set(selection()
            .passing.slice(0, SLOTS)
            .map((entry) => (0, prospecting_dedup_js_1.matchName)(entry.row.name))).size,
    };
    strict_1.default.equal(after.paidCalls, before.paidCalls);
    strict_1.default.ok(after.distinctBusinesses > before.distinctBusinesses);
    // And the copies were never consulted at all.
    strict_1.default.equal(duplicates.length * DETAIL_COST, 0.06);
});
(0, node_test_1.default)('the budget guard refuses the call that would cross the ceiling', () => {
    // Checked before the call, not after: a cap noticed once it has been
    // crossed is a report, not a control.
    const nearly = (0, prospecting_budget_js_1.evaluateSpend)({
        operation: 'FETCH_LISTING_DETAILS',
        leadScore: 90,
        settings: { ...prospecting_config_js_1.DEFAULT_SETTINGS, dailyBudgetUsd: 0.2 },
        spentThisMonthUsd: 0,
        spentTodayUsd: 0.18,
        spentOnLeadUsd: 0,
    });
    strict_1.default.equal(nearly.allowed, false);
    const room = (0, prospecting_budget_js_1.evaluateSpend)({
        operation: 'FETCH_LISTING_DETAILS',
        leadScore: 90,
        settings: { ...prospecting_config_js_1.DEFAULT_SETTINGS, dailyBudgetUsd: 0.2 },
        spentThisMonthUsd: 0,
        spentTodayUsd: 0.1,
        spentOnLeadUsd: 0,
    });
    strict_1.default.equal(room.allowed, true);
});
