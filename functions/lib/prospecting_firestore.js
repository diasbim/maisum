"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.PROSPECTING_POLICIES = void 0;
exports.firestoreStore = firestoreStore;
exports.withCorrelationId = withCorrelationId;
exports.currentCorrelationId = currentCorrelationId;
exports.createJob = createJob;
exports.getJob = getJob;
exports.cancelJob = cancelJob;
exports.claimJob = claimJob;
exports.runJobBatch = runJobBatch;
exports.driveJob = driveJob;
exports.listClaimableJobs = listClaimableJobs;
exports.consumeProspectingRateLimit = consumeProspectingRateLimit;
const crypto_1 = require("crypto");
const admin = __importStar(require("firebase-admin"));
const affiliate_rate_limit_js_1 = require("./affiliate_rate_limit.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
const prospecting_jobs_js_1 = require("./prospecting_jobs.js");
const prospecting_pipeline_js_1 = require("./prospecting_pipeline.js");
const prospecting_store_js_1 = require("./prospecting_store.js");
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
function firestoreStore(settings) {
    const phoneCountryCode = settings.geography.phoneCountryCode;
    return {
        claimCompany: (company) => (0, prospecting_store_js_1.claimCompany)({ company, phoneCountryCode, now: Date.now() }),
        matchExistingCustomer: (company) => (0, prospecting_store_js_1.matchExistingCustomer)({ company, phoneCountryCode }),
        createProspect: async (input) => {
            const result = await (0, prospecting_store_js_1.createProspectForCompany)({
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
        saveScores: ({ prospectId, score }) => (0, prospecting_store_js_1.saveScores)({
            prospectId,
            total: score.total,
            businessFit: score.businessFit,
            digitalPresence: score.digitalPresence,
            retentionPotential: score.retentionPotential,
            commercialOpportunity: score.commercialOpportunity,
            band: score.band,
            now: Date.now(),
        }),
        updateCompanyListing: (input) => (0, prospecting_store_js_1.updateCompanyListing)({ ...input, now: Date.now() }),
        setStatus: async ({ prospectId, to, reason }) => {
            try {
                await (0, prospecting_store_js_1.setProspectStatus)({
                    prospectId,
                    to,
                    actor: 'system',
                    reason: reason ?? null,
                    now: Date.now(),
                });
            }
            catch (error) {
                // A lead that has moved past this stage is not an error in a re-run.
                if (!(error instanceof prospecting_store_js_1.TransitionError))
                    throw error;
            }
        },
        setEnrichment: async (input) => {
            const patch = {
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
            await prospecting_store_js_1.prospectingRefs.prospect(input.prospectId).set(patch, { merge: true });
        },
        saveContact: async ({ prospectId, person, isDecisionMaker }) => {
            await (0, prospecting_store_js_1.saveContact)({ prospectId, person, isDecisionMaker, now: Date.now() });
        },
        appendActivity: async ({ prospectId, type, description, metadata }) => {
            await (0, prospecting_store_js_1.appendActivity)({
                prospectId,
                type,
                description,
                metadata,
                actor: 'system',
                now: Date.now(),
            });
        },
        recordUsage: async (input) => {
            await (0, prospecting_store_js_1.recordUsage)({
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
        readSpend: (prospectId) => (0, prospecting_store_js_1.readSpend)({ now: Date.now(), prospectId }),
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
let correlationId = null;
function withCorrelationId(id, run) {
    const previous = correlationId;
    correlationId = id;
    return run().finally(() => {
        correlationId = previous;
    });
}
function currentCorrelationId() {
    return correlationId ?? 'unattributed';
}
/* ---------------------------------------------------------------- jobs */
async function createJob(job) {
    await prospecting_store_js_1.prospectingRefs.job(job.id).set(job);
}
async function getJob(jobId) {
    const snapshot = await prospecting_store_js_1.prospectingRefs.job(jobId).get();
    return snapshot.exists ? snapshot.data() : null;
}
async function cancelJob(jobId, now) {
    const ref = prospecting_store_js_1.prospectingRefs.job(jobId);
    return admin.firestore().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            return null;
        const job = snapshot.data();
        // Cancelling a finished job is a no-op rather than an error: an operator
        // pressing cancel on a job that completed a second earlier has not done
        // anything wrong.
        if ((0, prospecting_jobs_js_1.isJobFinished)(job))
            return job;
        const cancelled = (0, prospecting_jobs_js_1.cancelJob)(job, now);
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
async function claimJob(jobId, now) {
    const ref = prospecting_store_js_1.prospectingRefs.job(jobId);
    const claimId = (0, crypto_1.randomUUID)();
    return admin.firestore().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            return null;
        const job = snapshot.data();
        const decision = (0, prospecting_jobs_js_1.claimDecision)(job, now);
        if (!decision.claimable)
            return null;
        const claimed = {
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
async function runJobBatch(input) {
    const now = input.now ?? Date.now;
    let claimed;
    if (input.claimId === undefined) {
        claimed = await claimJob(input.jobId, now());
    }
    else {
        const held = await getJob(input.jobId);
        // Somebody else took it while this worker was busy. Theirs now.
        claimed =
            held === null || held.claim_id !== input.claimId
                ? null
                : { job: held, claimId: input.claimId };
    }
    if (claimed === null)
        return null;
    const { job, claimId } = claimed;
    const criteria = job.criteria;
    const outcome = await withCorrelationId(job.id, () => (0, prospecting_pipeline_js_1.runDiscoveryBatch)({
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
        batchSize: Math.min(prospecting_contracts_js_1.JOB_BATCH_SIZE, Math.max(1, job.target - job.discovered)),
        deps: input.deps(input.settings),
    }));
    const ref = prospecting_store_js_1.prospectingRefs.job(job.id);
    return admin.firestore().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            return null;
        const current = snapshot.data();
        if (current.claim_id !== claimId) {
            // Somebody else holds it now. Their counts are authoritative.
            return current;
        }
        const advanced = (0, prospecting_jobs_js_1.applyBatch)(current, outcome, now());
        // A job that is still running keeps its claim, with the lease pushed out
        // so the next batch does not race the sweep. `applyBatch` clears both on
        // every terminal outcome, and that is left alone.
        transaction.set(ref, advanced.status === 'RUNNING'
            ? { ...advanced, claim_id: claimId, claimed_until: now() + prospecting_contracts_js_1.JOB_LEASE_MS }
            : advanced);
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
async function driveJob(input) {
    const now = input.now ?? Date.now;
    const startedAt = now();
    const budget = input.timeBudgetMs ?? 420000;
    // Claimed once, then held for every batch in this invocation.
    const claimed = await claimJob(input.jobId, now());
    if (claimed === null)
        return null;
    let job = claimed.job;
    while (now() - startedAt < budget) {
        const advanced = await runJobBatch({
            jobId: input.jobId,
            deps: input.deps,
            settings: input.settings,
            now,
            claimId: claimed.claimId,
        });
        // Null means somebody else holds it, or it is gone. Either way, not ours.
        if (advanced === null)
            return job;
        job = advanced;
        if ((0, prospecting_jobs_js_1.isJobFinished)(advanced))
            return advanced;
    }
    return job;
}
/**
 * Every job a sweep should look at.
 *
 * Only the unfinished ones, oldest first, so a backlog drains in the order it
 * was created rather than the newest job starving the rest.
 */
async function listClaimableJobs(limit = 5) {
    const snapshot = await admin
        .firestore()
        .collection(prospecting_store_js_1.COLLECTIONS.jobs)
        .where('status', 'in', ['QUEUED', 'RUNNING'])
        .orderBy('created_at', 'asc')
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => doc.data());
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
exports.PROSPECTING_POLICIES = {
    search: { limit: 5, windowMs: 60000 },
    enrich: { limit: 30, windowMs: 60000 },
    analyze: { limit: 30, windowMs: 60000 },
    outreach: { limit: 30, windowMs: 60000 },
};
const DEFAULT_POLICY = { limit: 60, windowMs: 60000 };
/**
 * Consumes one unit of an operator's allowance.
 *
 * The state lives in Firestore rather than in memory, because Cloud Functions
 * run many instances and an in-process counter limits one instance while the
 * caller is being served by ten — the same reasoning, and the same pure
 * decision function, as the referral rate limiter.
 */
async function consumeProspectingRateLimit(input) {
    const now = input.now ?? Date.now();
    const policy = exports.PROSPECTING_POLICIES[input.action] ?? DEFAULT_POLICY;
    const windowStart = (0, affiliate_rate_limit_js_1.windowStartFor)(now, policy);
    const bucketId = (0, affiliate_rate_limit_js_1.rateLimitBucketId)({
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
        const decision = (0, affiliate_rate_limit_js_1.evaluateRateLimit)(existing, policy, now);
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
