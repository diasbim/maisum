"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_budget_js_1 = require("./prospecting_budget.js");
const prospecting_config_js_1 = require("./prospecting_config.js");
const settings = prospecting_config_js_1.DEFAULT_SETTINGS;
function spend(overrides = {}) {
    return (0, prospecting_budget_js_1.evaluateSpend)({
        operation: 'FIND_DECISION_MAKERS',
        leadScore: 75,
        spentThisMonthUsd: 0,
        spentTodayUsd: 0,
        spentOnLeadUsd: 0,
        settings,
        ...overrides,
    });
}
/* ------------------------------------------------------- budget available */
(0, node_test_1.default)('a qualifying lead with budget available is allowed', () => {
    const decision = spend();
    strict_1.default.equal(decision.allowed, true);
    strict_1.default.equal(decision.allowed === true && decision.estimatedCostUsd, 0.05);
});
/* ------------------------------------------------------- below threshold */
(0, node_test_1.default)('a lead below the minimum score is refused before the budget is consulted', () => {
    const decision = spend({ leadScore: 59, spentThisMonthUsd: 0 });
    strict_1.default.equal(decision.allowed, false);
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'BELOW_THRESHOLD');
});
(0, node_test_1.default)('a lead exactly at the threshold is refused, and one point above passes', () => {
    // This used to assert the opposite, and a real run showed why it was wrong:
    // twenty businesses discovered in Maputo, every one with no rating and no
    // reviews landing on exactly 60 against a threshold of 60, and a gate that
    // passed all twenty while its own report said it had filtered. Equality is
    // the case a threshold exists to decide, and it decides against paying.
    const atThreshold = spend({ leadScore: 60 });
    strict_1.default.equal(atThreshold.allowed, false);
    strict_1.default.equal(atThreshold.allowed === false && atThreshold.refusal, 'BELOW_THRESHOLD');
    strict_1.default.equal(spend({ leadScore: 61 }).allowed, true);
});
(0, node_test_1.default)('the threshold refusal wins over an exhausted budget, because it is the real reason', () => {
    // Telling an operator "budget reached" when the lead scored 43 sends them to
    // raise a cap that was never the obstacle.
    const decision = spend({ leadScore: 43, spentThisMonthUsd: 50 });
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'BELOW_THRESHOLD');
});
(0, node_test_1.default)('an operation with no lead behind it is never below threshold', () => {
    // A discovery search has no score to be above.
    strict_1.default.equal(spend({ leadScore: null, operation: 'SEARCH_BUSINESSES' }).allowed, true);
});
/* ------------------------------------------------------- budget exhausted */
(0, node_test_1.default)('the monthly cap refuses the call that would cross it, not the one after', () => {
    // $49.98 spent, a $0.05 call: the call itself must be refused, because
    // admitting it would put the month at $50.03.
    const decision = spend({ spentThisMonthUsd: 49.98 });
    strict_1.default.equal(decision.allowed, false);
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'MONTHLY_CAP');
    strict_1.default.equal(decision.allowed === false && decision.remainingUsd, 0.02);
});
(0, node_test_1.default)('a call that lands exactly on the cap is allowed', () => {
    const decision = spend({ spentThisMonthUsd: 49.95 });
    strict_1.default.equal(decision.allowed, true);
});
(0, node_test_1.default)('the daily cap refuses independently of the month', () => {
    const decision = spend({ spentTodayUsd: 4.99, spentThisMonthUsd: 5 });
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'DAILY_CAP');
});
(0, node_test_1.default)('the per-lead cap refuses independently of both', () => {
    const decision = spend({ spentOnLeadUsd: 0.48 });
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'PER_LEAD_CAP');
});
(0, node_test_1.default)('a per-lead cap of zero means no paid enrichment at all', () => {
    const decision = spend({
        settings: { ...settings, maxEnrichmentCostPerLeadUsd: 0 },
    });
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'PER_LEAD_CAP');
});
(0, node_test_1.default)('the narrowest cap is the one reported', () => {
    // All three are close; the per-lead one is checked first because it is the
    // most specific thing an operator can act on.
    const decision = spend({
        spentOnLeadUsd: 0.49,
        spentTodayUsd: 4.99,
        spentThisMonthUsd: 49.99,
    });
    strict_1.default.equal(decision.allowed === false && decision.refusal, 'PER_LEAD_CAP');
});
(0, node_test_1.default)('every refusal carries a message an operator can read', () => {
    const decision = spend({ spentThisMonthUsd: 50 });
    strict_1.default.equal(decision.allowed, false);
    strict_1.default.ok(decision.allowed === false && decision.message.includes('orçamento'));
});
(0, node_test_1.default)('floating point does not decide whether a call is allowed', () => {
    // 0.1 + 0.2 > 0.3 in IEEE 754. Without rounding this refuses a call the cap
    // admits.
    const decision = (0, prospecting_budget_js_1.evaluateSpend)({
        operation: 'ANALYZE_LEAD',
        leadScore: 80,
        spentThisMonthUsd: 0.1,
        spentTodayUsd: 0.2,
        spentOnLeadUsd: 0.1,
        estimatedCostUsd: 0.2,
        settings: { ...settings, maxEnrichmentCostPerLeadUsd: 0.3 },
    });
    strict_1.default.equal(decision.allowed, true);
});
(0, node_test_1.default)('rounding is to the tenth of a cent', () => {
    strict_1.default.equal((0, prospecting_budget_js_1.round)(0.1 + 0.2), 0.3);
    strict_1.default.equal((0, prospecting_budget_js_1.round)(1 / 3), 0.3333);
});
/* ------------------------------------------------------------- estimates */
(0, node_test_1.default)('an estimate is a range, and says it is not verified', () => {
    const estimate = (0, prospecting_budget_js_1.estimateSearchCost)({ maxLeads: 100, minScore: 60, settings });
    strict_1.default.equal(estimate.minUsd, 2);
    strict_1.default.ok(estimate.maxUsd > estimate.minUsd);
    strict_1.default.ok(estimate.likelyUsd > estimate.minUsd);
    strict_1.default.ok(estimate.likelyUsd < estimate.maxUsd);
    // The unit prices have not been checked against an invoice, and the screen
    // must say so rather than presenting a figure to plan against.
    strict_1.default.equal(estimate.verified, false);
    strict_1.default.equal(estimate.monthlyBudgetUsd, 50);
});
(0, node_test_1.default)('a stricter threshold lowers the likely cost, because fewer leads qualify', () => {
    const loose = (0, prospecting_budget_js_1.estimateSearchCost)({ maxLeads: 100, minScore: 40, settings });
    const strict = (0, prospecting_budget_js_1.estimateSearchCost)({ maxLeads: 100, minScore: 80, settings });
    strict_1.default.ok(strict.likelyUsd < loose.likelyUsd);
    strict_1.default.equal(strict.maxUsd, loose.maxUsd);
    strict_1.default.equal(strict.minUsd, loose.minUsd);
});
(0, node_test_1.default)('a search for nothing costs nothing', () => {
    const estimate = (0, prospecting_budget_js_1.estimateSearchCost)({ maxLeads: 0, minScore: 60, settings });
    strict_1.default.equal(estimate.minUsd, 0);
    strict_1.default.equal(estimate.maxUsd, 0);
});
/* ----------------------------------------------------------------- period */
(0, node_test_1.default)('the budget day is Maputo, not UTC', () => {
    // 2026-09-20 22:30 UTC is already the 21st in Maputo, and a daily cap that
    // reset at UTC midnight would spread one day's budget over two of the
    // operator's working days.
    strict_1.default.equal((0, prospecting_budget_js_1.dayKey)(Date.parse('2026-09-20T22:30:00Z')), '2026-09-21');
    strict_1.default.equal((0, prospecting_budget_js_1.dayKey)(Date.parse('2026-09-20T21:30:00Z')), '2026-09-20');
});
(0, node_test_1.default)('the month rolls over on Maputo time too', () => {
    strict_1.default.equal((0, prospecting_budget_js_1.monthKey)(Date.parse('2026-09-30T22:30:00Z')), '2026-10');
    strict_1.default.equal((0, prospecting_budget_js_1.monthKey)(Date.parse('2026-09-30T21:30:00Z')), '2026-09');
});
/* ------------------------------------------------------------------ usage */
(0, node_test_1.default)('a month totals actual costs where reported and estimates where not', () => {
    const rows = [
        usage({ estimated_cost: 0.05, actual_cost: 0.07 }),
        usage({ estimated_cost: 0.05, actual_cost: null }),
    ];
    strict_1.default.equal((0, prospecting_budget_js_1.totalSpend)(rows), 0.12);
    strict_1.default.equal((0, prospecting_budget_js_1.spendIsEstimated)(rows), true);
});
(0, node_test_1.default)('a failed call still counts against the budget', () => {
    // Providers charge for calls that return nothing; a usage log that only
    // recorded successes would understate the month by exactly the amount
    // nobody expected to be spending.
    const rows = [usage({ success: false, error_code: 'NO_RESULT', estimated_cost: 0.05 })];
    strict_1.default.equal((0, prospecting_budget_js_1.totalSpend)(rows), 0.05);
});
(0, node_test_1.default)('a month where every provider reported a cost is not estimated', () => {
    const rows = [usage({ actual_cost: 0.05 }), usage({ actual_cost: 0.02 })];
    strict_1.default.equal((0, prospecting_budget_js_1.spendIsEstimated)(rows), false);
    strict_1.default.equal((0, prospecting_budget_js_1.totalSpend)(rows), 0.07);
});
function usage(overrides = {}) {
    return {
        id: 'u1',
        provider: 'fixtures',
        operation: 'FIND_DECISION_MAKERS',
        prospect_id: 'p1',
        estimated_cost: 0.05,
        actual_cost: null,
        credits_used: null,
        success: true,
        error_code: null,
        correlation_id: 'c1',
        month_key: '2026-09',
        day_key: '2026-09-20',
        created_at: 1758000000000,
        ...overrides,
    };
}
