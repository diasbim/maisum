/**
 * Who gets the paid slots — the whole pipeline's money decision, in one test.
 *
 * Deduplication, the gate and the ranking are each tested on their own. This
 * asserts what they do together over the twenty listings of the real Maputo
 * run, because that is the thing that went wrong: every part behaved as
 * written and the five paid calls still bought three businesses.
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { MAPUTO_RUN } from './prospecting_dedup_fixture.js';
import { dedupeCandidates, matchName } from './prospecting_dedup.js';
import {
  compareForRank,
  meanRatingOf,
  scoreProspect,
  UNKNOWN_SIGNALS,
} from './prospecting_scoring.js';
import {
  DEFAULT_GEOGRAPHY,
  DEFAULT_SCORING,
  DEFAULT_SETTINGS,
  OPERATION_COST_USD,
} from './prospecting_config.js';
import { evaluateSpend } from './prospecting_budget.js';

const SLOTS = 5;
const DETAIL_COST = OPERATION_COST_USD.FETCH_LISTING_DETAILS;

/** Discovery through to the ranked list of leads worth paying for. */
function selection() {
  const { kept, duplicates } = dedupeCandidates(MAPUTO_RUN, {
    radiusMetres: DEFAULT_SETTINGS.dedupRadiusMetres,
  });

  const meanRating = meanRatingOf(kept);
  const context = {
    meanRating,
    priorCount: DEFAULT_SETTINGS.bayesianPriorCount,
    noRatingPenalty: DEFAULT_SETTINGS.noRatingPenalty,
  };

  const scored = kept.map((row) => ({
    row,
    score: scoreProspect(
      {
        ...UNKNOWN_SIGNALS,
        businessType: 'barbershop',
        city: 'Maputo',
        country: DEFAULT_GEOGRAPHY.country,
        rating: row.rating,
        reviewCount: row.reviewCount,
        isOperational: true,
      },
      DEFAULT_SCORING,
      DEFAULT_GEOGRAPHY,
      context,
    ),
  }));

  const passing = scored.filter(
    (entry) =>
      evaluateSpend({
        operation: 'FETCH_LISTING_DETAILS',
        leadScore: entry.score.total,
        settings: DEFAULT_SETTINGS,
        spentThisMonthUsd: 0,
        spentTodayUsd: 0,
        spentOnLeadUsd: 0,
      }).allowed,
  );

  passing.sort((left, right) =>
    compareForRank(
      {
        score: left.score.total,
        reviewCount: left.row.reviewCount,
        rating: left.row.rating,
        name: left.row.name,
      },
      {
        score: right.score.total,
        reviewCount: right.row.reviewCount,
        rating: right.row.rating,
        name: right.row.name,
      },
    ),
  );

  return { duplicates, scored, passing, rejected: scored.length - passing.length };
}

test('the five paid slots go to five different businesses', () => {
  // Before: three of the five were the same shop, reached through three
  // spellings of its apostrophe, and $0.06 of $0.17 bought one phone number.
  const slots = selection().passing.slice(0, SLOTS);
  const distinct = new Set(slots.map((entry) => matchName(entry.row.name)));
  assert.equal(slots.length, SLOTS);
  assert.equal(distinct.size, SLOTS);
});

test('the businesses the old run skipped are now inside the slots', () => {
  // Tchetcho's carries 107 reviews and was skipped in favour of a duplicate.
  const names = selection()
    .passing.slice(0, SLOTS)
    .map((entry) => entry.row.name);
  for (const expected of ['Tchetcho', 'Tsemeta', 'KUBILA', 'Gentleman']) {
    assert.ok(
      names.some((name) => name.includes(expected)),
      `${expected} devia estar entre os pagos: ${names.join(', ')}`,
    );
  }
});

test('a business with no reviews does not reach the paid stage', () => {
  const { passing } = selection();
  for (const blank of ['Tongas studio', 'REI DO ESTILO', 'Celdz', 'Golden cut']) {
    assert.ok(
      !passing.some((entry) => entry.row.name === blank),
      `${blank} não tem avaliações e não devia ser pago`,
    );
  }
});

test('the gate now rejects something, which is the point of having one', () => {
  // The real run reported "20 discovered, 0 rejected" — a filter that passes
  // everything reads as working and is not.
  assert.ok(selection().rejected > 0);
});

test('the same money now reaches more businesses', () => {
  const { duplicates } = selection();
  const before = { paidCalls: SLOTS, distinctBusinesses: 3 };
  const after = {
    paidCalls: SLOTS,
    distinctBusinesses: new Set(
      selection()
        .passing.slice(0, SLOTS)
        .map((entry) => matchName(entry.row.name)),
    ).size,
  };
  assert.equal(after.paidCalls, before.paidCalls);
  assert.ok(after.distinctBusinesses > before.distinctBusinesses);
  // And the copies were never consulted at all.
  assert.equal(duplicates.length * DETAIL_COST, 0.06);
});

test('the budget guard refuses the call that would cross the ceiling', () => {
  // Checked before the call, not after: a cap noticed once it has been
  // crossed is a report, not a control.
  const nearly = evaluateSpend({
    operation: 'FETCH_LISTING_DETAILS',
    leadScore: 90,
    settings: { ...DEFAULT_SETTINGS, dailyBudgetUsd: 0.2 },
    spentThisMonthUsd: 0,
    spentTodayUsd: 0.18,
    spentOnLeadUsd: 0,
  });
  assert.equal(nearly.allowed, false);

  const room = evaluateSpend({
    operation: 'FETCH_LISTING_DETAILS',
    leadScore: 90,
    settings: { ...DEFAULT_SETTINGS, dailyBudgetUsd: 0.2 },
    spentThisMonthUsd: 0,
    spentTodayUsd: 0.1,
    spentOnLeadUsd: 0,
  });
  assert.equal(room.allowed, true);
});
