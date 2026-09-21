import assert from 'node:assert/strict';
import test from 'node:test';

import {
  dayKey,
  estimateSearchCost,
  evaluateSpend,
  monthKey,
  round,
  spendIsEstimated,
  totalSpend,
  type EnrichmentUsage,
} from './prospecting_budget.js';
import { DEFAULT_SETTINGS } from './prospecting_config.js';

const settings = DEFAULT_SETTINGS;

function spend(overrides: Partial<Parameters<typeof evaluateSpend>[0]> = {}) {
  return evaluateSpend({
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

test('a qualifying lead with budget available is allowed', () => {
  const decision = spend();
  assert.equal(decision.allowed, true);
  assert.equal(decision.allowed === true && decision.estimatedCostUsd, 0.05);
});

/* ------------------------------------------------------- below threshold */

test('a lead below the minimum score is refused before the budget is consulted', () => {
  const decision = spend({ leadScore: 59, spentThisMonthUsd: 0 });
  assert.equal(decision.allowed, false);
  assert.equal(decision.allowed === false && decision.refusal, 'BELOW_THRESHOLD');
});

test('a lead exactly at the threshold is allowed', () => {
  assert.equal(spend({ leadScore: 60 }).allowed, true);
});

test('the threshold refusal wins over an exhausted budget, because it is the real reason', () => {
  // Telling an operator "budget reached" when the lead scored 43 sends them to
  // raise a cap that was never the obstacle.
  const decision = spend({ leadScore: 43, spentThisMonthUsd: 50 });
  assert.equal(decision.allowed === false && decision.refusal, 'BELOW_THRESHOLD');
});

test('an operation with no lead behind it is never below threshold', () => {
  // A discovery search has no score to be above.
  assert.equal(spend({ leadScore: null, operation: 'SEARCH_BUSINESSES' }).allowed, true);
});

/* ------------------------------------------------------- budget exhausted */

test('the monthly cap refuses the call that would cross it, not the one after', () => {
  // $49.98 spent, a $0.05 call: the call itself must be refused, because
  // admitting it would put the month at $50.03.
  const decision = spend({ spentThisMonthUsd: 49.98 });
  assert.equal(decision.allowed, false);
  assert.equal(decision.allowed === false && decision.refusal, 'MONTHLY_CAP');
  assert.equal(decision.allowed === false && decision.remainingUsd, 0.02);
});

test('a call that lands exactly on the cap is allowed', () => {
  const decision = spend({ spentThisMonthUsd: 49.95 });
  assert.equal(decision.allowed, true);
});

test('the daily cap refuses independently of the month', () => {
  const decision = spend({ spentTodayUsd: 4.99, spentThisMonthUsd: 5 });
  assert.equal(decision.allowed === false && decision.refusal, 'DAILY_CAP');
});

test('the per-lead cap refuses independently of both', () => {
  const decision = spend({ spentOnLeadUsd: 0.48 });
  assert.equal(decision.allowed === false && decision.refusal, 'PER_LEAD_CAP');
});

test('a per-lead cap of zero means no paid enrichment at all', () => {
  const decision = spend({
    settings: { ...settings, maxEnrichmentCostPerLeadUsd: 0 },
  });
  assert.equal(decision.allowed === false && decision.refusal, 'PER_LEAD_CAP');
});

test('the narrowest cap is the one reported', () => {
  // All three are close; the per-lead one is checked first because it is the
  // most specific thing an operator can act on.
  const decision = spend({
    spentOnLeadUsd: 0.49,
    spentTodayUsd: 4.99,
    spentThisMonthUsd: 49.99,
  });
  assert.equal(decision.allowed === false && decision.refusal, 'PER_LEAD_CAP');
});

test('every refusal carries a message an operator can read', () => {
  const decision = spend({ spentThisMonthUsd: 50 });
  assert.equal(decision.allowed, false);
  assert.ok(decision.allowed === false && decision.message.includes('orçamento'));
});

test('floating point does not decide whether a call is allowed', () => {
  // 0.1 + 0.2 > 0.3 in IEEE 754. Without rounding this refuses a call the cap
  // admits.
  const decision = evaluateSpend({
    operation: 'ANALYZE_LEAD',
    leadScore: 80,
    spentThisMonthUsd: 0.1,
    spentTodayUsd: 0.2,
    spentOnLeadUsd: 0.1,
    estimatedCostUsd: 0.2,
    settings: { ...settings, maxEnrichmentCostPerLeadUsd: 0.3 },
  });
  assert.equal(decision.allowed, true);
});

test('rounding is to the tenth of a cent', () => {
  assert.equal(round(0.1 + 0.2), 0.3);
  assert.equal(round(1 / 3), 0.3333);
});

/* ------------------------------------------------------------- estimates */

test('an estimate is a range, and says it is not verified', () => {
  const estimate = estimateSearchCost({ maxLeads: 100, minScore: 60, settings });

  assert.equal(estimate.minUsd, 2);
  assert.ok(estimate.maxUsd > estimate.minUsd);
  assert.ok(estimate.likelyUsd > estimate.minUsd);
  assert.ok(estimate.likelyUsd < estimate.maxUsd);
  // The unit prices have not been checked against an invoice, and the screen
  // must say so rather than presenting a figure to plan against.
  assert.equal(estimate.verified, false);
  assert.equal(estimate.monthlyBudgetUsd, 50);
});

test('a stricter threshold lowers the likely cost, because fewer leads qualify', () => {
  const loose = estimateSearchCost({ maxLeads: 100, minScore: 40, settings });
  const strict = estimateSearchCost({ maxLeads: 100, minScore: 80, settings });

  assert.ok(strict.likelyUsd < loose.likelyUsd);
  assert.equal(strict.maxUsd, loose.maxUsd);
  assert.equal(strict.minUsd, loose.minUsd);
});

test('a search for nothing costs nothing', () => {
  const estimate = estimateSearchCost({ maxLeads: 0, minScore: 60, settings });
  assert.equal(estimate.minUsd, 0);
  assert.equal(estimate.maxUsd, 0);
});

/* ----------------------------------------------------------------- period */

test('the budget day is Maputo, not UTC', () => {
  // 2026-09-20 22:30 UTC is already the 21st in Maputo, and a daily cap that
  // reset at UTC midnight would spread one day's budget over two of the
  // operator's working days.
  assert.equal(dayKey(Date.parse('2026-09-20T22:30:00Z')), '2026-09-21');
  assert.equal(dayKey(Date.parse('2026-09-20T21:30:00Z')), '2026-09-20');
});

test('the month rolls over on Maputo time too', () => {
  assert.equal(monthKey(Date.parse('2026-09-30T22:30:00Z')), '2026-10');
  assert.equal(monthKey(Date.parse('2026-09-30T21:30:00Z')), '2026-09');
});

/* ------------------------------------------------------------------ usage */

test('a month totals actual costs where reported and estimates where not', () => {
  const rows: EnrichmentUsage[] = [
    usage({ estimated_cost: 0.05, actual_cost: 0.07 }),
    usage({ estimated_cost: 0.05, actual_cost: null }),
  ];
  assert.equal(totalSpend(rows), 0.12);
  assert.equal(spendIsEstimated(rows), true);
});

test('a failed call still counts against the budget', () => {
  // Providers charge for calls that return nothing; a usage log that only
  // recorded successes would understate the month by exactly the amount
  // nobody expected to be spending.
  const rows = [usage({ success: false, error_code: 'NO_RESULT', estimated_cost: 0.05 })];
  assert.equal(totalSpend(rows), 0.05);
});

test('a month where every provider reported a cost is not estimated', () => {
  const rows = [usage({ actual_cost: 0.05 }), usage({ actual_cost: 0.02 })];
  assert.equal(spendIsEstimated(rows), false);
  assert.equal(totalSpend(rows), 0.07);
});

function usage(overrides: Partial<EnrichmentUsage> = {}): EnrichmentUsage {
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
    created_at: 1_758_000_000_000,
    ...overrides,
  };
}
