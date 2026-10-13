import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  MAX_DELIVERY_ATTEMPTS,
  nextAttemptDelayMs,
  type DeliveryOutcome,
  type OutboxMessage,
  type WhatsAppAdapter,
} from './affiliate_notifications.js';
import {
  CLAIMABLE_STATUSES,
  claimOutboxMessage,
  claimPatch,
  composeOutboxMessage,
  isClaimable,
  MAX_LAST_ERROR_LENGTH,
  NOT_CONFIGURED_RECHECK_MS,
  OUTBOX_LEASE_MS,
  OUTBOX_MAX_BATCH,
  parseOutboxRecord,
  planOutboxTransition,
  processAffiliateOutbox,
  processOutboxMessage,
  releaseOutboxMessage,
  transitionPatch,
  truncateError,
  type DocumentData,
  type OutboxContext,
  type OutboxDeps,
  type OutboxLogEntry,
  type OutboxRecord,
  type OutboxStore,
  type OutboxTransaction,
  type StoredOutboxDocument,
} from './affiliate_outbox.js';

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
const NOW = 1_800_000_000_000;

/* ------------------------------------------------------------- the fake db */

class FakeOutboxStore implements OutboxStore {
  docs = new Map<string, { data: DocumentData; version: number }>();
  transactions = 0;
  /** Runs once, after the next transaction reads and before it commits. */
  interleave: (() => Promise<void> | void) | null = null;

  key(merchantId: string, outboxId: string): string {
    return `${merchantId}/${outboxId}`;
  }

  put(merchantId: string, outboxId: string, data: DocumentData): void {
    this.docs.set(this.key(merchantId, outboxId), { data, version: 1 });
  }

  read(merchantId = MERCHANT, outboxId = OUTBOX_ID): DocumentData {
    const entry = this.docs.get(this.key(merchantId, outboxId));
    assert.ok(entry, `no document at ${merchantId}/${outboxId}`);
    return entry.data;
  }

  async runTransaction<T>(
    run: (transaction: OutboxTransaction) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 0; attempt < 5; attempt++) {
      this.transactions += 1;
      const readVersions = new Map<string, number>();
      const staged = new Map<string, DocumentData>();

      const transaction: OutboxTransaction = {
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
      if (hook) await hook();

      const stale = [...readVersions].some(
        ([key, version]) => (this.docs.get(key)?.version ?? 0) !== version,
      );
      // Exactly what Firestore does: somebody wrote what we read, so the whole
      // transaction runs again against the new value.
      if (stale) continue;

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

  async listPending(input: {
    merchantId: string | null;
    limit: number;
    now: number;
  }): Promise<StoredOutboxDocument[]> {
    const rows: StoredOutboxDocument[] = [];
    for (const [key, entry] of this.docs) {
      const [merchantId, id] = key.split('/');
      if (input.merchantId !== null && merchantId !== input.merchantId) continue;
      const status = String(entry.data.status ?? 'QUEUED');
      if (!(CLAIMABLE_STATUSES as readonly string[]).includes(status)) continue;
      if (Number(entry.data.next_attempt_at ?? 0) > input.now) continue;
      rows.push({ merchantId, id, data: { ...entry.data } });
    }
    rows.sort(
      (left, right) =>
        Number(left.data.next_attempt_at ?? 0) - Number(right.data.next_attempt_at ?? 0),
    );
    return rows.slice(0, input.limit);
  }
}

/* -------------------------------------------------------------- fixtures */

function queuedRow(overrides: DocumentData = {}): DocumentData {
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

function record(overrides: Partial<OutboxRecord> = {}): OutboxRecord {
  return {
    ...parseOutboxRecord(MERCHANT, OUTBOX_ID, queuedRow()),
    ...overrides,
  };
}

function context(overrides: Partial<OutboxContext> = {}): OutboxContext {
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

type Harness = {
  store: FakeOutboxStore;
  deps: OutboxDeps;
  sent: OutboxMessage[];
  logs: Array<{ level: string; entry: OutboxLogEntry }>;
  clock: { now: number };
};

function harness(
  options: {
    adapter?: WhatsAppAdapter | null;
    context?: Partial<OutboxContext>;
    resolveContext?: (record: OutboxRecord) => Promise<OutboxContext>;
    row?: DocumentData;
  } = {},
): Harness {
  const store = new FakeOutboxStore();
  store.put(MERCHANT, OUTBOX_ID, options.row ?? queuedRow());

  const sent: OutboxMessage[] = [];
  const logs: Array<{ level: string; entry: OutboxLogEntry }> = [];
  const clock = { now: NOW };

  const adapter =
    options.adapter === undefined
      ? {
          async send(message: OutboxMessage) {
            sent.push(message);
            return { providerMessageId: `wamid.${sent.length}` };
          },
        }
      : options.adapter;

  const deps: OutboxDeps = {
    store,
    adapter,
    resolveContext:
      options.resolveContext ?? (async () => context(options.context ?? {})),
    now: () => clock.now,
    log: (level, entry) => logs.push({ level, entry }),
  };

  return { store, deps, sent, logs, clock };
}

/* ====================================================== the state machine */

test('a sent message is finished and asks for nothing else', () => {
  const transition = planOutboxTransition({
    attemptsBeforeClaim: 0,
    outcome: { status: 'sent', providerMessageId: 'wamid.1' },
    now: NOW,
  });

  assert.equal(transition.status, 'SENT');
  assert.equal(transition.terminal, true);
  assert.equal(transition.attempts, 1);
  assert.equal(transition.nextAttemptAt, null);
  assert.equal(transition.lastError, null);
});

test('a retryable failure goes back to the queue, later each time', () => {
  const failure: DeliveryOutcome = { status: 'failed', retryable: true, error: 'boom' };

  const first = planOutboxTransition({ attemptsBeforeClaim: 0, outcome: failure, now: NOW });
  const second = planOutboxTransition({ attemptsBeforeClaim: 1, outcome: failure, now: NOW });

  assert.equal(first.status, 'QUEUED');
  assert.equal(first.terminal, false);
  assert.equal(first.nextAttemptAt, NOW + nextAttemptDelayMs(1));
  assert.ok((second.nextAttemptAt ?? 0) > (first.nextAttemptAt ?? 0));
  assert.equal(second.attempts, 2);
});

test('failures stop at the cap instead of retrying forever', () => {
  const transition = planOutboxTransition({
    attemptsBeforeClaim: MAX_DELIVERY_ATTEMPTS - 1,
    outcome: { status: 'failed', retryable: true, error: 'boom' },
    now: NOW,
  });

  assert.equal(transition.attempts, MAX_DELIVERY_ATTEMPTS);
  assert.equal(transition.status, 'FAILED');
  assert.equal(transition.terminal, true);
  assert.equal(transition.nextAttemptAt, null);
});

test('a failure nobody should retry is terminal on the first attempt', () => {
  const transition = planOutboxTransition({
    attemptsBeforeClaim: 0,
    outcome: { status: 'failed', retryable: false, error: 'unknown_template' },
    now: NOW,
  });

  assert.equal(transition.status, 'FAILED');
  assert.equal(transition.terminal, true);
});

test('no provider costs no attempt and claims nothing', () => {
  // The state the product is actually in today. Burning retries here would
  // exhaust every message's budget before a provider ever existed.
  const transition = planOutboxTransition({
    attemptsBeforeClaim: 2,
    outcome: { status: 'not_configured' },
    now: NOW,
  });

  assert.equal(transition.status, 'NOT_CONFIGURED');
  assert.equal(transition.attempts, 2, 'an attempt was burned on a provider that does not exist');
  assert.equal(transition.terminal, false);
  assert.equal(transition.nextAttemptAt, NOW + NOT_CONFIGURED_RECHECK_MS);
  assert.equal(transition.lastError, null);
});

test('a skip is a decision, not an attempt, and is never retried', () => {
  const transition = planOutboxTransition({
    attemptsBeforeClaim: 0,
    outcome: { status: 'skipped', reason: 'consent_missing' },
    now: NOW,
  });

  assert.equal(transition.status, 'SKIPPED');
  assert.equal(transition.terminal, true);
  assert.equal(transition.attempts, 0);
  assert.equal(transition.nextAttemptAt, null);
  assert.equal(transition.lastError, 'consent_missing');
});

test('the two names for the attempt counter can never disagree', () => {
  const patch = transitionPatch(
    planOutboxTransition({
      attemptsBeforeClaim: 1,
      outcome: { status: 'failed', retryable: true, error: 'boom' },
      now: NOW,
    }),
    { status: 'failed', retryable: true, error: 'boom' },
    NOW,
  );

  assert.equal(patch.attempts, 2);
  assert.equal(patch.retry_count, 2);
  assert.equal(patch.claim_id, null, 'a resolved message still holds its claim');
});

test('a provider error is stored short enough to read', () => {
  const long = `${'x'.repeat(5_000)}`;
  assert.equal(truncateError(long).length, MAX_LAST_ERROR_LENGTH);
  assert.equal(truncateError('  line one\n  line two  '), 'line one line two');
});

/* ============================================================== the claim */

test('claiming moves the message out of the queue and stamps who has it', async () => {
  const store = new FakeOutboxStore();
  store.put(MERCHANT, OUTBOX_ID, queuedRow());

  const claim = await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-1',
    now: NOW,
  });

  assert.equal(claim.status, 'claimed');
  const stored = store.read();
  assert.equal(stored.status, 'PROCESSING');
  assert.equal(stored.claim_id, 'worker-1');
  assert.equal(stored.attempts, 1);
  assert.equal(stored.next_attempt_at, NOW + OUTBOX_LEASE_MS);
});

test('a second worker cannot take a message somebody already holds', async () => {
  const store = new FakeOutboxStore();
  store.put(MERCHANT, OUTBOX_ID, queuedRow());

  await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-1',
    now: NOW,
  });
  const second = await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-2',
    now: NOW + 1_000,
  });

  assert.equal(second.status, 'held');
  assert.equal(store.read().claim_id, 'worker-1');
});

test('two workers reading at the same moment still produce one claim', async () => {
  // The interleave lands after the first transaction reads and before it
  // commits, which is the only ordering that can produce a double send.
  const store = new FakeOutboxStore();
  store.put(MERCHANT, OUTBOX_ID, queuedRow());

  const outcomes: string[] = [];
  store.interleave = async () => {
    const other = await claimOutboxMessage(store, {
      merchantId: MERCHANT,
      outboxId: OUTBOX_ID,
      claimId: 'worker-2',
      now: NOW,
    });
    outcomes.push(other.status);
  };

  const first = await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-1',
    now: NOW,
  });
  outcomes.push(first.status);

  assert.deepEqual(outcomes.sort(), ['claimed', 'held']);
  assert.equal(store.read().claim_id, 'worker-2', 'the winner was overwritten');
});

test('a message already sent is never claimed again', async () => {
  const store = new FakeOutboxStore();
  store.put(MERCHANT, OUTBOX_ID, queuedRow({ status: 'SENT', next_attempt_at: null }));

  const claim = await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-1',
    now: NOW + 10_000_000,
  });

  assert.equal(claim.status, 'held');
});

test('a claim that lapsed is taken again; a live one is not', () => {
  const claimed = record({
    status: 'PROCESSING',
    claimedAt: NOW,
    nextAttemptAt: NOW + OUTBOX_LEASE_MS,
  });

  assert.equal(isClaimable(claimed, NOW + 1_000), false);
  assert.equal(isClaimable(claimed, NOW + OUTBOX_LEASE_MS + 1), true);
});

test('a message waiting on its backoff is left alone', () => {
  assert.equal(isClaimable(record({ nextAttemptAt: NOW + 60_000 }), NOW), false);
  assert.equal(isClaimable(record({ nextAttemptAt: NOW }), NOW), true);
});

test('claiming a message that is not there says so instead of throwing', async () => {
  const store = new FakeOutboxStore();
  const claim = await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: 'missing',
    claimId: 'worker-1',
    now: NOW,
  });
  assert.deepEqual(claim, { status: 'missing' });
});

test('a worker whose claim expired cannot overwrite the one that replaced it', async () => {
  const store = new FakeOutboxStore();
  store.put(MERCHANT, OUTBOX_ID, queuedRow());
  await claimOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-2',
    now: NOW,
  });

  const released = await releaseOutboxMessage(store, {
    merchantId: MERCHANT,
    outboxId: OUTBOX_ID,
    claimId: 'worker-1',
    patch: { status: 'SENT' },
  });

  assert.equal(released, 'lost');
  assert.equal(store.read().status, 'PROCESSING');
});

test('claimPatch counts the attempt before the send, not after', () => {
  // A worker that dies mid-delivery has still used an attempt; the alternative
  // retries a send that may have reached the provider, forever.
  const patch = claimPatch(record({ attempts: 1 }), 'worker-1', NOW);
  assert.equal(patch.attempts, 2);
  assert.equal(patch.retry_count, 2);
});

/* =========================================================== the composing */

test('the customer is thanked with the points the sale earned', () => {
  const composed = composeOutboxMessage(
    record({ template: 'customer_referral_thanks', payload: { points: 30 } }),
    context({ points: 30 }),
  );

  assert.equal(composed.ok, true);
  if (!composed.ok) return;
  assert.match(composed.message.body, /30 pontos/);
  assert.ok(!/\{\w+\}/.test(composed.message.body));
});

test('a pending reward is announced as pending, however it was queued', () => {
  const composed = composeOutboxMessage(record(), context({ rewardStatus: 'PENDING' }));
  assert.equal(composed.ok, true);
  if (!composed.ok) return;
  assert.match(composed.message.body, /a aguardar aprovação/);
  assert.doesNotMatch(composed.message.body, /aprovados/);
});

test('a reward approved before the message went out reads as approved', () => {
  const composed = composeOutboxMessage(record(), context({ rewardStatus: 'APPROVED' }));
  assert.equal(composed.ok, true);
  if (!composed.ok) return;
  assert.match(composed.message.body, /150 pontos de recompensa aprovados/);
});

test('the message body and the number come from the server, never the row', () => {
  // A till that could put a body or a number in the payload could send
  // arbitrary WhatsApp in the business's name, to anyone.
  const composed = composeOutboxMessage(
    record({
      payload: {
        body: 'transfira 5000 MT para 84 999 9999',
        to_phone: '+258849999999',
        reward_points: 150,
      },
    }),
    context(),
  );

  assert.equal(composed.ok, true);
  if (!composed.ok) return;
  assert.doesNotMatch(composed.message.body, /transfira/);
  assert.equal(composed.message.toPhoneE164, '+258841234567');
});

test('the message carries the row id, so a provider can dedupe on it', () => {
  const composed = composeOutboxMessage(record(), context());
  assert.equal(composed.ok, true);
  if (!composed.ok) return;
  assert.equal(composed.message.idempotencyKey, OUTBOX_ID);
});

test('a merchant with notifications off is not messaged', () => {
  const composed = composeOutboxMessage(record(), context({ notificationsEnabled: false }));
  assert.deepEqual(composed, {
    ok: false,
    outcome: { status: 'skipped', reason: 'notifications_disabled' },
  });
});

test('a customer who never consented is not messaged', () => {
  const composed = composeOutboxMessage(
    record({ template: 'customer_referral_thanks' }),
    context({ blockedReason: 'consent_missing', recipientPhoneE164: '+258841234567' }),
  );
  assert.deepEqual(composed, {
    ok: false,
    outcome: { status: 'skipped', reason: 'consent_missing' },
  });
});

test('a recipient with no number is skipped rather than retried', () => {
  const composed = composeOutboxMessage(record(), context({ recipientPhoneE164: null }));
  assert.deepEqual(composed, {
    ok: false,
    outcome: { status: 'skipped', reason: 'no_phone' },
  });
});

test('a template this build cannot render fails instead of guessing', () => {
  const parsed = parseOutboxRecord(MERCHANT, OUTBOX_ID, queuedRow({ template: 'made_up' }));
  assert.equal(parsed.template, null);

  const composed = composeOutboxMessage(parsed, context());
  assert.deepEqual(composed, {
    ok: false,
    outcome: { status: 'failed', retryable: false, error: 'unknown_template' },
  });
});

/* =========================================================== the processor */

test('a queued message is delivered once and recorded as sent', async () => {
  const { deps, store, sent } = harness();

  const result = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(result.result, 'sent');
  assert.equal(sent.length, 1);
  const stored = store.read();
  assert.equal(stored.status, 'SENT');
  assert.equal(stored.provider_message_id, 'wamid.1');
  assert.equal(stored.claim_id, null);
  assert.equal(stored.next_attempt_at, null);
});

test('the same trigger firing twice sends one message', async () => {
  // Firestore triggers are at-least-once. Two congratulations for one sale is
  // worse than a late one.
  const { deps, sent } = harness();

  const first = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);
  const second = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(first.result, 'sent');
  assert.equal(second.result, 'held');
  assert.equal(sent.length, 1);
});

test('a provider that fails is retried later, not dropped and not doubled', async () => {
  const { deps, store, clock } = harness({
    adapter: {
      async send() {
        throw new Error('502 Bad Gateway');
      },
    },
  });

  const first = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);
  assert.equal(first.result, 'retry');

  const stored = store.read();
  assert.equal(stored.status, 'QUEUED');
  assert.equal(stored.attempts, 1);
  assert.match(String(stored.last_error), /502/);
  assert.ok(Number(stored.next_attempt_at) > NOW);

  // Before the backoff elapses the message is not touched again.
  clock.now = NOW + 1_000;
  assert.equal((await processOutboxMessage(deps, MERCHANT, OUTBOX_ID)).result, 'held');

  clock.now = Number(stored.next_attempt_at);
  assert.equal((await processOutboxMessage(deps, MERCHANT, OUTBOX_ID)).result, 'retry');
  assert.equal(store.read().attempts, 2);
});

test('a message that has failed enough times is parked for a person', async () => {
  const { deps, store, clock } = harness({
    row: queuedRow({ attempts: MAX_DELIVERY_ATTEMPTS - 1, retry_count: MAX_DELIVERY_ATTEMPTS - 1 }),
    adapter: {
      async send() {
        throw new Error('still broken');
      },
    },
  });

  const result = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(result.result, 'failed');
  assert.equal(store.read().status, 'FAILED');

  clock.now = NOW + 10 * 3_600_000;
  assert.equal(
    (await processOutboxMessage(deps, MERCHANT, OUTBOX_ID)).result,
    'held',
    'a parked message was picked up again',
  );
});

test('with no provider the message waits, unsent and unspent', async () => {
  const { deps, store, clock } = harness({ adapter: null });

  const result = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(result.result, 'not_configured');
  const stored = store.read();
  assert.equal(stored.status, 'NOT_CONFIGURED');
  assert.equal(stored.attempts, 0, 'an attempt was spent on a provider that does not exist');
  assert.equal(stored.last_error, null);
  assert.equal(stored.sent_at, undefined, 'nothing may claim to have been sent');

  // And the backlog sends itself once a provider appears.
  clock.now = NOW + NOT_CONFIGURED_RECHECK_MS;
  const configured = harness({ row: store.read() });
  configured.clock.now = clock.now;
  assert.equal(
    (await processOutboxMessage(configured.deps, MERCHANT, OUTBOX_ID)).result,
    'sent',
  );
});

test('a merchant who switched notifications off is never reached', async () => {
  const { deps, store, sent } = harness({ context: { notificationsEnabled: false } });

  const result = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(result.result, 'skipped');
  assert.equal(sent.length, 0);
  assert.equal(store.read().skip_reason, 'notifications_disabled');
});

test('a customer with no consent and an affiliate with no number both stop here', async () => {
  const noConsent = harness({ context: { blockedReason: 'consent_missing' } });
  assert.equal(
    (await processOutboxMessage(noConsent.deps, MERCHANT, OUTBOX_ID)).result,
    'skipped',
  );
  assert.equal(noConsent.store.read().skip_reason, 'consent_missing');
  assert.equal(noConsent.sent.length, 0);

  const noPhone = harness({ context: { recipientPhoneE164: null } });
  assert.equal(
    (await processOutboxMessage(noPhone.deps, MERCHANT, OUTBOX_ID)).result,
    'skipped',
  );
  assert.equal(noPhone.store.read().skip_reason, 'no_phone');
});

test('a row naming an unknown template fails without reaching a provider', async () => {
  const { deps, store, sent } = harness({ row: queuedRow({ template: 'made_up' }) });

  const result = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(result.result, 'failed');
  assert.equal(sent.length, 0);
  assert.equal(store.read().last_error, 'unknown_template');
});

test('a context that cannot be read is a retry, not a lost message', async () => {
  const { deps, store } = harness({
    resolveContext: async () => {
      throw new Error('firestore unavailable');
    },
  });

  const result = await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(result.result, 'retry');
  assert.equal(store.read().status, 'QUEUED');
  assert.match(String(store.read().last_error), /unavailable/);
});

test('a message that is not there is reported, not thrown', async () => {
  const { deps } = harness();
  assert.deepEqual(await processOutboxMessage(deps, MERCHANT, 'nope'), { result: 'missing' });
});

/* --------------------------------------------------------------- the logs */

test('a log line identifies the recipient without carrying them', async () => {
  const { deps, logs } = harness();
  await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  const serialized = JSON.stringify(logs);
  assert.match(serialized, /\*\*\*4567/);
  assert.doesNotMatch(serialized, /258841234567/, 'a full phone number reached a log');
  assert.doesNotMatch(serialized, /pontos/, 'a message body reached a log');
});

test('a delivery failure is logged as an error with the reason', async () => {
  const { deps, logs } = harness({
    adapter: {
      async send() {
        throw new Error('502 Bad Gateway');
      },
    },
  });
  await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  const failure = logs.find((line) => line.level === 'error');
  assert.ok(failure, 'a provider failure was not logged as an error');
  assert.equal(failure.entry.event, 'affiliate_outbox_delivery_failed');
  assert.match(String(failure.entry.error), /502/);
});

/* -------------------------------------------------------------- the sweep */

test('a sweep processes the due backlog and stops at the bound', async () => {
  const { deps, store, sent } = harness();
  for (let index = 2; index <= 6; index++) {
    store.put(
      MERCHANT,
      `ao_${index}`,
      queuedRow({ id: `ao_${index}`, next_attempt_at: NOW - index }),
    );
  }

  const summary = await processAffiliateOutbox(deps, { merchantId: MERCHANT, limit: 3 });

  assert.equal(summary.scanned, 3);
  assert.equal(summary.sent, 3);
  assert.equal(sent.length, 3);
});

test('a sweep never runs longer than the cap, whatever it is asked for', async () => {
  const { deps, store } = harness();
  for (let index = 2; index <= 120; index++) {
    store.put(MERCHANT, `ao_${index}`, queuedRow({ id: `ao_${index}` }));
  }

  const summary = await processAffiliateOutbox(deps, {
    merchantId: MERCHANT,
    limit: 10_000,
  });

  assert.equal(summary.scanned, OUTBOX_MAX_BATCH);
});

test('a sweep skips what is not due and counts what it could not send', async () => {
  const { deps, store } = harness({ adapter: null });
  store.put(MERCHANT, 'ao_later', queuedRow({ id: 'ao_later', next_attempt_at: NOW + 60_000 }));
  store.put(MERCHANT, 'ao_done', queuedRow({ id: 'ao_done', status: 'SENT' }));

  const summary = await processAffiliateOutbox(deps, { merchantId: MERCHANT });

  assert.equal(summary.scanned, 1);
  assert.equal(summary.not_configured, 1);
  assert.equal(summary.sent, 0);
});

/* ------------------------------------------------- and never near the sale */

test('a sale is untouched by anything the delivery does', async () => {
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

  await processOutboxMessage(deps, MERCHANT, OUTBOX_ID);

  assert.equal(JSON.stringify(store.read(MERCHANT, 'sale_marker')), before);
  assert.equal(store.read().status, 'QUEUED', 'the message was lost with the failure');
});

test('the sale commit knows nothing about delivery', () => {
  // Read from the source because the property is structural: an import of the
  // worker or an adapter into the commit is how a provider timeout would
  // eventually end up inside a sale transaction.
  const source = readFileSync(
    path.join(__dirname, '..', 'src', 'affiliate_sale_commit.ts'),
    'utf8',
  );

  assert.doesNotMatch(source, /from '\.\/affiliate_outbox/);
  assert.doesNotMatch(source, /deliverAffiliateMessage|WhatsAppAdapter|processOutboxMessage/);
});

/** The body of one Firestore trigger declared in index.ts. */
function triggerSource(name: string): string {
  const source = readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
  const start = source.indexOf(`export const ${name} = `);
  assert.ok(start > 0, `${name} is not declared in index.ts`);
  const next = source.indexOf('\nexport const ', start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

test('the outbox trigger fires on creation, so it cannot trigger itself', () => {
  // The worker writes the outcome back to the same document. On a write
  // trigger that is an infinite loop that also sends repeatedly.
  const trigger = triggerSource('affiliateOutboxOnCreate');
  assert.match(trigger, /onDocumentCreated\(/);
  assert.doesNotMatch(trigger, /onDocumentWritten\(/);
  assert.match(trigger, /affiliate_outbox\/\{outboxId\}/);
});

test('a failing delivery never fails the function that started it', () => {
  // A thrown error is a retriggered function, and a retriggered function on a
  // message that was already delivered is a second message.
  const trigger = triggerSource('affiliateOutboxOnCreate');
  assert.match(trigger, /try \{[\s\S]*processOutboxMessage\([\s\S]*\} catch/);
  assert.match(trigger, /console\.error\('affiliate_outbox_trigger_failed'/);
});

test('the retention dispatch runs after the commit and cannot fail the sale', () => {
  const trigger = triggerSource('affiliateRetentionEventOnCreate');
  // Events are written inside the sale transaction; a create trigger is by
  // definition the other side of the commit.
  assert.match(trigger, /onDocumentCreated\(/);
  assert.match(trigger, /affiliate_events\/\{eventId\}/);
  assert.match(trigger, /try \{[\s\S]*dispatchAffiliateRetentionEvent\([\s\S]*\} catch/);
  assert.doesNotMatch(
    trigger,
    /processOutboxMessage|processAffiliateOutbox/,
    'a second sender for the same fact is how a referral gets messaged twice',
  );
});

test('a scheduled sweep retries rows after the create trigger', () => {
  const sweep = triggerSource('affiliateOutboxRetrySweep');
  assert.match(sweep, /onSchedule\(/);
  assert.match(sweep, /every 5 minutes/);
  assert.match(sweep, /processAffiliateOutbox\(/);
  assert.match(sweep, /merchantId: null/);
});

/* ------------------------------------------------------- the provider gap */

test('no provider is configured, and nothing pretends otherwise', async () => {
  // The honest state of the product: delivery refuses rather than reporting a
  // success nobody can verify. The hook is what a real provider plugs into.
  const { resolveWhatsAppAdapter, setWhatsAppAdapter } = await import(
    './affiliate_outbox_firestore.js'
  );

  assert.equal(resolveWhatsAppAdapter(), null);

  const fake: WhatsAppAdapter = { async send() { return { providerMessageId: 'x' }; } };
  setWhatsAppAdapter(fake);
  assert.equal(resolveWhatsAppAdapter(), fake);
  setWhatsAppAdapter(null);
  assert.equal(resolveWhatsAppAdapter(), null);
});

test('the recipient is read from the merchant records, never from the row', () => {
  const source = readFileSync(
    path.join(__dirname, '..', 'src', 'affiliate_outbox_firestore.ts'),
    'utf8',
  );

  // Consent and the merchant's own setting are both checked before a number
  // is read at all.
  assert.match(source, /whatsapp_consent_status/);
  assert.match(source, /affiliateConfigFrom\(/);
  assert.match(source, /notificationsEnabled/);
  assert.match(source, /affiliate_merchants/);
  assert.match(source, /affiliateIds\.link/);
  assert.match(source, /linkStatus !== 'ACTIVE'/);
  // The only things taken from the queued payload are ids and the point
  // count; a phone or a body from there would be client-controlled.
  assert.doesNotMatch(source, /payload, 'phone|payload\.phone|payload, 'body'|payload\.body/);
});
