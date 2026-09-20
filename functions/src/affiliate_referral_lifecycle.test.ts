import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_AFFILIATE_CONFIG,
  REFERRAL_REASON_MESSAGE,
  type AffiliateConfig,
} from './affiliate_contracts.js';
import { affiliateIds, saleIdempotencyKey } from './affiliate_engine.js';
import type { OutboxMessage } from './affiliate_notifications.js';
import {
  commitOfflineReferralSale,
  type OfflineReferralSaleInput,
} from './affiliate_offline_sale.js';
import {
  CLAIMABLE_STATUSES,
  processAffiliateOutbox,
  type DocumentData as OutboxDocumentData,
  type OutboxContext,
  type OutboxLogEntry,
  type OutboxRecord,
  type OutboxStore,
  type OutboxTransaction,
  type StoredOutboxDocument,
} from './affiliate_outbox.js';
import {
  commitReferralSale,
  recordReferredCustomerReturn,
  referralBonusLedgerEntryId,
  referralPaths,
  reverseReferralSale,
  type DocumentData,
  type ReferralSaleCommitInput,
  type ReferralSaleGateway,
  type ReferralSaleTransaction,
  type StoredDocument,
  type WriteOperation,
} from './affiliate_sale_commit.js';

/**
 * The seven scenarios of §12, each run end to end against one store.
 *
 * The other affiliate test files each hold one seam still and prove a property
 * of it. This one does the opposite: it starts from an empty business, runs a
 * whole scenario through the real commit, the real offline reconciliation, the
 * real return hook and the real outbox worker, and then asks what the business
 * is left holding. A regression that no single-seam test can see — a message
 * queued for a sale that was refused, a reward that survives a replay, a
 * second attribution created by reconnecting — shows up here as a wrong count
 * at the end of a story rather than as a wrong field in the middle of one.
 *
 * It runs without an emulator, deliberately. The transaction is a port, and
 * the double below behaves the way Firestore does in the two ways that decide
 * whether a commit is legal at all: a read issued after a write is refused,
 * and `create` on an existing document is refused. A plan that production
 * would reject fails here instead. What this does *not* prove is that
 * `firestore.rules` and `firestore.indexes.json` are deployed and enforced —
 * that needs the emulator, and is asserted as a source contract in
 * `affiliate_security_contracts.test.ts` instead.
 */

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
const MERCHANT = 'm1';
const OTHER_MERCHANT = 'm2';
const CODE = 'AFI-ANA-7K2P';
const CUSTOMER = 'c1';
const PHONE = '+258841234567';
const DEVICE = 'till-1';

const LINK_ID = affiliateIds.link('af1', MERCHANT);
const ATTRIBUTION_ID = affiliateIds.attribution(MERCHANT, CUSTOMER);
const FIRST_REWARD_ID = affiliateIds.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE');
const RETURN_REWARD_ID = affiliateIds.reward(ATTRIBUTION_ID, 'CUSTOMER_RETURN');

/* -------------------------------------------------------------- the store */

type Store = Map<string, DocumentData>;

/**
 * One map, shared by every seam in a scenario.
 *
 * The outbox rows the sale transaction writes are read back by the worker from
 * the same paths, so a message the commit never queued is a message the worker
 * cannot invent.
 */
function gatewayOver(
  docs: Store,
  options: { failAfterWrites?: number } = {},
): { gateway: ReferralSaleGateway; applied: WriteOperation[] } {
  const applied: WriteOperation[] = [];

  const gateway: ReferralSaleGateway = {
    async runTransaction<T>(
      run: (transaction: ReferralSaleTransaction) => Promise<T>,
    ): Promise<T> {
      const staged: WriteOperation[] = [];
      let hasWritten = false;

      const stage = (operation: WriteOperation): void => {
        hasWritten = true;
        if (
          options.failAfterWrites !== undefined &&
          staged.length >= options.failAfterWrites
        ) {
          throw new Error('injected transaction failure');
        }
        staged.push(operation);
      };

      const transaction: ReferralSaleTransaction = {
        async getDoc(docPath: string): Promise<DocumentData | null> {
          assert.ok(!hasWritten, `read after write: ${docPath}`);
          const data = docs.get(docPath);
          return data === undefined ? null : { ...data };
        },
        async queryDocs(
          collectionPath: string,
          field: string,
          value: string,
          limit: number,
        ): Promise<StoredDocument[]> {
          assert.ok(!hasWritten, `query after write: ${collectionPath}`);
          const rows: StoredDocument[] = [];
          for (const [docPath, data] of docs) {
            if (!docPath.startsWith(`${collectionPath}/`)) continue;
            const id = docPath.slice(collectionPath.length + 1);
            if (id.includes('/')) continue;
            if (data[field] !== value) continue;
            rows.push({ id, data: { ...data } });
            if (rows.length >= limit) break;
          }
          return rows;
        },
        create: (docPath, data) => stage({ kind: 'create', path: docPath, data }),
        merge: (docPath, data) => stage({ kind: 'merge', path: docPath, data }),
      };

      const result = await run(transaction);

      for (const operation of staged) {
        if (operation.kind === 'create') {
          assert.ok(
            !docs.has(operation.path),
            `create on an existing document: ${operation.path}`,
          );
          docs.set(operation.path, { ...operation.data });
        } else {
          docs.set(operation.path, {
            ...(docs.get(operation.path) ?? {}),
            ...operation.data,
          });
        }
        applied.push(operation);
      }

      return result;
    },
  };

  return { gateway, applied };
}

/** The same documents, seen the way the outbox worker addresses them. */
function outboxStoreOver(docs: Store): OutboxStore {
  return {
    async runTransaction<T>(
      run: (transaction: OutboxTransaction) => Promise<T>,
    ): Promise<T> {
      const staged = new Map<string, OutboxDocumentData>();
      const transaction: OutboxTransaction = {
        get: async (merchantId, outboxId) => {
          const data = docs.get(referralPaths.outbox(merchantId, outboxId));
          return data === undefined ? null : { ...data };
        },
        update: (merchantId, outboxId, patch) => {
          const path = referralPaths.outbox(merchantId, outboxId);
          staged.set(path, { ...(staged.get(path) ?? {}), ...patch });
        },
      };
      const result = await run(transaction);
      for (const [path, patch] of staged) {
        docs.set(path, { ...(docs.get(path) ?? {}), ...patch });
      }
      return result;
    },
    async listPending(input): Promise<StoredOutboxDocument[]> {
      const rows: StoredOutboxDocument[] = [];
      for (const [path, data] of docs) {
        const match = /^businesses\/([^/]+)\/affiliate_outbox\/([^/]+)$/.exec(path);
        if (match === null) continue;
        const [, merchantId, id] = match;
        if (input.merchantId !== null && merchantId !== input.merchantId) continue;
        const status = String(data.status ?? 'QUEUED');
        if (!(CLAIMABLE_STATUSES as readonly string[]).includes(status)) continue;
        if (Number(data.next_attempt_at ?? 0) > input.now) continue;
        rows.push({ merchantId, id, data: { ...data } });
      }
      rows.sort(
        (left, right) =>
          Number(left.data.created_at ?? 0) - Number(right.data.created_at ?? 0),
      );
      return rows.slice(0, input.limit);
    },
  };
}

/* ------------------------------------------------------------- inspection */

function docsUnder(docs: Store, merchantId: string, collection: string): string[] {
  const prefix = `businesses/${merchantId}/${collection}/`;
  return [...docs.keys()].filter((path) => path.startsWith(prefix)).sort();
}

function eventTypes(docs: Store, merchantId = MERCHANT): string[] {
  return docsUnder(docs, merchantId, 'affiliate_events')
    .map((path) => String(docs.get(path)?.event_type ?? ''))
    .sort();
}

function snapshot(docs: Store): Map<string, string> {
  return new Map([...docs].map(([key, value]) => [key, JSON.stringify(value)]));
}

/* --------------------------------------------------------------- fixtures */

function config(overrides: Partial<AffiliateConfig> = {}): AffiliateConfig {
  return {
    ...DEFAULT_AFFILIATE_CONFIG,
    enabled: true,
    firstSaleRewardPoints: 100,
    ...overrides,
  };
}

function storeWith(
  overrides: {
    code?: DocumentData;
    customer?: DocumentData;
    affiliate?: DocumentData;
    link?: DocumentData;
    extra?: Record<string, DocumentData>;
  } = {},
): Store {
  const docs: Store = new Map();
  docs.set(referralPaths.business(MERCHANT), {
    id: MERCHANT,
    merchant_name: 'Salão Bela',
    loyalty_config: { points_per_mzn: 100, version: 2 },
  });
  docs.set(referralPaths.codeLookup(CODE), {
    code: CODE,
    merchant_id: MERCHANT,
    affiliate_id: 'af1',
    code_id: 'ac1',
  });
  docs.set(referralPaths.code(MERCHANT, 'ac1'), {
    id: 'ac1',
    merchant_id: MERCHANT,
    affiliate_id: 'af1',
    code: CODE,
    normalized_code: CODE,
    status: 'ACTIVE',
    starts_at: NOW - DAY,
    expires_at: NOW + 30 * DAY,
    usage_limit: null,
    usage_count: 0,
    first_visit_only: true,
    benefit_type: 'FIXED_AMOUNT',
    benefit_value: 50,
    ...overrides.code,
  });
  docs.set(referralPaths.affiliate('af1'), {
    id: 'af1',
    status: 'ACTIVE',
    display_name: 'Ana Silva',
    first_name: 'Ana',
    phone_e164: '+258840000001',
    ...overrides.affiliate,
  });
  docs.set(referralPaths.link(MERCHANT, LINK_ID), {
    id: LINK_ID,
    merchant_id: MERCHANT,
    affiliate_id: 'af1',
    status: 'ACTIVE',
    ...overrides.link,
  });
  docs.set(referralPaths.customer(MERCHANT, CUSTOMER), {
    id: CUSTOMER,
    merchant_id: MERCHANT,
    name: 'Joana Cliente',
    phone: PHONE,
    confirmed_points: 0,
    whatsapp_consent: true,
    ...overrides.customer,
  });
  for (const [path, data] of Object.entries(overrides.extra ?? {})) {
    docs.set(path, data);
  }
  return docs;
}

function input(
  overrides: Partial<ReferralSaleCommitInput> = {},
): ReferralSaleCommitInput {
  return {
    merchantId: MERCHANT,
    deviceId: DEVICE,
    localSaleId: 'l1',
    customerId: CUSTOMER,
    customerPhoneE164: PHONE,
    grossAmount: 500,
    rawCode: 'afi-ana-7k2p',
    items: [],
    appUserId: 'u1',
    now: NOW,
    ...overrides,
  };
}

function offlineInput(
  overrides: Partial<OfflineReferralSaleInput> = {},
): OfflineReferralSaleInput {
  return {
    ...input(),
    offlineBenefitApplied: true,
    appliedBenefit: {
      type: 'FIXED_AMOUNT',
      value: 50,
      discountAmount: 50,
      pointsAwarded: 0,
    },
    localCreatedAt: NOW - 3 * 3_600_000,
    ...overrides,
  };
}

async function commit(
  docs: Store,
  overrides: Partial<ReferralSaleCommitInput> = {},
  settings: AffiliateConfig = config(),
  options: { failAfterWrites?: number } = {},
) {
  const { gateway } = gatewayOver(docs, options);
  return commitReferralSale(gateway, input(overrides), () => settings);
}

async function reconcile(
  docs: Store,
  overrides: Partial<OfflineReferralSaleInput> = {},
  settings: AffiliateConfig = config(),
) {
  const { gateway } = gatewayOver(docs);
  return commitOfflineReferralSale(gateway, offlineInput(overrides), () => settings);
}

/**
 * Runs the real worker over whatever the transaction queued.
 *
 * The context resolver mirrors the Firestore one: every number and every name
 * is read from the merchant's own documents at delivery time, never from the
 * queued row, so a message this returns is one the stored data justified.
 */
async function deliverQueuedMessages(
  docs: Store,
  options: { fail?: boolean; now?: number } = {},
): Promise<{ sent: OutboxMessage[]; logged: OutboxLogEntry[] }> {
  const sent: OutboxMessage[] = [];
  const logged: OutboxLogEntry[] = [];
  const clock = options.now ?? NOW + 1_000;

  await processAffiliateOutbox(
    {
      store: outboxStoreOver(docs),
      adapter: {
        async send(message: OutboxMessage): Promise<{ providerMessageId: string }> {
          if (options.fail === true) throw new Error('provider down');
          sent.push(message);
          return { providerMessageId: `pm-${sent.length}` };
        },
      },
      resolveContext: async (record: OutboxRecord): Promise<OutboxContext> => {
        const business = docs.get(referralPaths.business(record.merchantId));
        const rewardId =
          typeof record.payload.reward_id === 'string'
            ? record.payload.reward_id
            : null;
        const reward =
          rewardId === null
            ? null
            : docs.get(referralPaths.reward(record.merchantId, rewardId));
        const context: OutboxContext = {
          merchantName:
            typeof business?.merchant_name === 'string'
              ? business.merchant_name
              : null,
          notificationsEnabled: true,
          recipientPhoneE164: null,
          blockedReason: null,
          points:
            typeof record.payload.reward_points === 'number'
              ? record.payload.reward_points
              : 0,
          rewardStatus:
            typeof reward?.status === 'string'
              ? (reward.status as OutboxContext['rewardStatus'])
              : null,
        };

        if (record.template === 'customer_referral_thanks') {
          const customerId =
            typeof record.payload.customer_id === 'string'
              ? record.payload.customer_id
              : null;
          const customer =
            customerId === null
              ? null
              : docs.get(referralPaths.customer(record.merchantId, customerId));
          if (customer?.whatsapp_consent !== true) {
            return { ...context, blockedReason: 'consent_missing' };
          }
          return {
            ...context,
            recipientPhoneE164:
              typeof customer.phone === 'string' ? customer.phone : null,
          };
        }

        if (record.affiliateId === null) return context;
        const affiliate = docs.get(referralPaths.affiliate(record.affiliateId));
        const link = docs.get(
          referralPaths.link(
            record.merchantId,
            affiliateIds.link(record.affiliateId, record.merchantId),
          ),
        );
        if (affiliate?.status !== 'ACTIVE' || link?.status !== 'ACTIVE') {
          return { ...context, blockedReason: 'affiliate_inactive' };
        }
        return {
          ...context,
          recipientPhoneE164:
            typeof affiliate.phone_e164 === 'string' ? affiliate.phone_e164 : null,
        };
      },
      now: () => clock,
      newClaimId: () => 'claim-1',
      log: (_level, entry) => logged.push(entry),
    },
    { merchantId: MERCHANT, limit: 25 },
  );

  return { sent, logged };
}

/* =========================================================== scenario one */

test('§12.1 a new customer with a valid code is discounted, attributed, rewarded and messaged', async () => {
  const docs = storeWith();

  const outcome = await commit(docs);
  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;

  // The benefit: 50 off a 500 bill.
  const saleId = affiliateIds.sale(DEVICE, 'l1');
  const sale = docs.get(referralPaths.sale(MERCHANT, saleId));
  assert.equal(sale?.gross_amount, 500);
  assert.equal(sale?.amount, 450);
  assert.equal(sale?.referral_benefit_amount, 50);

  // The ordinary points: earned on what the customer paid, by the business's
  // own loyalty rule, exactly as a sale without a code earns them.
  assert.equal(sale?.points, 4);

  // The attribution, and the first reward it owes.
  const attribution = docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
  assert.equal(attribution?.status, 'CONFIRMED');
  assert.equal(attribution?.first_sale_id, saleId);
  assert.equal(attribution?.affiliate_id, 'af1');

  const reward = docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID));
  assert.equal(reward?.status, 'PENDING');
  assert.equal(reward?.value, 100);
  assert.equal(reward?.reward_type ?? reward?.type, 'FIRST_QUALIFYING_SALE');

  // The code was spent once.
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);

  // The history a merchant reads back.
  assert.deepEqual(eventTypes(docs), [
    'AFFILIATE_REWARD_CREATED',
    'REFERRAL_ATTRIBUTED',
  ]);

  // The messages: queued by the transaction, sent by the worker afterwards.
  // Two of them — the affiliate is told they earned something, the customer is
  // thanked — and neither is sent inside the transaction that made the sale.
  const queued = docsUnder(docs, MERCHANT, 'affiliate_outbox');
  assert.equal(queued.length, 2);
  for (const path of queued) assert.equal(docs.get(path)?.status, 'QUEUED');

  const { sent } = await deliverQueuedMessages(docs);
  assert.deepEqual(
    sent.map((message) => message.template).sort(),
    ['affiliate_new_customer', 'customer_referral_thanks'],
  );
  const toAffiliate = sent.find(
    (message) => message.template === 'affiliate_new_customer',
  );
  assert.equal(toAffiliate?.toPhoneE164, '+258840000001');
  assert.match(String(toAffiliate?.body), /Salão Bela/);
  for (const path of queued) assert.equal(docs.get(path)?.status, 'SENT');
});

test('§12.1 a delivery failure leaves the sale, the attribution and the reward exactly as they were', async () => {
  const docs = storeWith();
  await commit(docs);

  const before = snapshot(docs);
  const { sent } = await deliverQueuedMessages(docs, { fail: true });

  assert.equal(sent.length, 0);
  const saleId = affiliateIds.sale(DEVICE, 'l1');
  for (const path of [
    referralPaths.sale(MERCHANT, saleId),
    referralPaths.attribution(MERCHANT, ATTRIBUTION_ID),
    referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
  ]) {
    assert.equal(
      snapshot(docs).get(path),
      before.get(path),
      `WhatsApp changed ${path}`,
    );
  }
  // Only the queue rows moved, and they moved to "try again".
  for (const path of docsUnder(docs, MERCHANT, 'affiliate_outbox')) {
    assert.equal(docs.get(path)?.status, 'QUEUED');
    assert.equal(docs.get(path)?.attempts, 1);
  }
});

/* =========================================================== scenario two */

test('§12.2 an existing customer under a first-visit code is refused and the sale goes on without one', async () => {
  const docs = storeWith({
    extra: {
      [`${referralPaths.sales(MERCHANT)}/older-sale`]: {
        id: 'older-sale',
        merchant_id: MERCHANT,
        customer_id: CUSTOMER,
        amount: 200,
        cancellation_status: 'ACTIVE',
      },
    },
  });

  const outcome = await commit(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CUSTOMER_NOT_ELIGIBLE');
  assert.equal(outcome.message, REFERRAL_REASON_MESSAGE.CUSTOMER_NOT_ELIGIBLE);

  // No acquisition, no reward, no message, and the code is not spent.
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_attributions'), []);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), []);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_outbox'), []);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
  assert.deepEqual(eventTypes(docs), ['REFERRAL_REJECTED']);

  // The referred sale was never written, so the till is free to ring the same
  // basket up as an ordinary sale under the same local id.
  const saleId = affiliateIds.sale(DEVICE, 'l1');
  assert.equal(docs.has(referralPaths.sale(MERCHANT, saleId)), false);

  docs.set(referralPaths.sale(MERCHANT, saleId), {
    id: saleId,
    merchant_id: MERCHANT,
    customer_id: CUSTOMER,
    amount: 500,
    points: 5,
    cancellation_status: 'ACTIVE',
  });
  const { gateway } = gatewayOver(docs);
  const reversal = await reverseReferralSale(gateway, {
    merchantId: MERCHANT,
    saleId,
    cancelledAt: NOW + 1,
    actorId: 'u1',
  });
  assert.equal(
    reversal.status,
    'not_referred',
    'the fallback sale carries no referral to undo',
  );
});

/* ========================================================= scenario three */

test('§12.3 an expired code says so in words the cashier can read, and blocks nothing', async () => {
  const docs = storeWith({ code: { expires_at: NOW - 1 } });
  const before = snapshot(docs);

  const outcome = await commit(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CODE_EXPIRED');
  assert.equal(outcome.message, 'Este código expirou.');
  // No id, no phone, no other business named in what the cashier is shown.
  assert.doesNotMatch(outcome.message, /af1|ac1|258|m1/);

  // The rejection event is the only thing written.
  const added = [...docs.keys()].filter((path) => !before.has(path));
  assert.equal(added.length, 1);
  assert.ok(added[0].startsWith(`businesses/${MERCHANT}/affiliate_events/`));
  assert.equal(docs.get(added[0])?.event_type, 'REFERRAL_REJECTED');
  assert.equal(docs.has(referralPaths.sale(MERCHANT, affiliateIds.sale(DEVICE, 'l1'))), false);
});

/* ========================================================== scenario four */

test('§12.4 the same submit twice leaves one sale, one attribution, one reward and one ledger entry', async () => {
  const docs = storeWith({
    code: { benefit_type: 'POINTS', benefit_value: 25 },
  });

  const first = await commit(docs);
  const afterFirst = snapshot(docs);
  const second = await commit(docs);

  assert.equal(first.status, 'committed');
  assert.equal(second.status, 'replayed');
  if (second.status !== 'replayed') return;
  assert.equal(second.result.replayed, true);

  assert.deepEqual(snapshot(docs), afterFirst, 'the replay wrote something');

  const saleId = affiliateIds.sale(DEVICE, 'l1');
  assert.deepEqual(docsUnder(docs, MERCHANT, 'sales'), [
    referralPaths.sale(MERCHANT, saleId),
  ]);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_attributions'), [
    referralPaths.attribution(MERCHANT, ATTRIBUTION_ID),
  ]);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), [
    referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
  ]);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'loyalty_ledger'), [
    referralPaths.ledgerEntry(MERCHANT, referralBonusLedgerEntryId(saleId)),
  ]);
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_outbox').length, 2);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);

  // And each message is still sent once, not once per submit.
  const { sent } = await deliverQueuedMessages(docs);
  assert.equal(sent.length, 2);
  const again = await deliverQueuedMessages(docs);
  assert.equal(again.sent.length, 0);
});

test('§12.4 the same replay answers the same thing, including the same idempotency key', async () => {
  const docs = storeWith();
  const first = await commit(docs);
  const second = await commit(docs);

  assert.equal(first.status, 'committed');
  assert.equal(second.status, 'replayed');
  if (first.status !== 'committed' || second.status !== 'replayed') return;

  assert.equal(second.result.idempotency_key, saleIdempotencyKey(DEVICE, 'l1'));
  assert.equal(
    second.result.referral.attribution_id,
    first.result.referral.attribution_id,
  );
  assert.equal(second.result.referral.reward?.id, first.result.referral.reward?.id);
  assert.equal(second.result.sale.amount, first.result.sale.amount);
});

/* ========================================================== scenario five */

test('§12.5 an offline sale with a cached code is confirmed once when the till reconnects', async () => {
  const docs = storeWith();

  // Reconnect: the queued operation reaches the server for the first time.
  const reconnected = await reconcile(docs);
  assert.equal(reconnected.status, 'committed');
  if (reconnected.status !== 'committed') return;

  const saleId = affiliateIds.sale(DEVICE, 'l1');
  const sale = docs.get(referralPaths.sale(MERCHANT, saleId));
  assert.equal(sale?.amount, 450, 'the discount the till gave is the one recorded');
  assert.equal(sale?.gross_amount, 500);
  assert.equal(sale?.referral_status, 'ATTRIBUTED');
  assert.equal(sale?.referral_offline_benefit_applied, true);

  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CONFIRMED',
  );
  assert.equal(
    docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status,
    'PENDING',
  );
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);

  // A retry storm after a flaky reconnect: the queue sends it again, twice.
  const afterFirst = snapshot(docs);
  const again = await reconcile(docs);
  const andAgain = await reconcile(docs);

  assert.equal(again.status, 'replayed');
  assert.equal(andAgain.status, 'replayed');
  assert.deepEqual(snapshot(docs), afterFirst, 'a retry wrote a second time');
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_attributions').length, 1);
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_rewards').length, 1);
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_outbox').length, 1);

  const { sent } = await deliverQueuedMessages(docs);
  assert.equal(sent.length, 1);
});
test('§12.5 a device whose clock is days out is still reconciled, and the skew is recorded', async () => {
  const docs = storeWith();

  const outcome = await reconcile(docs, { localCreatedAt: NOW - 3 * DAY });

  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;
  assert.equal(outcome.result.clock_skew_ms, 3 * DAY);
  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CONFIRMED',
    'a wrong clock is a signal, never a refusal',
  );

  // Recorded on the event, so a run of skewed tills is visible afterwards.
  const saleId = affiliateIds.sale(DEVICE, 'l1');
  const event = docs.get(
    referralPaths.event(
      MERCHANT,
      affiliateIds.event(MERCHANT, 'REFERRAL_ATTRIBUTED', saleId),
    ),
  );
  assert.equal((event?.metadata as DocumentData).clock_skew_exceeded, true);
  assert.equal((event?.metadata as DocumentData).clock_skew_ms, 3 * DAY);
  // The sale keeps the till's own timestamp: that is what the receipt says.
  assert.equal(docs.get(referralPaths.sale(MERCHANT, saleId))?.created_at, NOW - 3 * DAY);
});

/* =========================================================== scenario six */

test('§12.6 a code that expired before the sync keeps the sale and the discount, and pays nobody', async () => {
  const docs = storeWith({ code: { expires_at: NOW - 1 } });

  const outcome = await reconcile(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CODE_EXPIRED');

  // The sale is kept, and so is the money already taken off the bill.
  const saleId = affiliateIds.sale(DEVICE, 'l1');
  const sale = docs.get(referralPaths.sale(MERCHANT, saleId));
  assert.ok(sale, 'the sale was dropped');
  assert.equal(sale.amount, 450);
  assert.equal(sale.gross_amount, 500);
  assert.equal(sale.referral_benefit_amount, 50);
  assert.equal(sale.referral_status, 'REJECTED');
  assert.equal(sale.referral_rejection_reason, 'CODE_EXPIRED');

  // The attribution exists, as the refusal it is.
  const attribution = docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
  assert.equal(attribution?.status, 'REJECTED');
  assert.equal(attribution?.rejection_reason, 'CODE_EXPIRED');

  // Nobody is owed anything, nobody is messaged, and the code is not spent.
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), []);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_outbox'), []);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);

  // And the merchant can find out why they paid for nothing.
  const signals = docsUnder(docs, MERCHANT, 'affiliate_fraud_signals');
  assert.equal(signals.length, 1);
  const signal = docs.get(signals[0]);
  assert.equal(signal?.signal_type, 'OFFLINE_CODE_REJECTED');
  assert.equal(signal?.severity, 'HIGH');
  assert.deepEqual(eventTypes(docs), ['REFERRAL_REJECTED']);
});

test('§12.6 a rejected offline referral stays rejected however many times the queue retries it', async () => {
  const docs = storeWith({ code: { expires_at: NOW - 1 } });

  await reconcile(docs);
  const afterFirst = snapshot(docs);
  const second = await reconcile(docs);
  const third = await reconcile(docs);

  assert.equal(second.status, 'replayed');
  assert.equal(third.status, 'replayed');
  assert.deepEqual(snapshot(docs), afterFirst);
  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'REJECTED',
  );
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), []);
});

/* ========================================================= scenario seven */

const RETURNS_ON = config({
  returnRewardEnabled: true,
  returnRewardPoints: 40,
  returnWindowDays: 30,
});

async function secondVisit(
  docs: Store,
  occurredAt: number,
  settings: AffiliateConfig,
  saleId = 'sale-2',
) {
  const { gateway } = gatewayOver(docs);
  return recordReferredCustomerReturn(
    gateway,
    { merchantId: MERCHANT, saleId, customerId: CUSTOMER, amount: 300, occurredAt },
    settings,
  );
}

test('§12.7 a referred customer who comes back inside the window earns one return event and one reward', async () => {
  const docs = storeWith();
  await commit(docs);
  await deliverQueuedMessages(docs);

  const returned = await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON);
  assert.equal(returned.status, 'recorded');

  const returns = docsUnder(docs, MERCHANT, 'affiliate_events').filter(
    (path) => docs.get(path)?.event_type === 'REFERRED_CUSTOMER_RETURNED',
  );
  assert.equal(returns.length, 1);

  const reward = docs.get(referralPaths.reward(MERCHANT, RETURN_REWARD_ID));
  assert.equal(reward?.status, 'PENDING');
  assert.equal(reward?.value, 40);
  assert.equal(reward?.trigger_sale_id, 'sale-2');

  // Two rewards in total, and they are the two different kinds.
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards').sort(), [
    referralPaths.reward(MERCHANT, RETURN_REWARD_ID),
    referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
  ].sort());

  // The trigger firing again is the same visit, not a second one.
  const afterReturn = snapshot(docs);
  assert.equal((await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON)).status,
    'already_recorded');
  assert.deepEqual(snapshot(docs), afterReturn);

  const { sent } = await deliverQueuedMessages(docs, { now: NOW + 7 * DAY + 1_000 });
  assert.equal(sent.length, 1, 'the return was announced exactly once');
  assert.equal(sent[0].template, 'affiliate_customer_returned');
});

test('§12.7 a return outside the window is history, not money', async () => {
  const docs = storeWith();
  await commit(docs);

  const returned = await secondVisit(docs, NOW + 45 * DAY, RETURNS_ON);

  assert.equal(returned.status, 'out_of_window');
  assert.equal(returned.reward_id, null);
  assert.equal(docs.has(referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
});

test('§12.7 a business that never turned return rewards on owes nothing for a return', async () => {
  const docs = storeWith();
  await commit(docs);

  const returned = await secondVisit(docs, NOW + 7 * DAY, config());

  assert.equal(returned.reward_id, null);
  assert.equal(docs.has(referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), [
    referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
  ]);
});

/* ================================================= the whole life, at once */

test('a referral that is sold, returned to and then cancelled leaves nothing payable', async () => {
  const docs = storeWith();
  await commit(docs);
  await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON);
  await deliverQueuedMessages(docs);

  const saleId = affiliateIds.sale(DEVICE, 'l1');
  const { gateway } = gatewayOver(docs);
  const reversal = await reverseReferralSale(gateway, {
    merchantId: MERCHANT,
    saleId,
    cancelledAt: NOW + 10 * DAY,
    actorId: 'u1',
  });

  assert.equal(reversal.status, 'reversed');
  assert.equal(reversal.attribution_cancelled, true);

  // §13: a cancelled sale never leaves a PENDING or APPROVED reward behind.
  for (const path of docsUnder(docs, MERCHANT, 'affiliate_rewards')) {
    const status = docs.get(path)?.status;
    assert.ok(
      status !== 'PENDING' && status !== 'APPROVED',
      `${path} is still ${String(status)} after the sale was cancelled`,
    );
  }
  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CANCELLED',
  );
  // The code stays spent: cancelling is not a way around a usage limit.
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
});

test('a cancellation that cannot take back a paid reward raises it for a person instead', async () => {
  const docs = storeWith();
  await commit(docs);
  docs.set(referralPaths.reward(MERCHANT, FIRST_REWARD_ID), {
    ...docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID)),
    status: 'PAID',
    paid_at: NOW + DAY,
  });

  const saleId = affiliateIds.sale(DEVICE, 'l1');
  const { gateway } = gatewayOver(docs);
  const reversal = await reverseReferralSale(gateway, {
    merchantId: MERCHANT,
    saleId,
    cancelledAt: NOW + 2 * DAY,
    actorId: 'u1',
  });

  assert.deepEqual(reversal.rewards_cancelled, []);
  assert.deepEqual(reversal.rewards_needing_review, [FIRST_REWARD_ID]);
  assert.equal(
    docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status,
    'PAID',
  );
  const signal = docs.get(
    referralPaths.fraudSignal(
      MERCHANT,
      affiliateIds.fraudSignal(MERCHANT, 'PAID_REWARD_SALE_CANCELLED', FIRST_REWARD_ID),
    ),
  );
  assert.equal(signal?.requires_manual_review, true);
});

/* ===================================================== crossing businesses */

test("another business's code is not found, and nothing about it leaks", async () => {
  const docs = storeWith();
  // The code exists — it just belongs to somebody else.
  docs.set(referralPaths.codeLookup(CODE), {
    code: CODE,
    merchant_id: OTHER_MERCHANT,
    affiliate_id: 'af9',
    code_id: 'ac9',
  });
  docs.set(referralPaths.code(OTHER_MERCHANT, 'ac9'), {
    id: 'ac9',
    merchant_id: OTHER_MERCHANT,
    affiliate_id: 'af9',
    status: 'ACTIVE',
    starts_at: NOW - DAY,
    expires_at: NOW + DAY,
    usage_count: 0,
    first_visit_only: true,
    benefit_type: 'FIXED_AMOUNT',
    benefit_value: 50,
  });

  const outcome = await commit(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CODE_NOT_FOUND');
  assert.equal(outcome.message, REFERRAL_REASON_MESSAGE.CODE_NOT_FOUND);
  // Not "disabled", not "expired": a distinguishable answer is an oracle for
  // probing another business's codes.
  assert.doesNotMatch(outcome.message, new RegExp(OTHER_MERCHANT));
  assert.doesNotMatch(outcome.message, /af9|ac9/);

  // The other business's code is untouched and nothing was written into it.
  assert.equal(docs.get(referralPaths.code(OTHER_MERCHANT, 'ac9'))?.usage_count, 0);
  assert.deepEqual(docsUnder(docs, OTHER_MERCHANT, 'affiliate_attributions'), []);
  assert.deepEqual(docsUnder(docs, OTHER_MERCHANT, 'affiliate_events'), []);
  assert.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_attributions'), []);
});

/* ================================================== the transaction itself */

test('a failure partway through a referred sale leaves the business exactly as it was', async () => {
  const docs = storeWith();
  const before = snapshot(docs);

  await assert.rejects(
    () => commit(docs, {}, config(), { failAfterWrites: 3 }),
    /injected transaction failure/,
  );

  assert.deepEqual(snapshot(docs), before, 'a partial commit reached the store');

  // And the retry after the rollback is a first commit, not a replay.
  const retry = await commit(docs);
  assert.equal(retry.status, 'committed');
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_rewards').length, 1);
});

test('a failure partway through an offline reconciliation leaves the queue free to retry', async () => {
  const docs = storeWith();
  const before = snapshot(docs);

  const { gateway } = gatewayOver(docs, { failAfterWrites: 2 });
  await assert.rejects(
    () => commitOfflineReferralSale(gateway, offlineInput(), () => config()),
    /injected transaction failure/,
  );

  assert.deepEqual(snapshot(docs), before);

  const retry = await reconcile(docs);
  assert.equal(retry.status, 'committed');
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_attributions').length, 1);
});

/* ================================================= many sales, one backlog */

test('a backlog of offline sales reaches the server once each, and the limit stops the rest', async () => {
  const docs = storeWith({ code: { usage_limit: 3 } });
  // Five customers, five queued sales, one code that only three may use.
  for (let index = 0; index < 5; index++) {
    docs.set(referralPaths.customer(MERCHANT, `c${index}`), {
      id: `c${index}`,
      merchant_id: MERCHANT,
      name: `Cliente ${index}`,
      phone: `+2588412345${String(index).padStart(2, '0')}`,
      confirmed_points: 0,
    });
  }

  const statuses: string[] = [];
  for (let index = 0; index < 5; index++) {
    const outcome = await reconcile(docs, {
      customerId: `c${index}`,
      customerPhoneE164: `+2588412345${String(index).padStart(2, '0')}`,
      localSaleId: `l${index}`,
    });
    statuses.push(outcome.status);
  }

  // Processed in the order the server received them; the later ones lose.
  assert.deepEqual(statuses, [
    'committed',
    'committed',
    'committed',
    'rejected',
    'rejected',
  ]);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 3);
  assert.equal(docsUnder(docs, MERCHANT, 'affiliate_rewards').length, 3);
  // Every one of the five sales is on the books, refused or not.
  assert.equal(docsUnder(docs, MERCHANT, 'sales').length, 5);

  // Replaying the whole backlog changes nothing.
  const afterFirstPass = snapshot(docs);
  for (let index = 0; index < 5; index++) {
    await reconcile(docs, {
      customerId: `c${index}`,
      customerPhoneE164: `+2588412345${String(index).padStart(2, '0')}`,
      localSaleId: `l${index}`,
    });
  }
  assert.deepEqual(snapshot(docs), afterFirstPass);
});

/* ============================================================== no secrets */

test('nothing a scenario writes carries a phone number a person could dial', async () => {
  const docs = storeWith();
  await commit(docs);
  await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON);

  // The customer and affiliate records hold phones by design; every record the
  // referral feature writes about them must not.
  const owned = [
    'affiliate_attributions',
    'affiliate_rewards',
    'affiliate_events',
    'affiliate_fraud_signals',
    'affiliate_outbox',
  ];
  for (const collection of owned) {
    for (const path of docsUnder(docs, MERCHANT, collection)) {
      const serialized = JSON.stringify(docs.get(path));
      assert.doesNotMatch(
        serialized,
        /841234567|840000001/,
        `${path} carries a reachable number`,
      );
      assert.ok(!path.includes('841234567'), `${path} is keyed by a phone number`);
    }
  }
});
