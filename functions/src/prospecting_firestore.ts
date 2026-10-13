import { randomUUID } from 'crypto';

import * as admin from 'firebase-admin';

import {
  evaluateRateLimit,
  rateLimitBucketId,
  windowStartFor,
  type RateLimitPolicy,
} from './affiliate_rate_limit.js';
import {
  JOB_BATCH_SIZE,
  JOB_LEASE_MS,
  type JobStatus,
} from './prospecting_contracts.js';
import {
  applyBatch,
  cancelJob as cancelJobRecord,
  claimDecision,
  isJobFinished,
  type ProspectingJob,
} from './prospecting_jobs.js';
import {
  runDiscoveryBatch,
  type DiscoveryCriteria,
  type PipelineDeps,
  type PipelineStore,
} from './prospecting_pipeline.js';
import type { ProspectingSettings } from './prospecting_config.js';
import {
  appendActivity,
  claimCompany,
  COLLECTIONS,
  createProspectForCompany,
  matchExistingCustomer,
  prospectingRefs,
  readSpend,
  recordUsage,
  saveContact,
  saveScores,
  setProspectStatus,
  TransitionError,
  updateCompanyListing,
} from './prospecting_store.js';

/**
 * The Firestore side of prospecting: the store port, the job worker and the
 * rate limiter.
 *
 * Everything here is glue. The decisions live in the pure modules — the
 * pipeline decides what to do with a discovered business, `claimDecision`
 * decides whether a job may be taken, `evaluateRateLimit` decides whether a
 * caller is over the limit — and this file does nothing but read documents,
 * hand them to those functions, and write back what they return.
 */

/* ------------------------------------------------------------- the store */

/**
 * The pipeline's store port, over Firestore.
 *
 * `setStatus` swallows a `TransitionError` on purpose, and only here. The
 * pipeline moves a fresh prospect RAW → QUALIFIED → SCORED, and re-running a
 * search over a business already at `CONTACTED` would otherwise fail the whole
 * batch for a transition that is refused for exactly the right reason. An
 * operator's status change goes through `setProspectStatus` directly, where
 * the refusal is a 409 they can see.
 */
export function firestoreStore(settings: ProspectingSettings): PipelineStore {
  const phoneCountryCode = settings.geography.phoneCountryCode;

  return {
    claimCompany: (company) =>
      claimCompany({ company, phoneCountryCode, now: Date.now() }),

    matchExistingCustomer: (company) =>
      matchExistingCustomer({ company, phoneCountryCode }),

    createProspect: async (input) => {
      const result = await createProspectForCompany({
        companyId: input.companyId,
        source: input.source,
        sourceReference: input.sourceReference,
        status: input.status,
        suspectedMerchantId: input.suspectedMerchantId ?? null,
        disqualifyReason: input.disqualifyReason ?? null,
        now: Date.now(),
      });
      return { prospectId: result.prospect.id, created: result.created };
    },

    saveScores: ({ prospectId, score }) =>
      saveScores({
        prospectId,
        total: score.total,
        businessFit: score.businessFit,
        digitalPresence: score.digitalPresence,
        retentionPotential: score.retentionPotential,
        commercialOpportunity: score.commercialOpportunity,
        band: score.band,
        now: Date.now(),
      }),

    updateCompanyListing: (input) =>
      updateCompanyListing({ ...input, now: Date.now() }),

    setStatus: async ({ prospectId, to, reason }) => {
      try {
        await setProspectStatus({
          prospectId,
          to,
          actor: 'system',
          reason: reason ?? null,
          now: Date.now(),
        });
      } catch (error) {
        // A lead that has moved past this stage is not an error in a re-run.
        if (!(error instanceof TransitionError)) throw error;
      }
    },

    setEnrichment: async (input) => {
      const patch: Record<string, unknown> = {
        enrichment_status: input.status,
        updated_at: Date.now(),
      };
      if (input.lastEnrichedAt !== undefined) {
        patch.last_enriched_at = input.lastEnrichedAt;
      }
      if (input.decisionMakerCount !== undefined) {
        patch.decision_maker_count = input.decisionMakerCount;
      }
      if (input.hasReachableContact !== undefined) {
        patch.has_reachable_contact = input.hasReachableContact;
      }
      await prospectingRefs.prospect(input.prospectId).set(patch, { merge: true });
    },

    saveContact: async ({ prospectId, person, isDecisionMaker }) => {
      await saveContact({ prospectId, person, isDecisionMaker, now: Date.now() });
    },

    appendActivity: async ({ prospectId, type, description, metadata }) => {
      await appendActivity({
        prospectId,
        type,
        description,
        metadata,
        actor: 'system',
        now: Date.now(),
      });
    },

    recordUsage: async (input) => {
      await recordUsage({
        provider: input.provider,
        operation: input.operation,
        prospectId: input.prospectId,
        estimatedCostUsd: input.estimatedCostUsd,
        // Only AIsa reports what it charged, through `X-AISA-Price-USD`.
        // Everything else leaves this null and the month's total says it is
        // estimated; writing the estimate into both fields would turn a guess
        // into a figure somebody plans against.
        actualCostUsd: input.actualCostUsd ?? null,
        creditsUsed: null,
        success: input.success,
        errorCode: input.errorCode,
        correlationId: currentCorrelationId(),
        now: Date.now(),
      });
    },

    readSpend: (prospectId) => readSpend({ now: Date.now(), prospectId }),
  };
}

/**
 * The id that ties one operator action to every provider call it caused.
 *
 * Set by the route or the worker before the pipeline runs, so a usage row, a
 * log line and an audit event can be lined up afterwards. Module-level rather
 * than threaded through twelve signatures: a Cloud Functions instance handles
 * one request at a time in the path that matters here, and the alternative is
 * a parameter on every function in the pipeline that only observability uses.
 */
let correlationId: string | null = null;

export function withCorrelationId<T>(id: string, run: () => Promise<T>): Promise<T> {
  const previous = correlationId;
  correlationId = id;
  return run().finally(() => {
    correlationId = previous;
  });
}

export function currentCorrelationId(): string {
  return correlationId ?? 'unattributed';
}

/* ---------------------------------------------------------------- jobs */

export async function createJob(job: ProspectingJob): Promise<void> {
  await prospectingRefs.job(job.id).set(job);
}

export async function getJob(jobId: string): Promise<ProspectingJob | null> {
  const snapshot = await prospectingRefs.job(jobId).get();
  return snapshot.exists ? (snapshot.data() as ProspectingJob) : null;
}

export async function cancelJob(
  jobId: string,
  now: number,
): Promise<ProspectingJob | null> {
  const ref = prospectingRefs.job(jobId);

  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;

    const job = snapshot.data() as ProspectingJob;
    // Cancelling a finished job is a no-op rather than an error: an operator
    // pressing cancel on a job that completed a second earlier has not done
    // anything wrong.
    if (isJobFinished(job)) return job;

    const cancelled = cancelJobRecord(job, now);
    transaction.set(ref, cancelled);
    return cancelled;
  });
}

/**
 * Takes a job, if nobody else holds it.
 *
 * The claim is a transaction that stamps a claim id and a lease. A second
 * worker — a duplicate trigger, an overlapping sweep — reads the claimed row
 * and stops. Without it, one search would run twice and charge twice.
 */
export async function claimJob(
  jobId: string,
  now: number,
): Promise<{ job: ProspectingJob; claimId: string } | null> {
  const ref = prospectingRefs.job(jobId);
  const claimId = randomUUID();

  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;

    const job = snapshot.data() as ProspectingJob;
    const decision = claimDecision(job, now);
    if (!decision.claimable) return null;

    const claimed: ProspectingJob = {
      ...job,
      status: 'RUNNING',
      claim_id: claimId,
      claimed_until: decision.claimedUntil,
      updated_at: now,
    };

    transaction.set(ref, claimed);
    return { job: claimed, claimId };
  });
}

/**
 * Runs one batch of a job and writes the result back.
 *
 * Bounded: one invocation processes `JOB_BATCH_SIZE` businesses and then
 * returns, leaving the job claimable again for the next sweep. A worker that
 * looped until the job finished would hold a Cloud Functions instance for
 * minutes and lose everything if it timed out.
 *
 * The write is conditional on still holding the claim. A worker whose lease
 * lapsed mid-batch has had its job taken by somebody else, and writing its
 * counts over theirs would double-count every business both of them saw.
 */
export async function runJobBatch(input: {
  jobId: string;
  deps: (settings: ProspectingSettings) => PipelineDeps;
  settings: ProspectingSettings;
  now?: () => number;
  /**
   * A claim this worker already holds.
   *
   * Without it, a caller running several batches in a row would try to claim a
   * job it is itself holding, `claimDecision` would correctly refuse — the
   * lease is live — and the run would stop after one batch, leaving the job
   * `RUNNING` until its lease lapsed. A search of five hundred businesses
   * would then advance ten at a time, once every lease period.
   */
  claimId?: string;
}): Promise<ProspectingJob | null> {
  const now = input.now ?? Date.now;

  let claimed: { job: ProspectingJob; claimId: string } | null;
  if (input.claimId === undefined) {
    claimed = await claimJob(input.jobId, now());
  } else {
    const held = await getJob(input.jobId);
    // Somebody else took it while this worker was busy. Theirs now.
    claimed =
      held === null || held.claim_id !== input.claimId
        ? null
        : { job: held, claimId: input.claimId };
  }
  if (claimed === null) return null;

  const { job, claimId } = claimed;
  const criteria = job.criteria as unknown as DiscoveryCriteria;

  const outcome = await withCorrelationId(job.id, () =>
    runDiscoveryBatch({
      criteria: {
        industries: Array.isArray(criteria.industries) ? criteria.industries : [],
        city: criteria.city ?? null,
        province: criteria.province ?? null,
        employeeMin: criteria.employeeMin ?? null,
        employeeMax: criteria.employeeMax ?? null,
        minScore: criteria.minScore ?? 60,
        maxLeads: job.target,
      },
      cursor: job.cursor,
      batchSize: Math.min(JOB_BATCH_SIZE, Math.max(1, job.target - job.discovered)),
      deps: input.deps(input.settings),
    }),
  );

  const ref = prospectingRefs.job(job.id);
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;

    const current = snapshot.data() as ProspectingJob;
    if (current.claim_id !== claimId) {
      // Somebody else holds it now. Their counts are authoritative.
      return current;
    }

    const advanced = applyBatch(current, outcome, now());

    // A job that is still running keeps its claim, with the lease pushed out
    // so the next batch does not race the sweep. `applyBatch` clears both on
    // every terminal outcome, and that is left alone.
    transaction.set(
      ref,
      advanced.status === 'RUNNING'
        ? { ...advanced, claim_id: claimId, claimed_until: now() + JOB_LEASE_MS }
        : advanced,
    );
    return advanced;
  });
}

/**
 * Drives a job to completion, a batch at a time, within a time budget.
 *
 * Used by the trigger that fires when a job is created, and by the scheduled
 * sweep. The budget is what keeps one invocation inside the platform's
 * timeout; whatever is left stays `RUNNING` with a lapsed lease, and the next
 * sweep picks it up exactly where the cursor says.
 */
export async function driveJob(input: {
  jobId: string;
  deps: (settings: ProspectingSettings) => PipelineDeps;
  settings: ProspectingSettings;
  timeBudgetMs?: number;
  now?: () => number;
}): Promise<ProspectingJob | null> {
  const now = input.now ?? Date.now;
  const startedAt = now();
  const budget = input.timeBudgetMs ?? 420_000;

  // Claimed once, then held for every batch in this invocation.
  const claimed = await claimJob(input.jobId, now());
  if (claimed === null) return null;

  let job: ProspectingJob = claimed.job;

  while (now() - startedAt < budget) {
    const advanced = await runJobBatch({
      jobId: input.jobId,
      deps: input.deps,
      settings: input.settings,
      now,
      claimId: claimed.claimId,
    });

    // Null means somebody else holds it, or it is gone. Either way, not ours.
    if (advanced === null) return job;
    job = advanced;
    if (isJobFinished(advanced)) return advanced;
  }

  return job;
}

/**
 * Every job a sweep should look at.
 *
 * Only the unfinished ones, oldest first, so a backlog drains in the order it
 * was created rather than the newest job starving the rest.
 */
export async function listClaimableJobs(limit = 5): Promise<ProspectingJob[]> {
  const snapshot = await admin
    .firestore()
    .collection(COLLECTIONS.jobs)
    .where('status', 'in', ['QUEUED', 'RUNNING'] satisfies JobStatus[])
    .orderBy('created_at', 'asc')
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => doc.data() as ProspectingJob);
}

/* ---------------------------------------------------------- rate limiting */

/**
 * What one operator may ask for, per action.
 *
 * Not about load — there are four of them. It is about a retry loop in a
 * browser tab spending a month's budget in a minute, which a person clicking
 * "enriquecer" on a slow connection will produce without meaning to. Search is
 * tighter than the rest because one search is the most expensive thing the
 * module can be asked to do.
 */
export const PROSPECTING_POLICIES: Record<string, RateLimitPolicy> = {
  search: { limit: 5, windowMs: 60_000 },
  enrich: { limit: 30, windowMs: 60_000 },
  analyze: { limit: 30, windowMs: 60_000 },
  outreach: { limit: 30, windowMs: 60_000 },
};

const DEFAULT_POLICY: RateLimitPolicy = { limit: 60, windowMs: 60_000 };

/**
 * Consumes one unit of an operator's allowance.
 *
 * The state lives in Firestore rather than in memory, because Cloud Functions
 * run many instances and an in-process counter limits one instance while the
 * caller is being served by ten — the same reasoning, and the same pure
 * decision function, as the referral rate limiter.
 */
export async function consumeProspectingRateLimit(input: {
  actorId: string;
  action: string;
  now?: number;
}): Promise<boolean> {
  const now = input.now ?? Date.now();
  const policy = PROSPECTING_POLICIES[input.action] ?? DEFAULT_POLICY;
  const windowStart = windowStartFor(now, policy);

  const bucketId = rateLimitBucketId({
    // Prospecting is not scoped to a merchant; the constant keeps the id
    // shape identical to the referral buckets so one sweep can expire both.
    merchantId: 'prospecting',
    actorId: input.actorId,
    action: input.action,
    windowStart,
  });

  const ref = admin
    .firestore()
    .collection('prospecting_rate_limits')
    .doc(bucketId);

  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const existing = snapshot.exists
      ? {
          windowStart: Number((snapshot.data() ?? {}).window_start ?? 0),
          count: Number((snapshot.data() ?? {}).count ?? 0),
        }
      : null;

    const decision = evaluateRateLimit(existing, policy, now);

    transaction.set(ref, {
      window_start: decision.bucket.windowStart,
      count: decision.bucket.count,
      action: input.action,
      updated_at: now,
      // Read by a TTL policy, so an expired bucket is swept rather than
      // needing a cleanup job.
      expires_at: new Date(decision.bucket.windowStart + policy.windowMs * 2),
    });

    return decision.allowed;
  });
}
