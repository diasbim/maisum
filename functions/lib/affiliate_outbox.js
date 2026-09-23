"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AFFILIATE_ADDRESSED_TEMPLATES = exports.MAX_LAST_ERROR_LENGTH = exports.OUTBOX_MAX_BATCH = exports.OUTBOX_BATCH_LIMIT = exports.NOT_CONFIGURED_RECHECK_MS = exports.OUTBOX_LEASE_MS = exports.CLAIMABLE_STATUSES = exports.OUTBOX_STATUS = void 0;
exports.parseOutboxRecord = parseOutboxRecord;
exports.isClaimable = isClaimable;
exports.claimPatch = claimPatch;
exports.truncateError = truncateError;
exports.planOutboxTransition = planOutboxTransition;
exports.transitionPatch = transitionPatch;
exports.composeOutboxMessage = composeOutboxMessage;
exports.claimOutboxMessage = claimOutboxMessage;
exports.releaseOutboxMessage = releaseOutboxMessage;
exports.processOutboxMessage = processOutboxMessage;
exports.processAffiliateOutbox = processAffiliateOutbox;
const crypto_1 = require("crypto");
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
/* ------------------------------------------------------------------ states */
exports.OUTBOX_STATUS = [
    'QUEUED',
    'PROCESSING',
    'SENT',
    'SKIPPED',
    'FAILED',
    'NOT_CONFIGURED',
];
/** States a sweep may pick up. Terminal rows are never queried again. */
exports.CLAIMABLE_STATUSES = [
    'QUEUED',
    'NOT_CONFIGURED',
    'PROCESSING',
];
/**
 * How long a claim holds a message before another worker may take it.
 *
 * Longer than any single delivery attempt should take, short enough that a
 * crashed instance does not strand a congratulation for an hour.
 */
exports.OUTBOX_LEASE_MS = 120000;
/**
 * How long a message waits before asking again whether a provider exists.
 *
 * Without a delay, every sweep would re-claim the whole unconfigured backlog
 * on every run; with one, the backlog is checked hourly and sends itself the
 * hour after a provider is configured.
 */
exports.NOT_CONFIGURED_RECHECK_MS = 3600000;
/** Messages one invocation may process. Bounded so a trigger cannot run long. */
exports.OUTBOX_BATCH_LIMIT = 25;
exports.OUTBOX_MAX_BATCH = 100;
/** Provider errors are stored to be read by a person, not to be a payload. */
exports.MAX_LAST_ERROR_LENGTH = 300;
function str(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'string' && value.trim() !== '')
            return value.trim();
    }
    return null;
}
function num(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'number' && Number.isFinite(value))
            return value;
    }
    return null;
}
/**
 * Reads a stored row into the shape the worker reasons about.
 *
 * `retry_count` is the referral spec's name for the attempt counter and
 * `attempts` is what the sale transaction writes. Both are read, both are
 * written, and both always come from the same number — see `countPatch` — so
 * they cannot drift into two different answers.
 */
function parseOutboxRecord(merchantId, id, data) {
    const status = str(data, 'status')?.toUpperCase() ?? 'QUEUED';
    const template = data.template;
    return {
        id,
        merchantId,
        affiliateId: str(data, 'affiliate_id'),
        template: (0, affiliate_notifications_js_1.isAffiliateTemplate)(template) ? template : null,
        sourceKey: str(data, 'source_key') ?? '',
        status: exports.OUTBOX_STATUS.includes(status)
            ? status
            : 'QUEUED',
        attempts: Math.max(0, Math.floor(num(data, 'retry_count', 'attempts') ?? 0)),
        nextAttemptAt: num(data, 'next_attempt_at') ?? 0,
        lastError: str(data, 'last_error'),
        payload: data.payload !== null && typeof data.payload === 'object'
            ? data.payload
            : {},
        claimId: str(data, 'claim_id'),
        claimedAt: num(data, 'claimed_at'),
    };
}
/** Whether this worker may take the message now. */
function isClaimable(record, now) {
    if (!exports.CLAIMABLE_STATUSES.includes(record.status))
        return false;
    if (record.nextAttemptAt > now)
        return false;
    if (record.status === 'PROCESSING') {
        // Only a lapsed claim, so two live workers never hold the same message.
        return (record.claimedAt ?? 0) + exports.OUTBOX_LEASE_MS <= now;
    }
    return true;
}
function countPatch(attempts) {
    return { attempts, retry_count: attempts };
}
/**
 * The write that takes a message.
 *
 * The attempt is counted here rather than after delivery, so a worker that
 * dies mid-send has still used one — the alternative retries an attempt that
 * may have reached the provider, forever. `not_configured` gives the attempt
 * back, because a provider that does not exist was never tried.
 */
function claimPatch(record, claimId, now) {
    return {
        status: 'PROCESSING',
        ...countPatch(record.attempts + 1),
        claim_id: claimId,
        claimed_at: now,
        // Doubles as the lease: a lapsed claim becomes due to the pending query.
        next_attempt_at: now + exports.OUTBOX_LEASE_MS,
        updated_at: now,
    };
}
function truncateError(error) {
    const clean = error.replace(/\s+/g, ' ').trim();
    return clean.length <= exports.MAX_LAST_ERROR_LENGTH
        ? clean
        : `${clean.slice(0, exports.MAX_LAST_ERROR_LENGTH - 1)}…`;
}
/**
 * What one delivery outcome does to the row.
 *
 * Pure, and the only place the state machine is written down: every caller
 * either applies this or is wrong.
 */
function planOutboxTransition(input) {
    const { attemptsBeforeClaim, outcome, now } = input;
    const attempts = attemptsBeforeClaim + 1;
    if (outcome.status === 'sent') {
        return {
            status: 'SENT',
            attempts,
            nextAttemptAt: null,
            lastError: null,
            terminal: true,
        };
    }
    if (outcome.status === 'skipped') {
        // A decision, not an attempt: the counter is handed back so a later read
        // of this row does not suggest the provider was ever asked.
        return {
            status: 'SKIPPED',
            attempts: attemptsBeforeClaim,
            nextAttemptAt: null,
            lastError: outcome.reason,
            terminal: true,
        };
    }
    if (outcome.status === 'not_configured') {
        return {
            status: 'NOT_CONFIGURED',
            attempts: attemptsBeforeClaim,
            nextAttemptAt: now + exports.NOT_CONFIGURED_RECHECK_MS,
            lastError: null,
            terminal: false,
        };
    }
    const terminal = (0, affiliate_notifications_js_1.isTerminalDelivery)(outcome, attempts);
    return {
        status: terminal ? 'FAILED' : 'QUEUED',
        attempts,
        nextAttemptAt: terminal ? null : now + (0, affiliate_notifications_js_1.nextAttemptDelayMs)(attempts),
        lastError: truncateError(outcome.error),
        terminal,
    };
}
/** The transition as a document patch, including what the outcome carries. */
function transitionPatch(transition, outcome, now) {
    const patch = {
        status: transition.status,
        ...countPatch(transition.attempts),
        next_attempt_at: transition.nextAttemptAt,
        last_error: transition.lastError,
        claim_id: null,
        claimed_at: null,
        updated_at: now,
    };
    if (outcome.status === 'sent') {
        patch.sent_at = now;
        patch.provider_message_id = outcome.providerMessageId;
    }
    if (outcome.status === 'skipped') {
        patch.skipped_at = now;
        patch.skip_reason = outcome.reason;
    }
    return patch;
}
/** Templates addressed to the affiliate rather than to the customer. */
exports.AFFILIATE_ADDRESSED_TEMPLATES = [
    'affiliate_new_customer',
    'affiliate_customer_returned',
];
/**
 * Builds the message, or refuses with the reason.
 *
 * The body is composed here, from the merchant's own data and the stored
 * template — never from anything a caller supplied. A client-provided body
 * would let a till send arbitrary WhatsApp in the business's name, and a
 * client-provided number would let it send that text to anyone.
 */
function composeOutboxMessage(record, context) {
    if (record.template === null) {
        return {
            ok: false,
            outcome: { status: 'failed', retryable: false, error: 'unknown_template' },
        };
    }
    if (!context.notificationsEnabled) {
        return { ok: false, outcome: { status: 'skipped', reason: 'notifications_disabled' } };
    }
    if (context.blockedReason !== null) {
        return { ok: false, outcome: { status: 'skipped', reason: context.blockedReason } };
    }
    const phone = context.recipientPhoneE164?.trim() ?? '';
    if (phone === '') {
        return { ok: false, outcome: { status: 'skipped', reason: 'no_phone' } };
    }
    const body = (0, affiliate_notifications_js_1.renderAffiliateMessage)(record.template, {
        points: context.points,
        merchantName: context.merchantName ?? undefined,
        statusText: exports.AFFILIATE_ADDRESSED_TEMPLATES.includes(record.template)
            ? (0, affiliate_notifications_js_1.rewardStatusText)(context.rewardStatus ?? 'PENDING')
            : undefined,
    });
    return {
        ok: true,
        message: {
            // The row's own id: derived from merchant, template and source, so a
            // provider that dedupes on it cannot be made to send twice.
            idempotencyKey: record.id,
            merchantId: record.merchantId,
            template: record.template,
            toPhoneE164: phone,
            body,
        },
    };
}
function clockOf(deps) {
    return deps.now ? deps.now() : Date.now();
}
function emit(deps, level, entry) {
    if (deps.log) {
        deps.log(level, entry);
        return;
    }
    const { event, ...fields } = entry;
    if (level === 'error')
        console.error(event, fields);
    else
        console.info(event, fields);
}
/**
 * Takes one message, in one transaction, or reports that somebody else has it.
 *
 * Read and write in the same transaction is the entire point: two workers that
 * both read a QUEUED row will not both write PROCESSING to it — the second
 * transaction is retried against the first one's write and then sees a claim.
 */
async function claimOutboxMessage(store, input) {
    return store.runTransaction(async (transaction) => {
        const data = await transaction.get(input.merchantId, input.outboxId);
        if (data === null)
            return { status: 'missing' };
        const record = parseOutboxRecord(input.merchantId, input.outboxId, data);
        if (!isClaimable(record, input.now)) {
            return { status: 'held', record };
        }
        transaction.update(input.merchantId, input.outboxId, claimPatch(record, input.claimId, input.now));
        return {
            status: 'claimed',
            attemptsBeforeClaim: record.attempts,
            record: {
                ...record,
                status: 'PROCESSING',
                attempts: record.attempts + 1,
                claimId: input.claimId,
                claimedAt: input.now,
            },
        };
    });
}
/**
 * Writes the outcome, but only if this worker still holds the message.
 *
 * A claim that lapsed while a slow provider was answering belongs to somebody
 * else by now; overwriting it would undo their attempt and could send twice.
 */
async function releaseOutboxMessage(store, input) {
    return store.runTransaction(async (transaction) => {
        const data = await transaction.get(input.merchantId, input.outboxId);
        if (data === null)
            return 'lost';
        const record = parseOutboxRecord(input.merchantId, input.outboxId, data);
        if (record.claimId !== input.claimId)
            return 'lost';
        transaction.update(input.merchantId, input.outboxId, input.patch);
        return 'released';
    });
}
function resultOf(outcome, transition) {
    if (outcome.status === 'sent')
        return 'sent';
    if (outcome.status === 'skipped')
        return 'skipped';
    if (outcome.status === 'not_configured')
        return 'not_configured';
    return transition.terminal ? 'failed' : 'retry';
}
/**
 * Claims, sends and records one message.
 *
 * Every failure path — a context that cannot be read, a provider that throws,
 * an adapter that hangs — ends in a stored outcome rather than an exception,
 * because the callers are a Firestore trigger and a sweep: a throw there is a
 * retriggered function, and a retriggered function on a message that was
 * already sent is a second message.
 */
async function processOutboxMessage(deps, merchantId, outboxId) {
    const now = clockOf(deps);
    const claimId = deps.newClaimId ? deps.newClaimId() : (0, crypto_1.randomUUID)();
    const claim = await claimOutboxMessage(deps.store, {
        merchantId,
        outboxId,
        claimId,
        now,
    });
    if (claim.status === 'missing') {
        emit(deps, 'error', {
            event: 'affiliate_outbox_missing',
            merchant_id: merchantId,
            outbox_id: outboxId,
            template: null,
            status: 'MISSING',
            attempts: 0,
            phone_masked: null,
            error: null,
        });
        return { result: 'missing' };
    }
    if (claim.status === 'held') {
        // The ordinary duplicate: a retriggered create, or a sweep overlapping the
        // trigger. Not an error, and deliberately not a send.
        emit(deps, 'info', {
            event: 'affiliate_outbox_held',
            merchant_id: merchantId,
            outbox_id: outboxId,
            template: claim.record.template,
            status: 'HELD',
            attempts: claim.record.attempts,
            phone_masked: null,
            error: null,
        });
        return { result: 'held' };
    }
    const record = claim.record;
    let outcome;
    let phoneMasked = null;
    try {
        const context = await deps.resolveContext(record);
        const composed = composeOutboxMessage(record, context);
        if (!composed.ok) {
            outcome = composed.outcome;
        }
        else {
            phoneMasked = (0, affiliate_notifications_js_1.maskPhone)(composed.message.toPhoneE164);
            outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(composed.message, {
                adapter: deps.adapter,
                notificationsEnabled: context.notificationsEnabled,
            });
        }
    }
    catch (error) {
        outcome = {
            status: 'failed',
            retryable: true,
            error: error instanceof Error ? error.message : String(error),
        };
    }
    const resolvedAt = clockOf(deps);
    const transition = planOutboxTransition({
        attemptsBeforeClaim: claim.attemptsBeforeClaim,
        outcome,
        now: resolvedAt,
    });
    const released = await releaseOutboxMessage(deps.store, {
        merchantId,
        outboxId,
        claimId,
        patch: transitionPatch(transition, outcome, resolvedAt),
    });
    const entry = {
        event: outcome.status === 'failed'
            ? 'affiliate_outbox_delivery_failed'
            : `affiliate_outbox_${outcome.status}`,
        merchant_id: merchantId,
        outbox_id: outboxId,
        template: record.template,
        status: transition.status,
        attempts: transition.attempts,
        phone_masked: phoneMasked,
        error: transition.lastError,
    };
    emit(deps, outcome.status === 'failed' ? 'error' : 'info', entry);
    if (released === 'lost')
        return { result: 'lost' };
    return { result: resultOf(outcome, transition), transition, outcome };
}
/**
 * Processes the due backlog, bounded.
 *
 * Sequential on purpose: the queue is small per business, and a parallel fan
 * out would multiply the read cost of a provider outage while making the
 * per-invocation bound meaningless.
 */
async function processAffiliateOutbox(deps, input = {}) {
    const limit = Math.max(1, Math.min(Math.floor(input.limit ?? exports.OUTBOX_BATCH_LIMIT), exports.OUTBOX_MAX_BATCH));
    const pending = await deps.store.listPending({
        merchantId: input.merchantId ?? null,
        limit,
        now: clockOf(deps),
    });
    const summary = {
        scanned: 0,
        sent: 0,
        skipped: 0,
        retried: 0,
        failed: 0,
        not_configured: 0,
        held: 0,
    };
    for (const document of pending) {
        summary.scanned += 1;
        const processed = await processOutboxMessage(deps, document.merchantId, document.id);
        switch (processed.result) {
            case 'sent':
                summary.sent += 1;
                break;
            case 'skipped':
                summary.skipped += 1;
                break;
            case 'retry':
                summary.retried += 1;
                break;
            case 'failed':
                summary.failed += 1;
                break;
            case 'not_configured':
                summary.not_configured += 1;
                break;
            default:
                summary.held += 1;
                break;
        }
    }
    return summary;
}
