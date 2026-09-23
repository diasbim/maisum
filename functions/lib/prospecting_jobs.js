"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.JOB_STATUS_LABEL = void 0;
exports.newJob = newJob;
exports.claimDecision = claimDecision;
exports.applyBatch = applyBatch;
exports.cancelJob = cancelJob;
exports.progressLabel = progressLabel;
exports.progressFraction = progressFraction;
exports.isJobFinished = isJobFinished;
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
function newJob(input) {
    return {
        id: input.id,
        type: input.type,
        status: 'QUEUED',
        criteria: input.criteria,
        target: input.target,
        discovered: 0,
        duplicates: 0,
        qualified: 0,
        disqualified: 0,
        enriched: 0,
        failed: 0,
        cursor: null,
        estimated_cost_usd: input.estimatedCostUsd,
        spent_usd: 0,
        error_code: null,
        claim_id: null,
        claimed_until: null,
        created_by: input.actor,
        created_at: input.now,
        updated_at: input.now,
        finished_at: null,
    };
}
/**
 * Whether this worker may take the job.
 *
 * A terminal job is never re-claimed, however it ended. A running job is
 * claimable only once its lease has lapsed — which is how a worker that died
 * mid-batch releases what it was holding without anything having to notice
 * that it died.
 *
 * The lease is compared with `<=` so a lease that expires exactly now is
 * available: the alternative leaves a job stranded for one more sweep for no
 * reason anyone could explain.
 */
function claimDecision(job, now) {
    if (!prospecting_contracts_js_1.CLAIMABLE_JOB_STATUSES.includes(job.status)) {
        return { claimable: false, reason: 'TERMINAL' };
    }
    if (job.claim_id !== null &&
        job.claimed_until !== null &&
        job.claimed_until > now) {
        return { claimable: false, reason: 'HELD' };
    }
    return { claimable: true, claimedUntil: now + prospecting_contracts_js_1.JOB_LEASE_MS };
}
/**
 * The job after a batch, and whether it is finished.
 *
 * A job finishes when the provider runs out of results, when the target is
 * reached, or when something fatal happened. "Ran out of results" is a null
 * cursor and is the common case — a search for five hundred barbershops in
 * Matola will find forty, and finishing at forty is success, not a shortfall.
 *
 * `PARTIAL` rather than `FAILED` when some businesses were stored and then
 * something broke: the forty that were found are real and usable, and marking
 * the whole job failed would invite an operator to run it again and pay for
 * them twice.
 */
function applyBatch(job, outcome, now) {
    const discovered = job.discovered + outcome.discovered;
    const next = {
        ...job,
        discovered,
        duplicates: job.duplicates + outcome.duplicates,
        qualified: job.qualified + outcome.qualified,
        disqualified: job.disqualified + outcome.disqualified,
        enriched: job.enriched + outcome.enriched,
        failed: job.failed + outcome.failed,
        spent_usd: Math.round((job.spent_usd + outcome.spentUsd) * 10000) / 10000,
        cursor: outcome.cursor,
        status: 'RUNNING',
        updated_at: now,
    };
    if (outcome.fatalCode !== null) {
        return {
            ...next,
            status: discovered > 0 ? 'PARTIAL' : 'FAILED',
            error_code: outcome.fatalCode,
            claim_id: null,
            claimed_until: null,
            finished_at: now,
        };
    }
    const exhausted = outcome.cursor === null;
    const reachedTarget = discovered >= job.target;
    if (exhausted || reachedTarget) {
        return {
            ...next,
            status: 'SUCCEEDED',
            claim_id: null,
            claimed_until: null,
            finished_at: now,
        };
    }
    return next;
}
/** A job an operator stopped. Terminal, so no sweep picks it up again. */
function cancelJob(job, now) {
    return {
        ...job,
        status: 'CANCELLED',
        claim_id: null,
        claimed_until: null,
        finished_at: now,
        updated_at: now,
    };
}
/* ----------------------------------------------------------------- display */
exports.JOB_STATUS_LABEL = {
    QUEUED: 'Em fila',
    RUNNING: 'A correr',
    SUCCEEDED: 'Concluído',
    PARTIAL: 'Concluído em parte',
    FAILED: 'Falhou',
    CANCELLED: 'Cancelado',
};
/**
 * What the progress line says.
 *
 * "12 / 100 negócios descobertos" — the form §11 asks for, built here so the
 * portal and any other reader say the same thing. The target rather than the
 * discovered count is the denominator even when the search will clearly not
 * reach it, because it is what the operator asked for and changing the
 * denominator mid-run makes a progress bar go backwards.
 */
function progressLabel(job) {
    if (job.type === 'BULK_ENRICHMENT') {
        return `${job.enriched} / ${job.target} negócios enriquecidos`;
    }
    return `${job.discovered} / ${job.target} negócios descobertos`;
}
/** Nought to one, for a progress bar. Never above one. */
function progressFraction(job) {
    if (job.target <= 0)
        return 0;
    const done = job.type === 'BULK_ENRICHMENT' ? job.enriched : job.discovered;
    return Math.min(1, done / job.target);
}
function isJobFinished(job) {
    return !prospecting_contracts_js_1.CLAIMABLE_JOB_STATUSES.includes(job.status);
}
