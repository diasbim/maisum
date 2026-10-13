import assert from 'node:assert/strict';
import test from 'node:test';

import { JOB_LEASE_MS } from './prospecting_contracts.js';
import {
  applyBatch,
  cancelJob,
  claimDecision,
  isJobFinished,
  newJob,
  progressFraction,
  progressLabel,
  type BatchOutcome,
  type ProspectingJob,
} from './prospecting_jobs.js';

const NOW = 1_758_000_000_000;

function job(overrides: Partial<ProspectingJob> = {}): ProspectingJob {
  return {
    ...newJob({
      id: 'job_1',
      type: 'DISCOVERY',
      criteria: { industries: ['barbershop'] },
      target: 100,
      estimatedCostUsd: 2,
      actor: 'admin@maisum.test',
      now: NOW,
    }),
    ...overrides,
  };
}

function outcome(overrides: Partial<BatchOutcome> = {}): BatchOutcome {
  return {
    discovered: 0,
    duplicates: 0,
    qualified: 0,
    disqualified: 0,
    enriched: 0,
    failed: 0,
    spentUsd: 0,
    cursor: null,
    fatalCode: null,
    ...overrides,
  };
}

/* ------------------------------------------------------------------ claim */

test('a queued job is claimable, and the claim carries a lease', () => {
  const decision = claimDecision(job(), NOW);
  assert.equal(decision.claimable, true);
  assert.equal(decision.claimable === true && decision.claimedUntil, NOW + JOB_LEASE_MS);
});

test('a job another worker holds is not claimable', () => {
  // A duplicate trigger or an overlapping sweep must not process it twice.
  const held = job({
    status: 'RUNNING',
    claim_id: 'worker_1',
    claimed_until: NOW + 60_000,
  });
  const decision = claimDecision(held, NOW);
  assert.equal(decision.claimable, false);
  assert.equal(decision.claimable === false && decision.reason, 'HELD');
});

test('a lapsed lease releases the job without anyone noticing the worker died', () => {
  const stranded = job({
    status: 'RUNNING',
    claim_id: 'worker_1',
    claimed_until: NOW - 1,
  });
  assert.equal(claimDecision(stranded, NOW).claimable, true);
});

test('a lease that expires exactly now is available', () => {
  const stranded = job({ status: 'RUNNING', claim_id: 'w', claimed_until: NOW });
  assert.equal(claimDecision(stranded, NOW).claimable, true);
});

test('a finished job is never claimed again, however it finished', () => {
  for (const status of ['SUCCEEDED', 'PARTIAL', 'FAILED', 'CANCELLED'] as const) {
    const decision = claimDecision(job({ status }), NOW);
    assert.equal(decision.claimable, false, status);
    assert.equal(decision.claimable === false && decision.reason, 'TERMINAL');
  }
});

/* --------------------------------------------------------------- progress */

test('a batch adds to the counts and keeps the job running', () => {
  const advanced = applyBatch(
    job(),
    outcome({ discovered: 10, duplicates: 2, qualified: 7, disqualified: 3, cursor: '10' }),
    NOW + 1000,
  );

  assert.equal(advanced.status, 'RUNNING');
  assert.equal(advanced.discovered, 10);
  assert.equal(advanced.duplicates, 2);
  assert.equal(advanced.qualified, 7);
  assert.equal(advanced.cursor, '10');
});

test('batches accumulate rather than replacing', () => {
  const first = applyBatch(job(), outcome({ discovered: 10, cursor: '10' }), NOW);
  const second = applyBatch(first, outcome({ discovered: 10, cursor: '20' }), NOW);
  assert.equal(second.discovered, 20);
});

test('a null cursor means the provider ran out, which is success', () => {
  // Five hundred barbershops were asked for and Matola has forty. Finishing
  // at forty is success, not a shortfall.
  const finished = applyBatch(job(), outcome({ discovered: 40, cursor: null }), NOW);
  assert.equal(finished.status, 'SUCCEEDED');
  assert.equal(finished.finished_at, NOW);
  assert.equal(finished.claim_id, null);
});

test('reaching the target finishes the job even with a cursor left', () => {
  const finished = applyBatch(
    job({ target: 10 }),
    outcome({ discovered: 10, cursor: '10' }),
    NOW,
  );
  assert.equal(finished.status, 'SUCCEEDED');
});

test('something fatal after results were stored is PARTIAL, not FAILED', () => {
  // The forty found are real and usable; marking the job failed would invite
  // an operator to run it again and pay for them twice.
  const partial = applyBatch(
    job({ discovered: 40 }),
    outcome({ discovered: 0, fatalCode: 'MONTHLY_CAP' }),
    NOW,
  );

  assert.equal(partial.status, 'PARTIAL');
  assert.equal(partial.error_code, 'MONTHLY_CAP');
  assert.equal(partial.finished_at, NOW);
});

test('something fatal before anything was stored is FAILED', () => {
  const failed = applyBatch(job(), outcome({ fatalCode: 'MONTHLY_CAP' }), NOW);
  assert.equal(failed.status, 'FAILED');
  assert.equal(failed.error_code, 'MONTHLY_CAP');
});

test('a fatal outcome always releases the claim', () => {
  const failed = applyBatch(
    job({ claim_id: 'w', claimed_until: NOW + 1000 }),
    outcome({ fatalCode: 'UNAVAILABLE' }),
    NOW,
  );
  assert.equal(failed.claim_id, null);
  assert.equal(failed.claimed_until, null);
});

test('spend accumulates without floating-point drift', () => {
  let current = job();
  for (let index = 0; index < 10; index++) {
    current = applyBatch(current, outcome({ discovered: 1, spentUsd: 0.1, cursor: 'x' }), NOW);
  }
  assert.equal(current.spent_usd, 1);
});

/* ----------------------------------------------------------------- cancel */

test('a cancelled job is terminal and holds no claim', () => {
  const cancelled = cancelJob(job({ status: 'RUNNING', claim_id: 'w' }), NOW);
  assert.equal(cancelled.status, 'CANCELLED');
  assert.equal(cancelled.claim_id, null);
  assert.equal(isJobFinished(cancelled), true);
  assert.equal(claimDecision(cancelled, NOW + 1_000_000).claimable, false);
});

/* ---------------------------------------------------------------- display */

test('the progress line is the one the plan asks for', () => {
  assert.equal(
    progressLabel(job({ discovered: 12, target: 100 })),
    '12 / 100 negócios descobertos',
  );
  assert.equal(
    progressLabel(job({ type: 'BULK_ENRICHMENT', enriched: 3, target: 20 })),
    '3 / 20 negócios enriquecidos',
  );
});

test('progress never exceeds one, and a zero target is not a division by zero', () => {
  assert.equal(progressFraction(job({ discovered: 50, target: 100 })), 0.5);
  assert.equal(progressFraction(job({ discovered: 200, target: 100 })), 1);
  assert.equal(progressFraction(job({ target: 0 })), 0);
});

test('a running job is not finished and a succeeded one is', () => {
  assert.equal(isJobFinished(job({ status: 'QUEUED' })), false);
  assert.equal(isJobFinished(job({ status: 'RUNNING' })), false);
  assert.equal(isJobFinished(job({ status: 'SUCCEEDED' })), true);
  assert.equal(isJobFinished(job({ status: 'PARTIAL' })), true);
});
