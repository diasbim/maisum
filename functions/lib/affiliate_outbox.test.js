"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
const affiliate_outbox_js_1 = require("./affiliate_outbox.js");
/**
 * The queue between a committed sale and a WhatsApp message.
 *
 * Two properties are worth a test suite of their own, and neither is visible
 * from a single function: a message is sent at most once even though the
 * trigger that delivers it can fire twice, and a sale is never harmed by
 * anything that happens here.
 *
 * So the store is a port and the fake below behaves the way Firestore does in
 * the way that decides both: a transaction that reads a document somebody else
 * writes before it commits is retried against the new value rather than
 * overwriting it. That is what makes the claim a claim. With a fake that
 * simply serialised everything, the concurrency test would pass against an
 * implementation with no transaction in it at all.
 */
const MERCHANT = 'm1';
const OUTBOX_ID = 'ao_1';
const NOW = 1800000000000;
/* ------------------------------------------------------------- the fake db */
class FakeOutboxStore {
    constructor() {
        this.docs = new Map();
        this.transactions = 0;
        /** Runs once, after the next transaction reads and before it commits. */
        this.interleave = null;
    }
    key(merchantId, outboxId) {
        return `${merchantId}/${outboxId}`;
    }
    put(merchantId, outboxId, data) {
        this.docs.set(this.key(merchantId, outboxId), { data, version: 1 });
    }
    read(merchantId = MERCHANT, outboxId = OUTBOX_ID) {
        const entry = this.docs.get(this.key(merchantId, outboxId));
        strict_1.default.ok(entry, `no document at ${merchantId}/${outboxId}`);
        return entry.data;
    }
    async runTransaction(run) {
        for (let attempt = 0; attempt < 5; attempt++) {
            this.transactions += 1;
            const readVersions = new Map();
            const staged = new Map();
            const transaction = {
                get: async (merchantId, outboxId) => {
                    const key = this.key(merchantId, outboxId);
                    const entry = this.docs.get(key);
                    readVersions.set(key, entry?.version ?? 0);
                    return entry === undefined ? null : { ...entry.data };
                },
                update: (merchantId, outboxId, patch) => {
                    const key = this.key(merchantId, outboxId);
                    staged.set(key, { ...(staged.get(key) ?? {}), ...patch });
                },
            };
            const result = await run(transaction);
            const hook = this.interleave;
            this.interleave = null;
            if (hook)
                await hook();
            const stale = [...readVersions].some(([key, version]) => (this.docs.get(key)?.version ?? 0) !== version);
            // Exactly what Firestore does: somebody wrote what we read, so the whole
            // transaction runs again against the new value.
            if (stale)
                continue;
            for (const [key, patch] of staged) {
                const entry = this.docs.get(key);
                this.docs.set(key, {
                    data: { ...(entry?.data ?? {}), ...patch },
                    version: (entry?.version ?? 0) + 1,
                });
            }
            return result;
        }
        throw new Error('transaction contention');
    }
    async listPending(input) {
        const rows = [];
        for (const [key, entry] of this.docs) {
            const [merchantId, id] = key.split('/');
            if (input.merchantId !== null && merchantId !== input.merchantId)
                continue;
            const status = String(entry.data.status ?? 'QUEUED');
            if (!affiliate_outbox_js_1.CLAIMABLE_STATUSES.includes(status))
                continue;
            if (Number(entry.data.next_attempt_at ?? 0) > input.now)
                continue;
            rows.push({ merchantId, id, data: { ...entry.data } });
        }
        rows.sort((left, right) => Number(left.data.next_attempt_at ?? 0) - Number(right.data.next_attempt_at ?? 0));
        return rows.slice(0, input.limit);
    }
}
/* -------------------------------------------------------------- fixtures */
function queuedRow(overrides = {}) {
    return {
        id: OUTBOX_ID,
        merchant_id: MERCHANT,
        affiliate_id: 'af1',
        template: 'affiliate_new_customer',
        source_key: 'sale_1',
        status: 'QUEUED',
        attempts: 0,
        retry_count: 0,
        next_attempt_at: NOW - 1,
        last_error: null,
        payload: { reward_id: 'ar_1', reward_points: 150, reward_status: 'PENDING' },
        created_at: NOW - 1,
        updated_at: NOW - 1,
        ...overrides,
    };
}
function record(overrides = {}) {
    return {
        ...(0, affiliate_outbox_js_1.parseOutboxRecord)(MERCHANT, OUTBOX_ID, queuedRow()),
        ...overrides,
    };
}
function context(overrides = {}) {
    return {
        merchantName: 'Café Central',
        notificationsEnabled: true,
        recipientPhoneE164: '+258841234567',
        blockedReason: null,
        points: 150,
        rewardStatus: 'PENDING',
        ...overrides,
    };
}
function harness(options = {}) {
    const store = new FakeOutboxStore();
    store.put(MERCHANT, OUTBOX_ID, options.row ?? queuedRow());
    const sent = [];
    const logs = [];
    const clock = { now: NOW };
    const adapter = options.adapter === undefined
        ? {
            async send(message) {
                sent.push(message);
                return { providerMessageId: `wamid.${sent.length}` };
            },
        }
        : options.adapter;
    const deps = {
        store,
        adapter,
        resolveContext: options.resolveContext ?? (async () => context(options.context ?? {})),
        now: () => clock.now,
        log: (level, entry) => logs.push({ level, entry }),
    };
    return { store, deps, sent, logs, clock };
}
/* ====================================================== the state machine */
(0, node_test_1.default)('a sent message is finished and asks for nothing else', () => {
    const transition = (0, affiliate_outbox_js_1.planOutboxTransition)({
        attemptsBeforeClaim: 0,
        outcome: { status: 'sent', providerMessageId: 'wamid.1' },
        now: NOW,
    });
    strict_1.default.equal(transition.status, 'SENT');
    strict_1.default.equal(transition.terminal, true);
    strict_1.default.equal(transition.attempts, 1);
    strict_1.default.equal(transition.nextAttemptAt, null);
    strict_1.default.equal(transition.lastError, null);
});
(0, node_test_1.default)('a retryable failure goes back to the queue, later each time', () => {
    const failure = { status: 'failed', retryable: true, error: 'boom' };
    const first = (0, affiliate_outbox_js_1.planOutboxTransition)({ attemptsBeforeClaim: 0, outcome: failure, now: NOW });
    const second = (0, affiliate_outbox_js_1.planOutboxTransition)({ attemptsBeforeClaim: 1, outcome: failure, now: NOW });
    strict_1.default.equal(first.status, 'QUEUED');
    strict_1.default.equal(first.terminal, false);
    strict_1.default.equal(first.nextAttemptAt, NOW + (0, affiliate_notifications_js_1.nextAttemptDelayMs)(1));
    strict_1.default.ok((second.nextAttemptAt ?? 0) > (first.nextAttemptAt ?? 0));
    strict_1.default.equal(second.attempts, 2);
});
(0, node_test_1.default)('failures stop at the cap instead of retrying forever', () => {
    const transition = (0, affiliate_outbox_js_1.planOutboxTransition)({
        attemptsBeforeClaim: affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS - 1,
        outcome: { status: 'failed', retryable: true, error: 'boom' },
        now: NOW,
    });
    strict_1.default.equal(transition.attempts, affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS);
    strict_1.default.equal(transition.status, 'FAILED');
    strict_1.default.equal(transition.terminal, true);
    strict_1.default.equal(transition.nextAttemptAt, null);
});
(0, node_test_1.default)('a failure nobody should retry is terminal on the first attempt', () => {
    const transition = (0, affiliate_outbox_js_1.planOutboxTransition)({
        attemptsBeforeClaim: 0,
        outcome: { status: 'failed', retryable: false, error: 'unknown_template' },
        now: NOW,
    });
    strict_1.default.equal(transition.status, 'FAILED');
    strict_1.default.equal(transition.terminal, true);
});
(0, node_test_1.default)('no provider costs no attempt and claims nothing', () => {
    // The state the product is actually in today. Burning retries here would
    // exhaust every message's budget before a provider ever existed.
    const transition = (0, affiliate_outbox_js_1.planOutboxTransition)({
        attemptsBeforeClaim: 2,
        outcome: { status: 'not_configured' },
        now: NOW,
    });
    strict_1.default.equal(transition.status, 'NOT_CONFIGURED');
    strict_1.default.equal(transition.attempts, 2, 'an attempt was burned on a provider that does not exist');
    strict_1.default.equal(transition.terminal, false);
    strict_1.default.equal(transition.nextAttemptAt, NOW + affiliate_outbox_js_1.NOT_CONFIGURED_RECHECK_MS);
    strict_1.default.equal(transition.lastError, null);
});
(0, node_test_1.default)('a skip is a decision, not an attempt, and is never retried', () => {
    const transition = (0, affiliate_outbox_js_1.planOutboxTransition)({
        attemptsBeforeClaim: 0,
        outcome: { status: 'skipped', reason: 'consent_missing' },
        now: NOW,
    });
    strict_1.default.equal(transition.status, 'SKIPPED');
    strict_1.default.equal(transition.terminal, true);
    strict_1.default.equal(transition.attempts, 0);
    strict_1.default.equal(transition.nextAttemptAt, null);
    strict_1.default.equal(transition.lastError, 'consent_missing');
});
(0, node_test_1.default)('the two names for the attempt counter can never disagree', () => {
    const patch = (0, affiliate_outbox_js_1.transitionPatch)((0, affiliate_outbox_js_1.planOutboxTransition)({
        attemptsBeforeClaim: 1,
        outcome: { status: 'failed', retryable: true, error: 'boom' },
        now: NOW,
    }), { status: 'failed', retryable: true, error: 'boom' }, NOW);
    strict_1.default.equal(patch.attempts, 2);
    strict_1.default.equal(patch.retry_count, 2);
    strict_1.default.equal(patch.claim_id, null, 'a resolved message still holds its claim');
});
(0, node_test_1.default)('a provider error is stored short enough to read', () => {
    const long = `${'x'.repeat(5000)}`;
    strict_1.default.equal((0, affiliate_outbox_js_1.truncateError)(long).length, affiliate_outbox_js_1.MAX_LAST_ERROR_LENGTH);
    strict_1.default.equal((0, affiliate_outbox_js_1.truncateError)('  line one\n  line two  '), 'line one line two');
});
/* ============================================================== the claim */
(0, node_test_1.default)('claiming moves the message out of the queue and stamps who has it', async () => {
    const store = new FakeOutboxStore();
    store.put(MERCHANT, OUTBOX_ID, queuedRow());
    const claim = await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-1',
        now: NOW,
    });
    strict_1.default.equal(claim.status, 'claimed');
    const stored = store.read();
    strict_1.default.equal(stored.status, 'PROCESSING');
    strict_1.default.equal(stored.claim_id, 'worker-1');
    strict_1.default.equal(stored.attempts, 1);
    strict_1.default.equal(stored.next_attempt_at, NOW + affiliate_outbox_js_1.OUTBOX_LEASE_MS);
});
(0, node_test_1.default)('a second worker cannot take a message somebody already holds', async () => {
    const store = new FakeOutboxStore();
    store.put(MERCHANT, OUTBOX_ID, queuedRow());
    await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-1',
        now: NOW,
    });
    const second = await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-2',
        now: NOW + 1000,
    });
    strict_1.default.equal(second.status, 'held');
    strict_1.default.equal(store.read().claim_id, 'worker-1');
});
(0, node_test_1.default)('two workers reading at the same moment still produce one claim', async () => {
    // The interleave lands after the first transaction reads and before it
    // commits, which is the only ordering that can produce a double send.
    const store = new FakeOutboxStore();
    store.put(MERCHANT, OUTBOX_ID, queuedRow());
    const outcomes = [];
    store.interleave = async () => {
        const other = await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
            merchantId: MERCHANT,
            outboxId: OUTBOX_ID,
            claimId: 'worker-2',
            now: NOW,
        });
        outcomes.push(other.status);
    };
    const first = await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-1',
        now: NOW,
    });
    outcomes.push(first.status);
    strict_1.default.deepEqual(outcomes.sort(), ['claimed', 'held']);
    strict_1.default.equal(store.read().claim_id, 'worker-2', 'the winner was overwritten');
});
(0, node_test_1.default)('a message already sent is never claimed again', async () => {
    const store = new FakeOutboxStore();
    store.put(MERCHANT, OUTBOX_ID, queuedRow({ status: 'SENT', next_attempt_at: null }));
    const claim = await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-1',
        now: NOW + 10000000,
    });
    strict_1.default.equal(claim.status, 'held');
});
(0, node_test_1.default)('a claim that lapsed is taken again; a live one is not', () => {
    const claimed = record({
        status: 'PROCESSING',
        claimedAt: NOW,
        nextAttemptAt: NOW + affiliate_outbox_js_1.OUTBOX_LEASE_MS,
    });
    strict_1.default.equal((0, affiliate_outbox_js_1.isClaimable)(claimed, NOW + 1000), false);
    strict_1.default.equal((0, affiliate_outbox_js_1.isClaimable)(claimed, NOW + affiliate_outbox_js_1.OUTBOX_LEASE_MS + 1), true);
});
(0, node_test_1.default)('a message waiting on its backoff is left alone', () => {
    strict_1.default.equal((0, affiliate_outbox_js_1.isClaimable)(record({ nextAttemptAt: NOW + 60000 }), NOW), false);
    strict_1.default.equal((0, affiliate_outbox_js_1.isClaimable)(record({ nextAttemptAt: NOW }), NOW), true);
});
(0, node_test_1.default)('claiming a message that is not there says so instead of throwing', async () => {
    const store = new FakeOutboxStore();
    const claim = await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: 'missing',
        claimId: 'worker-1',
        now: NOW,
    });
    strict_1.default.deepEqual(claim, { status: 'missing' });
});
(0, node_test_1.default)('a worker whose claim expired cannot overwrite the one that replaced it', async () => {
    const store = new FakeOutboxStore();
    store.put(MERCHANT, OUTBOX_ID, queuedRow());
    await (0, affiliate_outbox_js_1.claimOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-2',
        now: NOW,
    });
    const released = await (0, affiliate_outbox_js_1.releaseOutboxMessage)(store, {
        merchantId: MERCHANT,
        outboxId: OUTBOX_ID,
        claimId: 'worker-1',
        patch: { status: 'SENT' },
    });
    strict_1.default.equal(released, 'lost');
    strict_1.default.equal(store.read().status, 'PROCESSING');
});
(0, node_test_1.default)('claimPatch counts the attempt before the send, not after', () => {
    // A worker that dies mid-delivery has still used an attempt; the alternative
    // retries a send that may have reached the provider, forever.
    const patch = (0, affiliate_outbox_js_1.claimPatch)(record({ attempts: 1 }), 'worker-1', NOW);
    strict_1.default.equal(patch.attempts, 2);
    strict_1.default.equal(patch.retry_count, 2);
});
/* =========================================================== the composing */
(0, node_test_1.default)('the customer is thanked with the points the sale earned', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record({ template: 'customer_referral_thanks', payload: { points: 30 } }), context({ points: 30 }));
    strict_1.default.equal(composed.ok, true);
    if (!composed.ok)
        return;
    strict_1.default.match(composed.message.body, /30 pontos/);
    strict_1.default.ok(!/\{\w+\}/.test(composed.message.body));
});
(0, node_test_1.default)('a pending reward is announced as pending, however it was queued', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record(), context({ rewardStatus: 'PENDING' }));
    strict_1.default.equal(composed.ok, true);
    if (!composed.ok)
        return;
    strict_1.default.match(composed.message.body, /a aguardar aprovação/);
    strict_1.default.doesNotMatch(composed.message.body, /aprovados/);
});
(0, node_test_1.default)('a reward approved before the message went out reads as approved', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record(), context({ rewardStatus: 'APPROVED' }));
    strict_1.default.equal(composed.ok, true);
    if (!composed.ok)
        return;
    strict_1.default.match(composed.message.body, /150 pontos de recompensa aprovados/);
});
(0, node_test_1.default)('the message body and the number come from the server, never the row', () => {
    // A till that could put a body or a number in the payload could send
    // arbitrary WhatsApp in the business's name, to anyone.
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record({
        payload: {
            body: 'transfira 5000 MT para 84 999 9999',
            to_phone: '+258849999999',
            reward_points: 150,
        },
    }), context());
    strict_1.default.equal(composed.ok, true);
    if (!composed.ok)
        return;
    strict_1.default.doesNotMatch(composed.message.body, /transfira/);
    strict_1.default.equal(composed.message.toPhoneE164, '+258841234567');
});
(0, node_test_1.default)('the message carries the row id, so a provider can dedupe on it', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record(), context());
    strict_1.default.equal(composed.ok, true);
    if (!composed.ok)
        return;
    strict_1.default.equal(composed.message.idempotencyKey, OUTBOX_ID);
});
(0, node_test_1.default)('a merchant with notifications off is not messaged', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record(), context({ notificationsEnabled: false }));
    strict_1.default.deepEqual(composed, {
        ok: false,
        outcome: { status: 'skipped', reason: 'notifications_disabled' },
    });
});
(0, node_test_1.default)('a customer who never consented is not messaged', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record({ template: 'customer_referral_thanks' }), context({ blockedReason: 'consent_missing', recipientPhoneE164: '+258841234567' }));
    strict_1.default.deepEqual(composed, {
        ok: false,
        outcome: { status: 'skipped', reason: 'consent_missing' },
    });
});
(0, node_test_1.default)('a recipient with no number is skipped rather than retried', () => {
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(record(), context({ recipientPhoneE164: null }));
    strict_1.default.deepEqual(composed, {
        ok: false,
        outcome: { status: 'skipped', reason: 'no_phone' },
    });
});
(0, node_test_1.default)('a template this build cannot render fails instead of guessing', () => {
    const parsed = (0, affiliate_outbox_js_1.parseOutboxRecord)(MERCHANT, OUTBOX_ID, queuedRow({ template: 'made_up' }));
    strict_1.default.equal(parsed.template, null);
    const composed = (0, affiliate_outbox_js_1.composeOutboxMessage)(parsed, context());
    strict_1.default.deepEqual(composed, {
        ok: false,
        outcome: { status: 'failed', retryable: false, error: 'unknown_template' },
    });
});
/* =========================================================== the processor */
(0, node_test_1.default)('a queued message is delivered once and recorded as sent', async () => {
    const { deps, store, sent } = harness();
    const result = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(result.result, 'sent');
    strict_1.default.equal(sent.length, 1);
    const stored = store.read();
    strict_1.default.equal(stored.status, 'SENT');
    strict_1.default.equal(stored.provider_message_id, 'wamid.1');
    strict_1.default.equal(stored.claim_id, null);
    strict_1.default.equal(stored.next_attempt_at, null);
});
(0, node_test_1.default)('the same trigger firing twice sends one message', async () => {
    // Firestore triggers are at-least-once. Two congratulations for one sale is
    // worse than a late one.
    const { deps, sent } = harness();
    const first = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    const second = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(first.result, 'sent');
    strict_1.default.equal(second.result, 'held');
    strict_1.default.equal(sent.length, 1);
});
(0, node_test_1.default)('a provider that fails is retried later, not dropped and not doubled', async () => {
    const { deps, store, clock } = harness({
        adapter: {
            async send() {
                throw new Error('502 Bad Gateway');
            },
        },
    });
    const first = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(first.result, 'retry');
    const stored = store.read();
    strict_1.default.equal(stored.status, 'QUEUED');
    strict_1.default.equal(stored.attempts, 1);
    strict_1.default.match(String(stored.last_error), /502/);
    strict_1.default.ok(Number(stored.next_attempt_at) > NOW);
    // Before the backoff elapses the message is not touched again.
    clock.now = NOW + 1000;
    strict_1.default.equal((await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID)).result, 'held');
    clock.now = Number(stored.next_attempt_at);
    strict_1.default.equal((await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID)).result, 'retry');
    strict_1.default.equal(store.read().attempts, 2);
});
(0, node_test_1.default)('a message that has failed enough times is parked for a person', async () => {
    const { deps, store, clock } = harness({
        row: queuedRow({ attempts: affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS - 1, retry_count: affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS - 1 }),
        adapter: {
            async send() {
                throw new Error('still broken');
            },
        },
    });
    const result = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(result.result, 'failed');
    strict_1.default.equal(store.read().status, 'FAILED');
    clock.now = NOW + 10 * 3600000;
    strict_1.default.equal((await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID)).result, 'held', 'a parked message was picked up again');
});
(0, node_test_1.default)('with no provider the message waits, unsent and unspent', async () => {
    const { deps, store, clock } = harness({ adapter: null });
    const result = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(result.result, 'not_configured');
    const stored = store.read();
    strict_1.default.equal(stored.status, 'NOT_CONFIGURED');
    strict_1.default.equal(stored.attempts, 0, 'an attempt was spent on a provider that does not exist');
    strict_1.default.equal(stored.last_error, null);
    strict_1.default.equal(stored.sent_at, undefined, 'nothing may claim to have been sent');
    // And the backlog sends itself once a provider appears.
    clock.now = NOW + affiliate_outbox_js_1.NOT_CONFIGURED_RECHECK_MS;
    const configured = harness({ row: store.read() });
    configured.clock.now = clock.now;
    strict_1.default.equal((await (0, affiliate_outbox_js_1.processOutboxMessage)(configured.deps, MERCHANT, OUTBOX_ID)).result, 'sent');
});
(0, node_test_1.default)('a merchant who switched notifications off is never reached', async () => {
    const { deps, store, sent } = harness({ context: { notificationsEnabled: false } });
    const result = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(result.result, 'skipped');
    strict_1.default.equal(sent.length, 0);
    strict_1.default.equal(store.read().skip_reason, 'notifications_disabled');
});
(0, node_test_1.default)('a customer with no consent and an affiliate with no number both stop here', async () => {
    const noConsent = harness({ context: { blockedReason: 'consent_missing' } });
    strict_1.default.equal((await (0, affiliate_outbox_js_1.processOutboxMessage)(noConsent.deps, MERCHANT, OUTBOX_ID)).result, 'skipped');
    strict_1.default.equal(noConsent.store.read().skip_reason, 'consent_missing');
    strict_1.default.equal(noConsent.sent.length, 0);
    const noPhone = harness({ context: { recipientPhoneE164: null } });
    strict_1.default.equal((await (0, affiliate_outbox_js_1.processOutboxMessage)(noPhone.deps, MERCHANT, OUTBOX_ID)).result, 'skipped');
    strict_1.default.equal(noPhone.store.read().skip_reason, 'no_phone');
});
(0, node_test_1.default)('a row naming an unknown template fails without reaching a provider', async () => {
    const { deps, store, sent } = harness({ row: queuedRow({ template: 'made_up' }) });
    const result = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(result.result, 'failed');
    strict_1.default.equal(sent.length, 0);
    strict_1.default.equal(store.read().last_error, 'unknown_template');
});
(0, node_test_1.default)('a context that cannot be read is a retry, not a lost message', async () => {
    const { deps, store } = harness({
        resolveContext: async () => {
            throw new Error('firestore unavailable');
        },
    });
    const result = await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(result.result, 'retry');
    strict_1.default.equal(store.read().status, 'QUEUED');
    strict_1.default.match(String(store.read().last_error), /unavailable/);
});
(0, node_test_1.default)('a message that is not there is reported, not thrown', async () => {
    const { deps } = harness();
    strict_1.default.deepEqual(await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, 'nope'), { result: 'missing' });
});
/* --------------------------------------------------------------- the logs */
(0, node_test_1.default)('a log line identifies the recipient without carrying them', async () => {
    const { deps, logs } = harness();
    await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    const serialized = JSON.stringify(logs);
    strict_1.default.match(serialized, /\*\*\*4567/);
    strict_1.default.doesNotMatch(serialized, /258841234567/, 'a full phone number reached a log');
    strict_1.default.doesNotMatch(serialized, /pontos/, 'a message body reached a log');
});
(0, node_test_1.default)('a delivery failure is logged as an error with the reason', async () => {
    const { deps, logs } = harness({
        adapter: {
            async send() {
                throw new Error('502 Bad Gateway');
            },
        },
    });
    await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    const failure = logs.find((line) => line.level === 'error');
    strict_1.default.ok(failure, 'a provider failure was not logged as an error');
    strict_1.default.equal(failure.entry.event, 'affiliate_outbox_delivery_failed');
    strict_1.default.match(String(failure.entry.error), /502/);
});
/* -------------------------------------------------------------- the sweep */
(0, node_test_1.default)('a sweep processes the due backlog and stops at the bound', async () => {
    const { deps, store, sent } = harness();
    for (let index = 2; index <= 6; index++) {
        store.put(MERCHANT, `ao_${index}`, queuedRow({ id: `ao_${index}`, next_attempt_at: NOW - index }));
    }
    const summary = await (0, affiliate_outbox_js_1.processAffiliateOutbox)(deps, { merchantId: MERCHANT, limit: 3 });
    strict_1.default.equal(summary.scanned, 3);
    strict_1.default.equal(summary.sent, 3);
    strict_1.default.equal(sent.length, 3);
});
(0, node_test_1.default)('a sweep never runs longer than the cap, whatever it is asked for', async () => {
    const { deps, store } = harness();
    for (let index = 2; index <= 120; index++) {
        store.put(MERCHANT, `ao_${index}`, queuedRow({ id: `ao_${index}` }));
    }
    const summary = await (0, affiliate_outbox_js_1.processAffiliateOutbox)(deps, {
        merchantId: MERCHANT,
        limit: 10000,
    });
    strict_1.default.equal(summary.scanned, affiliate_outbox_js_1.OUTBOX_MAX_BATCH);
});
(0, node_test_1.default)('a sweep skips what is not due and counts what it could not send', async () => {
    const { deps, store } = harness({ adapter: null });
    store.put(MERCHANT, 'ao_later', queuedRow({ id: 'ao_later', next_attempt_at: NOW + 60000 }));
    store.put(MERCHANT, 'ao_done', queuedRow({ id: 'ao_done', status: 'SENT' }));
    const summary = await (0, affiliate_outbox_js_1.processAffiliateOutbox)(deps, { merchantId: MERCHANT });
    strict_1.default.equal(summary.scanned, 1);
    strict_1.default.equal(summary.not_configured, 1);
    strict_1.default.equal(summary.sent, 0);
});
/* ------------------------------------------------- and never near the sale */
(0, node_test_1.default)('a sale is untouched by anything the delivery does', async () => {
    // The row is written inside the sale transaction; everything below happens
    // afterwards, against the outbox document alone.
    const { deps, store } = harness({
        adapter: {
            async send() {
                throw new Error('provider down');
            },
        },
    });
    store.put(MERCHANT, 'sale_marker', { id: 'sale_1', amount: 500, confirmed: true });
    const before = JSON.stringify(store.read(MERCHANT, 'sale_marker'));
    await (0, affiliate_outbox_js_1.processOutboxMessage)(deps, MERCHANT, OUTBOX_ID);
    strict_1.default.equal(JSON.stringify(store.read(MERCHANT, 'sale_marker')), before);
    strict_1.default.equal(store.read().status, 'QUEUED', 'the message was lost with the failure');
});
(0, node_test_1.default)('the sale commit knows nothing about delivery', () => {
    // Read from the source because the property is structural: an import of the
    // worker or an adapter into the commit is how a provider timeout would
    // eventually end up inside a sale transaction.
    const source = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_sale_commit.ts'), 'utf8');
    strict_1.default.doesNotMatch(source, /from '\.\/affiliate_outbox/);
    strict_1.default.doesNotMatch(source, /deliverAffiliateMessage|WhatsAppAdapter|processOutboxMessage/);
});
/** The body of one Firestore trigger declared in index.ts. */
function triggerSource(name) {
    const source = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
    const start = source.indexOf(`export const ${name} = `);
    strict_1.default.ok(start > 0, `${name} is not declared in index.ts`);
    const next = source.indexOf('\nexport const ', start + 1);
    return source.slice(start, next === -1 ? source.length : next);
}
(0, node_test_1.default)('the outbox trigger fires on creation, so it cannot trigger itself', () => {
    // The worker writes the outcome back to the same document. On a write
    // trigger that is an infinite loop that also sends repeatedly.
    const trigger = triggerSource('affiliateOutboxOnCreate');
    strict_1.default.match(trigger, /onDocumentCreated\(/);
    strict_1.default.doesNotMatch(trigger, /onDocumentWritten\(/);
    strict_1.default.match(trigger, /affiliate_outbox\/\{outboxId\}/);
});
(0, node_test_1.default)('a failing delivery never fails the function that started it', () => {
    // A thrown error is a retriggered function, and a retriggered function on a
    // message that was already delivered is a second message.
    const trigger = triggerSource('affiliateOutboxOnCreate');
    strict_1.default.match(trigger, /try \{[\s\S]*processOutboxMessage\([\s\S]*\} catch/);
    strict_1.default.match(trigger, /console\.error\('affiliate_outbox_trigger_failed'/);
});
(0, node_test_1.default)('the retention dispatch runs after the commit and cannot fail the sale', () => {
    const trigger = triggerSource('affiliateRetentionEventOnCreate');
    // Events are written inside the sale transaction; a create trigger is by
    // definition the other side of the commit.
    strict_1.default.match(trigger, /onDocumentCreated\(/);
    strict_1.default.match(trigger, /affiliate_events\/\{eventId\}/);
    strict_1.default.match(trigger, /try \{[\s\S]*dispatchAffiliateRetentionEvent\([\s\S]*\} catch/);
    strict_1.default.doesNotMatch(trigger, /processOutboxMessage|processAffiliateOutbox/, 'a second sender for the same fact is how a referral gets messaged twice');
});
(0, node_test_1.default)('a scheduled sweep retries rows after the create trigger', () => {
    const sweep = triggerSource('affiliateOutboxRetrySweep');
    strict_1.default.match(sweep, /onSchedule\(/);
    strict_1.default.match(sweep, /every 5 minutes/);
    strict_1.default.match(sweep, /processAffiliateOutbox\(/);
    strict_1.default.match(sweep, /merchantId: null/);
});
/* ------------------------------------------------------- the provider gap */
(0, node_test_1.default)('no provider is configured, and nothing pretends otherwise', async () => {
    // The honest state of the product: delivery refuses rather than reporting a
    // success nobody can verify. The hook is what a real provider plugs into.
    const { resolveWhatsAppAdapter, setWhatsAppAdapter } = await import('./affiliate_outbox_firestore.js');
    strict_1.default.equal(resolveWhatsAppAdapter(), null);
    const fake = { async send() { return { providerMessageId: 'x' }; } };
    setWhatsAppAdapter(fake);
    strict_1.default.equal(resolveWhatsAppAdapter(), fake);
    setWhatsAppAdapter(null);
    strict_1.default.equal(resolveWhatsAppAdapter(), null);
});
(0, node_test_1.default)('the recipient is read from the merchant records, never from the row', () => {
    const source = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_outbox_firestore.ts'), 'utf8');
    // Consent and the merchant's own setting are both checked before a number
    // is read at all.
    strict_1.default.match(source, /whatsapp_consent_status/);
    strict_1.default.match(source, /affiliateConfigFrom\(/);
    strict_1.default.match(source, /notificationsEnabled/);
    strict_1.default.match(source, /affiliate_merchants/);
    strict_1.default.match(source, /affiliateIds\.link/);
    strict_1.default.match(source, /linkStatus !== 'ACTIVE'/);
    // The only things taken from the queued payload are ids and the point
    // count; a phone or a body from there would be client-controlled.
    strict_1.default.doesNotMatch(source, /payload, 'phone|payload\.phone|payload, 'body'|payload\.body/);
});
