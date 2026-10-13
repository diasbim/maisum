import * as admin from 'firebase-admin';

import { affiliateConfigFrom } from './affiliate_store.js';
import { affiliateIds } from './affiliate_engine.js';
import type { RewardStatus } from './affiliate_contracts.js';
import type { WhatsAppAdapter } from './affiliate_notifications.js';
import {
  CLAIMABLE_STATUSES,
  type DocumentData,
  type OutboxContext,
  type OutboxRecord,
  type OutboxStore,
  type OutboxTransaction,
  type StoredOutboxDocument,
} from './affiliate_outbox.js';

/**
 * The outbox worker, bound to Firestore, and the one place a WhatsApp provider
 * would be plugged in.
 *
 * `affiliate_outbox.ts` decides; this file knows where the documents are. The
 * split is the same one the sale commit uses, and for the same reason: the
 * claim race and the retry state machine are testable against a fake store,
 * and nothing in the adapter below can disagree with them because it makes no
 * decisions.
 *
 * ── The provider gap ────────────────────────────────────────────────────────
 *
 * There used to be no WhatsApp provider here, and this section said what
 * filling the gap would take. It has been filled: `affiliate_whatsapp_cloud.ts`
 * implements the adapter against Meta's Cloud API, and `index.ts` builds one
 * when `AFFILIATE_WHATSAPP_ENABLED` is on and both credentials exist.
 *
 * The boundary itself has not moved, and that is why the change was one file.
 * `resolveWhatsAppAdapter()` still returns null by default, delivery still
 * answers `not_configured`, and the row stays claimable without burning a
 * retry or claiming success — which is still the state of any deployment that
 * has not been given credentials, and still the state the outbox tests run in.
 *
 * What the Cloud API forced was one thing, and it was not here: a
 * business-initiated message must be an approved template submitted as a name
 * plus ordered parameters, so `OutboxMessage` now carries the values it was
 * rendered from beside the rendered text. Nothing persisted changed — the body
 * was always rendered at send time, from context read fresh.
 *
 * Manual sharing is unaffected: the merchant app's `url_launcher` share sheet
 * is a separate path that needs none of this.
 */

const db = () => admin.firestore();

const outboxRef = (merchantId: string, outboxId: string) =>
  db()
    .collection('businesses')
    .doc(merchantId)
    .collection('affiliate_outbox')
    .doc(outboxId);

/* ------------------------------------------------------------------- store */

export const firestoreOutboxStore: OutboxStore = {
  runTransaction<T>(run: (transaction: OutboxTransaction) => Promise<T>): Promise<T> {
    return db().runTransaction((transaction) =>
      run({
        async get(merchantId: string, outboxId: string): Promise<DocumentData | null> {
          const snapshot = await transaction.get(outboxRef(merchantId, outboxId));
          return snapshot.exists ? ((snapshot.data() ?? {}) as DocumentData) : null;
        },
        update(merchantId: string, outboxId: string, patch: DocumentData): void {
          transaction.set(outboxRef(merchantId, outboxId), patch, { merge: true });
        },
      }),
    );
  },

  /**
   * The due backlog, bounded and ordered by when it became due.
   *
   * Scoped to one business when the caller names one — which the trigger and
   * the per-merchant sweep both do — and a collection group query otherwise.
   * Both are covered by the composite indexes on (status, next_attempt_at);
   * neither ever reads a terminal row.
   */
  async listPending(input: {
    merchantId: string | null;
    limit: number;
    now: number;
  }): Promise<StoredOutboxDocument[]> {
    const base =
      input.merchantId === null
        ? db().collectionGroup('affiliate_outbox')
        : db()
            .collection('businesses')
            .doc(input.merchantId)
            .collection('affiliate_outbox');

    const snapshot = await base
      .where('status', 'in', CLAIMABLE_STATUSES as string[])
      .where('next_attempt_at', '<=', input.now)
      .orderBy('next_attempt_at', 'asc')
      .limit(input.limit)
      .get();

    return snapshot.docs.map((doc) => {
      const data = (doc.data() ?? {}) as DocumentData;
      const merchantId =
        typeof data.merchant_id === 'string' && data.merchant_id.trim() !== ''
          ? data.merchant_id.trim()
          : // businesses/{merchantId}/affiliate_outbox/{id}
            (doc.ref.parent.parent?.id ?? '');
      return { merchantId, id: doc.id, data };
    });
  },
};

/* ----------------------------------------------------------------- context */

function str(data: DocumentData, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return null;
}

function points(payload: DocumentData): number {
  for (const key of ['reward_points', 'points']) {
    const value = payload[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
  }
  return 0;
}

/**
 * Reads what the message needs, after the sale that caused it committed.
 *
 * Nothing is taken from the queued row except the ids it was written with: the
 * number, the shop's name and the reward's current status are read from the
 * merchant's own documents at delivery time. That is what makes it impossible
 * for a till to choose who gets a message or what it says, and what keeps a
 * reward approved five minutes ago from being announced as still waiting.
 */
export function createFirestoreOutboxContextResolver(options: {
  /** `tryNormalizeMozambiquePhoneToE164`: the product's one definition. */
  normalizePhone: (raw: unknown) => string | null;
}): (record: OutboxRecord) => Promise<OutboxContext> {
  return async (record: OutboxRecord): Promise<OutboxContext> => {
    const businessSnapshot = await db()
      .collection('businesses')
      .doc(record.merchantId)
      .get();
    const business = (businessSnapshot.data() ?? {}) as DocumentData;
    const config = affiliateConfigFrom(business);
    const merchantName = str(business, 'merchant_name', 'name', 'business_name');

    const context: OutboxContext = {
      merchantName,
      notificationsEnabled: config.notificationsEnabled,
      recipientPhoneE164: null,
      blockedReason: null,
      points: points(record.payload),
      rewardStatus: str(record.payload, 'reward_status') as RewardStatus | null,
    };

    // A merchant who switched notifications off is answered before anybody's
    // number is read at all.
    if (!config.notificationsEnabled) return context;

    if (record.template === 'customer_referral_thanks') {
      const customerId = str(record.payload, 'customer_id');
      if (customerId === null) return context;

      const snapshot = await db()
        .collection('businesses')
        .doc(record.merchantId)
        .collection('customers')
        .doc(customerId)
        .get();
      const customer = (snapshot.data() ?? {}) as DocumentData;

      // The same consent gate the notification queue enforces: an automated
      // message to a customer who never agreed to one is not ours to send.
      if (str(customer, 'whatsapp_consent_status')?.toUpperCase() !== 'GRANTED') {
        return { ...context, blockedReason: 'consent_missing' };
      }
      return {
        ...context,
        recipientPhoneE164: options.normalizePhone(
          str(customer, 'phone_e164', 'phone'),
        ),
      };
    }

    if (record.affiliateId === null) return context;

    const linkId = affiliateIds.link(record.affiliateId, record.merchantId);
    const [affiliateSnapshot, linkSnapshot] = await Promise.all([
      db().collection('affiliates').doc(record.affiliateId).get(),
      db()
        .collection('businesses')
        .doc(record.merchantId)
        .collection('affiliate_merchants')
        .doc(linkId)
        .get(),
    ]);
    const affiliate = (affiliateSnapshot.data() ?? {}) as DocumentData;
    const link = (linkSnapshot.data() ?? {}) as DocumentData;

    // Both the platform identity and this business's relationship must be
    // active. A merchant deactivates the link, not the global identity.
    const affiliateStatus =
      str(affiliate, 'status')?.toUpperCase() ?? 'INACTIVE';
    const linkStatus = str(link, 'status')?.toUpperCase() ?? 'INACTIVE';
    if (
      !affiliateSnapshot.exists ||
      !linkSnapshot.exists ||
      affiliateStatus !== 'ACTIVE' ||
      linkStatus !== 'ACTIVE'
    ) {
      return { ...context, blockedReason: 'affiliate_inactive' };
    }

    return {
      ...context,
      recipientPhoneE164: options.normalizePhone(
        str(affiliate, 'phone_e164', 'phone'),
      ),
      rewardStatus: await currentRewardStatus(record, context.rewardStatus),
    };
  };
}

/**
 * The reward's status as it is now, not as it was when the row was queued.
 *
 * Falls back to the queued value when the reward cannot be located, and the
 * fallback for that is `PENDING` — the direction that can only ever understate
 * the news. Telling an affiliate their points are approved when a merchant has
 * not agreed is the one mistake this feature cannot make.
 */
async function currentRewardStatus(
  record: OutboxRecord,
  queued: RewardStatus | string | null,
): Promise<RewardStatus | string | null> {
  const rewardId =
    str(record.payload, 'reward_id') ??
    rewardIdFromAttribution(record, str(record.payload, 'attribution_id'));
  if (rewardId === null) return queued;

  const snapshot = await db()
    .collection('businesses')
    .doc(record.merchantId)
    .collection('affiliate_rewards')
    .doc(rewardId)
    .get();
  if (!snapshot.exists) return queued;
  return str((snapshot.data() ?? {}) as DocumentData, 'status') ?? queued;
}

function rewardIdFromAttribution(
  record: OutboxRecord,
  attributionId: string | null,
): string | null {
  if (attributionId === null) return null;
  return affiliateIds.reward(
    attributionId,
    record.template === 'affiliate_customer_returned'
      ? 'CUSTOMER_RETURN'
      : 'FIRST_QUALIFYING_SALE',
  );
}

/* ----------------------------------------------------------------- adapter */

let configuredAdapter: WhatsAppAdapter | null = null;

/**
 * Installs a provider.
 *
 * The hook exists so that wiring one is a single call at startup rather than
 * an edit spread through the worker — and so that the day it happens, nothing
 * about claiming, backoff or masking has to be revisited.
 */
export function setWhatsAppAdapter(adapter: WhatsAppAdapter | null): void {
  configuredAdapter = adapter;
}

/**
 * The provider something has explicitly set, if any.
 *
 * Null is a deliberate answer and not an oversight. It means "nobody injected
 * one here", which is the normal case: `index.ts` builds the Cloud API adapter
 * from configuration instead, and falls back to this. The seam stays because
 * it is what the outbox tests inject a double through, and removing it would
 * make the sweep untestable without the network.
 *
 * Still undone, and deliberately out of this module: the delivery-receipt
 * webhook. Without it a message reads as `SENT` once Meta accepts it, which is
 * not the same as delivered or read.
 */
export function resolveWhatsAppAdapter(): WhatsAppAdapter | null {
  return configuredAdapter;
}
