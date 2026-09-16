import { randomUUID } from 'crypto';

import type { RewardStatus } from './affiliate_contracts.js';
import {
  deliverAffiliateMessage,
  isAffiliateTemplate,
  isTerminalDelivery,
  maskPhone,
  nextAttemptDelayMs,
  renderAffiliateMessage,
  rewardStatusText,
  type AffiliateTemplate,
  type DeliveryOutcome,
  type DeliverySkipReason,
  type OutboxMessage,
  type WhatsAppAdapter,
} from './affiliate_notifications.js';

/**
 * The worker around `businesses/{merchantId}/affiliate_outbox`.
 *
 * The rows are written inside the sale transaction, because the message is
 * part of what the sale means; they are sent from here, afterwards, because a
 * message is not. Nothing in this file runs inside a sale transaction and
 * nothing it does can roll one back: the worst outage leaves a backlog of
 * queued rows and a sale that committed exactly as it should have.
 *
 * Three properties are the whole design:
 *
 *   A message is claimed before it is sent. The claim is a transaction that
 *   moves the row to PROCESSING and stamps a claim id; a second worker — a
 *   duplicate trigger, an overlapping sweep — reads the claimed row and stops.
 *   Without it, a retriggered Firestore event is a second WhatsApp message to
 *   the same person about the same sale, which is worse than none.
 *
 *   A claim expires. A worker that dies mid-delivery would otherwise park its
 *   message in PROCESSING forever, so the claim carries a lease and the row
 *   becomes claimable again once it lapses.
 *
 *   No outcome is guessed. `sent`, `skipped`, `failed` and `not_configured`
 *   are four different things and are stored as four different things: the one
 *   that matters most is `not_configured`, which is today's normal state and
 *   must not consume an attempt, raise an error rate or claim success.
 *
 * The decisions are pure functions over a record and an outcome, and the store
 * is a port. That is what lets the state machine, the claim race and the
 * replay all be tested without an emulator.
 */

export type DocumentData = Record<string, unknown>;

/* ------------------------------------------------------------------ states */

export const OUTBOX_STATUS = [
  'QUEUED',
  'PROCESSING',
  'SENT',
  'SKIPPED',
  'FAILED',
  'NOT_CONFIGURED',
] as const;
export type OutboxStatus = (typeof OUTBOX_STATUS)[number];

/** States a sweep may pick up. Terminal rows are never queried again. */
export const CLAIMABLE_STATUSES: readonly OutboxStatus[] = [
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
export const OUTBOX_LEASE_MS = 120_000;

/**
 * How long a message waits before asking again whether a provider exists.
 *
 * Without a delay, every sweep would re-claim the whole unconfigured backlog
 * on every run; with one, the backlog is checked hourly and sends itself the
 * hour after a provider is configured.
 */
export const NOT_CONFIGURED_RECHECK_MS = 3_600_000;

/** Messages one invocation may process. Bounded so a trigger cannot run long. */
export const OUTBOX_BATCH_LIMIT = 25;
export const OUTBOX_MAX_BATCH = 100;

/** Provider errors are stored to be read by a person, not to be a payload. */
export const MAX_LAST_ERROR_LENGTH = 300;

export type OutboxRecord = {
  id: string;
  merchantId: string;
  affiliateId: string | null;
  /** Null when the row names a template this build cannot render. */
  template: AffiliateTemplate | null;
  sourceKey: string;
  status: OutboxStatus;
  attempts: number;
  nextAttemptAt: number;
  lastError: string | null;
  payload: DocumentData;
  claimId: string | null;
  claimedAt: number | null;
};

function str(data: DocumentData, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return null;
}

function num(data: DocumentData, ...keys: string[]): number | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
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
export function parseOutboxRecord(
  merchantId: string,
  id: string,
  data: DocumentData,
): OutboxRecord {
  const status = str(data, 'status')?.toUpperCase() ?? 'QUEUED';
  const template = data.template;
  return {
    id,
    merchantId,
    affiliateId: str(data, 'affiliate_id'),
    template: isAffiliateTemplate(template) ? template : null,
    sourceKey: str(data, 'source_key') ?? '',
    status: (OUTBOX_STATUS as readonly string[]).includes(status)
      ? (status as OutboxStatus)
      : 'QUEUED',
    attempts: Math.max(0, Math.floor(num(data, 'retry_count', 'attempts') ?? 0)),
    nextAttemptAt: num(data, 'next_attempt_at') ?? 0,
    lastError: str(data, 'last_error'),
    payload:
      data.payload !== null && typeof data.payload === 'object'
        ? (data.payload as DocumentData)
        : {},
    claimId: str(data, 'claim_id'),
    claimedAt: num(data, 'claimed_at'),
  };
}

/** Whether this worker may take the message now. */
export function isClaimable(record: OutboxRecord, now: number): boolean {
  if (!CLAIMABLE_STATUSES.includes(record.status)) return false;
  if (record.nextAttemptAt > now) return false;
  if (record.status === 'PROCESSING') {
    // Only a lapsed claim, so two live workers never hold the same message.
    return (record.claimedAt ?? 0) + OUTBOX_LEASE_MS <= now;
  }
  return true;
}

function countPatch(attempts: number): DocumentData {
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
export function claimPatch(
  record: OutboxRecord,
  claimId: string,
  now: number,
): DocumentData {
  return {
    status: 'PROCESSING' satisfies OutboxStatus,
    ...countPatch(record.attempts + 1),
    claim_id: claimId,
    claimed_at: now,
    // Doubles as the lease: a lapsed claim becomes due to the pending query.
    next_attempt_at: now + OUTBOX_LEASE_MS,
    updated_at: now,
  };
}

export type OutboxTransition = {
  status: OutboxStatus;
  attempts: number;
  nextAttemptAt: number | null;
  lastError: string | null;
  terminal: boolean;
};

export function truncateError(error: string): string {
  const clean = error.replace(/\s+/g, ' ').trim();
  return clean.length <= MAX_LAST_ERROR_LENGTH
    ? clean
    : `${clean.slice(0, MAX_LAST_ERROR_LENGTH - 1)}…`;
}

/**
 * What one delivery outcome does to the row.
 *
 * Pure, and the only place the state machine is written down: every caller
 * either applies this or is wrong.
 */
export function planOutboxTransition(input: {
  /** The counter as it stood before `claimPatch` incremented it. */
  attemptsBeforeClaim: number;
  outcome: DeliveryOutcome;
  now: number;
}): OutboxTransition {
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
      nextAttemptAt: now + NOT_CONFIGURED_RECHECK_MS,
      lastError: null,
      terminal: false,
    };
  }

  const terminal = isTerminalDelivery(outcome, attempts);
  return {
    status: terminal ? 'FAILED' : 'QUEUED',
    attempts,
    nextAttemptAt: terminal ? null : now + nextAttemptDelayMs(attempts),
    lastError: truncateError(outcome.error),
    terminal,
  };
}

/** The transition as a document patch, including what the outcome carries. */
export function transitionPatch(
  transition: OutboxTransition,
  outcome: DeliveryOutcome,
  now: number,
): DocumentData {
  const patch: DocumentData = {
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

/* ---------------------------------------------------------------- composing */

/**
 * Everything the message needs that is not in the row, read after the commit.
 *
 * Resolved at delivery time rather than stored at enqueue time, so a reward a
 * merchant approved in the meantime is described as approved and one still
 * waiting is described as waiting. Nothing here comes from a client.
 */
export type OutboxContext = {
  merchantName: string | null;
  notificationsEnabled: boolean;
  recipientPhoneE164: string | null;
  /** Set when a recipient exists but must not be messaged. */
  blockedReason: Extract<
    DeliverySkipReason,
    'consent_missing' | 'affiliate_inactive'
  > | null;
  points: number;
  rewardStatus: RewardStatus | string | null;
};

export type ComposedMessage =
  | { ok: true; message: OutboxMessage }
  | { ok: false; outcome: DeliveryOutcome };

/** Templates addressed to the affiliate rather than to the customer. */
export const AFFILIATE_ADDRESSED_TEMPLATES: readonly AffiliateTemplate[] = [
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
export function composeOutboxMessage(
  record: OutboxRecord,
  context: OutboxContext,
): ComposedMessage {
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

  const body = renderAffiliateMessage(record.template, {
    points: context.points,
    merchantName: context.merchantName ?? undefined,
    statusText: AFFILIATE_ADDRESSED_TEMPLATES.includes(record.template)
      ? rewardStatusText(context.rewardStatus ?? 'PENDING')
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

/* -------------------------------------------------------------------- ports */

export interface OutboxTransaction {
  get(merchantId: string, outboxId: string): Promise<DocumentData | null>;
  update(merchantId: string, outboxId: string, patch: DocumentData): void;
}

export type StoredOutboxDocument = {
  merchantId: string;
  id: string;
  data: DocumentData;
};

export interface OutboxStore {
  runTransaction<T>(run: (transaction: OutboxTransaction) => Promise<T>): Promise<T>;
  /** Due, claimable rows, oldest first, capped by `limit`. */
  listPending(input: {
    merchantId: string | null;
    limit: number;
    now: number;
  }): Promise<StoredOutboxDocument[]>;
}

export type OutboxLogEntry = {
  event: string;
  merchant_id: string;
  outbox_id: string;
  template: string | null;
  status: OutboxStatus | 'MISSING' | 'HELD';
  attempts: number;
  /** Never a number anyone could dial. */
  phone_masked: string | null;
  error: string | null;
};

export type OutboxDeps = {
  store: OutboxStore;
  resolveContext: (record: OutboxRecord) => Promise<OutboxContext>;
  /** Null until a provider is configured. See `affiliate_outbox_firestore.ts`. */
  adapter: WhatsAppAdapter | null;
  now?: () => number;
  newClaimId?: () => string;
  log?: (level: 'info' | 'error', entry: OutboxLogEntry) => void;
};

function clockOf(deps: OutboxDeps): number {
  return deps.now ? deps.now() : Date.now();
}

function emit(
  deps: OutboxDeps,
  level: 'info' | 'error',
  entry: OutboxLogEntry,
): void {
  if (deps.log) {
    deps.log(level, entry);
    return;
  }
  const { event, ...fields } = entry;
  if (level === 'error') console.error(event, fields);
  else console.info(event, fields);
}

/* ------------------------------------------------------------------- claim */

export type ClaimResult =
  | { status: 'claimed'; record: OutboxRecord; attemptsBeforeClaim: number }
  | { status: 'held'; record: OutboxRecord }
  | { status: 'missing' };

/**
 * Takes one message, in one transaction, or reports that somebody else has it.
 *
 * Read and write in the same transaction is the entire point: two workers that
 * both read a QUEUED row will not both write PROCESSING to it — the second
 * transaction is retried against the first one's write and then sees a claim.
 */
export async function claimOutboxMessage(
  store: OutboxStore,
  input: { merchantId: string; outboxId: string; claimId: string; now: number },
): Promise<ClaimResult> {
  return store.runTransaction(async (transaction) => {
    const data = await transaction.get(input.merchantId, input.outboxId);
    if (data === null) return { status: 'missing' as const };

    const record = parseOutboxRecord(input.merchantId, input.outboxId, data);
    if (!isClaimable(record, input.now)) {
      return { status: 'held' as const, record };
    }

    transaction.update(
      input.merchantId,
      input.outboxId,
      claimPatch(record, input.claimId, input.now),
    );

    return {
      status: 'claimed' as const,
      attemptsBeforeClaim: record.attempts,
      record: {
        ...record,
        status: 'PROCESSING' as OutboxStatus,
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
export async function releaseOutboxMessage(
  store: OutboxStore,
  input: {
    merchantId: string;
    outboxId: string;
    claimId: string;
    patch: DocumentData;
  },
): Promise<'released' | 'lost'> {
  return store.runTransaction(async (transaction) => {
    const data = await transaction.get(input.merchantId, input.outboxId);
    if (data === null) return 'lost' as const;
    const record = parseOutboxRecord(input.merchantId, input.outboxId, data);
    if (record.claimId !== input.claimId) return 'lost' as const;

    transaction.update(input.merchantId, input.outboxId, input.patch);
    return 'released' as const;
  });
}

/* --------------------------------------------------------------- processing */

export type OutboxProcessResult =
  | { result: 'missing' }
  | { result: 'held' }
  | { result: 'lost' }
  | {
      result: 'sent' | 'skipped' | 'retry' | 'failed' | 'not_configured';
      transition: OutboxTransition;
      outcome: DeliveryOutcome;
    };

function resultOf(outcome: DeliveryOutcome, transition: OutboxTransition) {
  if (outcome.status === 'sent') return 'sent' as const;
  if (outcome.status === 'skipped') return 'skipped' as const;
  if (outcome.status === 'not_configured') return 'not_configured' as const;
  return transition.terminal ? ('failed' as const) : ('retry' as const);
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
export async function processOutboxMessage(
  deps: OutboxDeps,
  merchantId: string,
  outboxId: string,
): Promise<OutboxProcessResult> {
  const now = clockOf(deps);
  const claimId = deps.newClaimId ? deps.newClaimId() : randomUUID();

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
  let outcome: DeliveryOutcome;
  let phoneMasked: string | null = null;

  try {
    const context = await deps.resolveContext(record);
    const composed = composeOutboxMessage(record, context);
    if (!composed.ok) {
      outcome = composed.outcome;
    } else {
      phoneMasked = maskPhone(composed.message.toPhoneE164);
      outcome = await deliverAffiliateMessage(composed.message, {
        adapter: deps.adapter,
        notificationsEnabled: context.notificationsEnabled,
      });
    }
  } catch (error) {
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

  const entry: OutboxLogEntry = {
    event:
      outcome.status === 'failed'
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

  if (released === 'lost') return { result: 'lost' };
  return { result: resultOf(outcome, transition), transition, outcome };
}

export type OutboxSweepSummary = {
  scanned: number;
  sent: number;
  skipped: number;
  retried: number;
  failed: number;
  not_configured: number;
  held: number;
};

/**
 * Processes the due backlog, bounded.
 *
 * Sequential on purpose: the queue is small per business, and a parallel fan
 * out would multiply the read cost of a provider outage while making the
 * per-invocation bound meaningless.
 */
export async function processAffiliateOutbox(
  deps: OutboxDeps,
  input: { merchantId?: string | null; limit?: number } = {},
): Promise<OutboxSweepSummary> {
  const limit = Math.max(
    1,
    Math.min(Math.floor(input.limit ?? OUTBOX_BATCH_LIMIT), OUTBOX_MAX_BATCH),
  );
  const pending = await deps.store.listPending({
    merchantId: input.merchantId ?? null,
    limit,
    now: clockOf(deps),
  });

  const summary: OutboxSweepSummary = {
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
    const processed = await processOutboxMessage(
      deps,
      document.merchantId,
      document.id,
    );
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
