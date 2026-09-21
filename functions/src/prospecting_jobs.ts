import {
  CLAIMABLE_JOB_STATUSES,
  JOB_LEASE_MS,
  type JobStatus,
  type JobType,
} from './prospecting_contracts.js';

/**
 * The job record, and the decisions about it — as pure functions.
 *
 * Bulk discovery cannot run inside a request: a search for five hundred
 * businesses is minutes of provider calls, and an operator watching a spinner
 * for that long will reload the page and start a second one. So the request
 * writes a job and returns its id, and a worker drains it.
 *
 * There is no Cloud Tasks and no Pub/Sub in this project. What there is — and
 * what this follows — is the shape `affiliate_outbox.ts` established: a
 * Firestore record, claimed under an expiring lease so a duplicate trigger
 * cannot double-process it, drained in bounded batches, and swept on a
 * schedule for anything a crashed instance stranded.
 *
 * Everything here is a decision over a record and a clock. The transaction
 * that actually claims a job does nothing but read, call `claimDecision`, and
 * write, which is what lets the claim race be tested without an emulator.
 */

export type ProspectingJob = {
  id: string;
  type: JobType;
  status: JobStatus;
  /** What was asked for. Echoed to the UI so a job explains itself. */
  criteria: Record<string, unknown>;
  /** How many businesses the search asked for. */
  target: number;
  discovered: number;
  duplicates: number;
  qualified: number;
  disqualified: number;
  enriched: number;
  failed: number;
  /** Where the provider's paging got to, so a resumed batch does not repeat. */
  cursor: string | null;
  estimated_cost_usd: number;
  spent_usd: number;
  error_code: string | null;
  /** Who holds the job now, and until when. */
  claim_id: string | null;
  claimed_until: number | null;
  created_by: string;
  created_at: number;
  updated_at: number;
  finished_at: number | null;
};

export function newJob(input: {
  id: string;
  type: JobType;
  criteria: Record<string, unknown>;
  target: number;
  estimatedCostUsd: number;
  actor: string;
  now: number;
}): ProspectingJob {
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

/* ------------------------------------------------------------------ claim */

export type ClaimDecision =
  | { claimable: true; claimedUntil: number }
  | { claimable: false; reason: 'TERMINAL' | 'HELD' };

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
export function claimDecision(job: ProspectingJob, now: number): ClaimDecision {
  if (!CLAIMABLE_JOB_STATUSES.includes(job.status)) {
    return { claimable: false, reason: 'TERMINAL' };
  }

  if (
    job.claim_id !== null &&
    job.claimed_until !== null &&
    job.claimed_until > now
  ) {
    return { claimable: false, reason: 'HELD' };
  }

  return { claimable: true, claimedUntil: now + JOB_LEASE_MS };
}

/* ----------------------------------------------------------------- progress */

export type BatchOutcome = {
  discovered: number;
  duplicates: number;
  qualified: number;
  disqualified: number;
  enriched: number;
  failed: number;
  spentUsd: number;
  cursor: string | null;
  /** Set when the batch hit something that should stop the whole job. */
  fatalCode: string | null;
};

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
export function applyBatch(
  job: ProspectingJob,
  outcome: BatchOutcome,
  now: number,
): ProspectingJob {
  const discovered = job.discovered + outcome.discovered;
  const next: ProspectingJob = {
    ...job,
    discovered,
    duplicates: job.duplicates + outcome.duplicates,
    qualified: job.qualified + outcome.qualified,
    disqualified: job.disqualified + outcome.disqualified,
    enriched: job.enriched + outcome.enriched,
    failed: job.failed + outcome.failed,
    spent_usd: Math.round((job.spent_usd + outcome.spentUsd) * 10_000) / 10_000,
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
export function cancelJob(job: ProspectingJob, now: number): ProspectingJob {
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

export const JOB_STATUS_LABEL: Record<JobStatus, string> = {
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
export function progressLabel(job: ProspectingJob): string {
  if (job.type === 'BULK_ENRICHMENT') {
    return `${job.enriched} / ${job.target} negócios enriquecidos`;
  }
  return `${job.discovered} / ${job.target} negócios descobertos`;
}

/** Nought to one, for a progress bar. Never above one. */
export function progressFraction(job: ProspectingJob): number {
  if (job.target <= 0) return 0;
  const done = job.type === 'BULK_ENRICHMENT' ? job.enriched : job.discovered;
  return Math.min(1, done / job.target);
}

export function isJobFinished(job: ProspectingJob): boolean {
  return !CLAIMABLE_JOB_STATUSES.includes(job.status);
}
