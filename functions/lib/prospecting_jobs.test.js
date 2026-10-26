"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
const prospecting_jobs_js_1 = require("./prospecting_jobs.js");
const NOW = 1758000000000;
function job(overrides = {}) {
    return {
        ...(0, prospecting_jobs_js_1.newJob)({
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
function outcome(overrides = {}) {
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
(0, node_test_1.default)('a queued job is claimable, and the claim carries a lease', () => {
    const decision = (0, prospecting_jobs_js_1.claimDecision)(job(), NOW);
    strict_1.default.equal(decision.claimable, true);
    strict_1.default.equal(decision.claimable === true && decision.claimedUntil, NOW + prospecting_contracts_js_1.JOB_LEASE_MS);
});
(0, node_test_1.default)('a job another worker holds is not claimable', () => {
    // A duplicate trigger or an overlapping sweep must not process it twice.
    const held = job({
        status: 'RUNNING',
        claim_id: 'worker_1',
        claimed_until: NOW + 60000,
    });
    const decision = (0, prospecting_jobs_js_1.claimDecision)(held, NOW);
    strict_1.default.equal(decision.claimable, false);
    strict_1.default.equal(decision.claimable === false && decision.reason, 'HELD');
});
(0, node_test_1.default)('a lapsed lease releases the job without anyone noticing the worker died', () => {
    const stranded = job({
        status: 'RUNNING',
        claim_id: 'worker_1',
        claimed_until: NOW - 1,
    });
    strict_1.default.equal((0, prospecting_jobs_js_1.claimDecision)(stranded, NOW).claimable, true);
});
(0, node_test_1.default)('a lease that expires exactly now is available', () => {
    const stranded = job({ status: 'RUNNING', claim_id: 'w', claimed_until: NOW });
    strict_1.default.equal((0, prospecting_jobs_js_1.claimDecision)(stranded, NOW).claimable, true);
});
(0, node_test_1.default)('a finished job is never claimed again, however it finished', () => {
    for (const status of ['SUCCEEDED', 'PARTIAL', 'FAILED', 'CANCELLED']) {
        const decision = (0, prospecting_jobs_js_1.claimDecision)(job({ status }), NOW);
        strict_1.default.equal(decision.claimable, false, status);
        strict_1.default.equal(decision.claimable === false && decision.reason, 'TERMINAL');
    }
});
/* --------------------------------------------------------------- progress */
(0, node_test_1.default)('a batch adds to the counts and keeps the job running', () => {
    const advanced = (0, prospecting_jobs_js_1.applyBatch)(job(), outcome({ discovered: 10, duplicates: 2, qualified: 7, disqualified: 3, cursor: '10' }), NOW + 1000);
    strict_1.default.equal(advanced.status, 'RUNNING');
    strict_1.default.equal(advanced.discovered, 10);
    strict_1.default.equal(advanced.duplicates, 2);
    strict_1.default.equal(advanced.qualified, 7);
    strict_1.default.equal(advanced.cursor, '10');
});
(0, node_test_1.default)('batches accumulate rather than replacing', () => {
    const first = (0, prospecting_jobs_js_1.applyBatch)(job(), outcome({ discovered: 10, cursor: '10' }), NOW);
    const second = (0, prospecting_jobs_js_1.applyBatch)(first, outcome({ discovered: 10, cursor: '20' }), NOW);
    strict_1.default.equal(second.discovered, 20);
});
(0, node_test_1.default)('a null cursor means the provider ran out, which is success', () => {
    // Five hundred barbershops were asked for and Matola has forty. Finishing
    // at forty is success, not a shortfall.
    const finished = (0, prospecting_jobs_js_1.applyBatch)(job(), outcome({ discovered: 40, cursor: null }), NOW);
    strict_1.default.equal(finished.status, 'SUCCEEDED');
    strict_1.default.equal(finished.finished_at, NOW);
    strict_1.default.equal(finished.claim_id, null);
});
(0, node_test_1.default)('reaching the target finishes the job even with a cursor left', () => {
    const finished = (0, prospecting_jobs_js_1.applyBatch)(job({ target: 10 }), outcome({ discovered: 10, cursor: '10' }), NOW);
    strict_1.default.equal(finished.status, 'SUCCEEDED');
});
(0, node_test_1.default)('something fatal after results were stored is PARTIAL, not FAILED', () => {
    // The forty found are real and usable; marking the job failed would invite
    // an operator to run it again and pay for them twice.
    const partial = (0, prospecting_jobs_js_1.applyBatch)(job({ discovered: 40 }), outcome({ discovered: 0, fatalCode: 'MONTHLY_CAP' }), NOW);
    strict_1.default.equal(partial.status, 'PARTIAL');
    strict_1.default.equal(partial.error_code, 'MONTHLY_CAP');
    strict_1.default.equal(partial.finished_at, NOW);
});
(0, node_test_1.default)('something fatal before anything was stored is FAILED', () => {
    const failed = (0, prospecting_jobs_js_1.applyBatch)(job(), outcome({ fatalCode: 'MONTHLY_CAP' }), NOW);
    strict_1.default.equal(failed.status, 'FAILED');
    strict_1.default.equal(failed.error_code, 'MONTHLY_CAP');
});
(0, node_test_1.default)('a fatal outcome always releases the claim', () => {
    const failed = (0, prospecting_jobs_js_1.applyBatch)(job({ claim_id: 'w', claimed_until: NOW + 1000 }), outcome({ fatalCode: 'UNAVAILABLE' }), NOW);
    strict_1.default.equal(failed.claim_id, null);
    strict_1.default.equal(failed.claimed_until, null);
});
(0, node_test_1.default)('spend accumulates without floating-point drift', () => {
    let current = job();
    for (let index = 0; index < 10; index++) {
        current = (0, prospecting_jobs_js_1.applyBatch)(current, outcome({ discovered: 1, spentUsd: 0.1, cursor: 'x' }), NOW);
    }
    strict_1.default.equal(current.spent_usd, 1);
});
/* ----------------------------------------------------------------- cancel */
(0, node_test_1.default)('a cancelled job is terminal and holds no claim', () => {
    const cancelled = (0, prospecting_jobs_js_1.cancelJob)(job({ status: 'RUNNING', claim_id: 'w' }), NOW);
    strict_1.default.equal(cancelled.status, 'CANCELLED');
    strict_1.default.equal(cancelled.claim_id, null);
    strict_1.default.equal((0, prospecting_jobs_js_1.isJobFinished)(cancelled), true);
    strict_1.default.equal((0, prospecting_jobs_js_1.claimDecision)(cancelled, NOW + 1000000).claimable, false);
});
/* ---------------------------------------------------------------- display */
(0, node_test_1.default)('the progress line is the one the plan asks for', () => {
    strict_1.default.equal((0, prospecting_jobs_js_1.progressLabel)(job({ discovered: 12, target: 100 })), '12 / 100 negócios descobertos');
    strict_1.default.equal((0, prospecting_jobs_js_1.progressLabel)(job({ type: 'BULK_ENRICHMENT', enriched: 3, target: 20 })), '3 / 20 negócios enriquecidos');
});
(0, node_test_1.default)('progress never exceeds one, and a zero target is not a division by zero', () => {
    strict_1.default.equal((0, prospecting_jobs_js_1.progressFraction)(job({ discovered: 50, target: 100 })), 0.5);
    strict_1.default.equal((0, prospecting_jobs_js_1.progressFraction)(job({ discovered: 200, target: 100 })), 1);
    strict_1.default.equal((0, prospecting_jobs_js_1.progressFraction)(job({ target: 0 })), 0);
});
(0, node_test_1.default)('a running job is not finished and a succeeded one is', () => {
    strict_1.default.equal((0, prospecting_jobs_js_1.isJobFinished)(job({ status: 'QUEUED' })), false);
    strict_1.default.equal((0, prospecting_jobs_js_1.isJobFinished)(job({ status: 'RUNNING' })), false);
    strict_1.default.equal((0, prospecting_jobs_js_1.isJobFinished)(job({ status: 'SUCCEEDED' })), true);
    strict_1.default.equal((0, prospecting_jobs_js_1.isJobFinished)(job({ status: 'PARTIAL' })), true);
});
