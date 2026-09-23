import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { DEFAULT_AFFILIATE_CONFIG, type AffiliateConfig } from './affiliate_contracts.js';
import { affiliateIds, saleIdempotencyKey } from './affiliate_engine.js';
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
 * The referred sale, checked without an emulator.
 *
 * The commit is one transaction with seven writes in it, and the property that
 * matters — all of them or none — is not something a unit test of any single
 * step can see. So the transaction is a port, and this file implements a fake
 * one that behaves the way Firestore does in the two ways that bite: it
 * refuses a read issued after a write, and it refuses a `create` on a document
 * that already exists. A commit path that would be rejected in production
 * fails here instead.
 *
 * The fake can also be told to fail partway through. That is the test for
 * atomicity: the plan is staged, the failure lands, and the store is checked
 * to be exactly as it was.
 */

const NOW = 1_800_000_000_000;
const MERCHANT = 'm1';
const CODE = 'AFI-ANA-7K2P';
const CUSTOMER = 'c1';
const PHONE = '+258841234567';

/* ------------------------------------------------------------- the fake db */

type Store = Map<string, DocumentData>;

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

/* --------------------------------------------------------------- fixtures */

const LINK_ID = affiliateIds.link('af1', MERCHANT);
const ATTRIBUTION_ID = affiliateIds.attribution(MERCHANT, CUSTOMER);
const SALE_ID = affiliateIds.sale('d1', 'l1');
const FIRST_REWARD_ID = affiliateIds.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE');
const RETURN_REWARD_ID = affiliateIds.reward(ATTRIBUTION_ID, 'CUSTOMER_RETURN');

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
    lookupMerchantId?: string;
    extra?: Record<string, DocumentData>;
  } = {},
): Store {
  const docs: Store = new Map();
  docs.set(referralPaths.business(MERCHANT), {
    id: MERCHANT,
    loyalty_config: { points_per_mzn: 100, version: 2 },
  });
  docs.set(referralPaths.codeLookup(CODE), {
    code: CODE,
    merchant_id: overrides.lookupMerchantId ?? MERCHANT,
    affiliate_id: 'af1',
    code_id: 'ac1',
  });
  docs.set(referralPaths.code(MERCHANT, 'ac1'), {
    id: 'ac1',
    merchant_id: MERCHANT,
    affiliate_id: 'af1',
    status: 'ACTIVE',
    starts_at: NOW - 86_400_000,
    expires_at: NOW + 86_400_000,
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
    phone: PHONE,
    confirmed_points: 0,
    ...overrides.customer,
  });
  for (const [docPath, data] of Object.entries(overrides.extra ?? {})) {
    docs.set(docPath, data);
  }
  return docs;
}

function input(overrides: Partial<ReferralSaleCommitInput> = {}): ReferralSaleCommitInput {
  return {
    merchantId: MERCHANT,
    deviceId: 'd1',
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

async function commit(
  docs: Store,
  overrides: Partial<ReferralSaleCommitInput> = {},
  settings: AffiliateConfig = config(),
  options: { failAfterWrites?: number } = {},
) {
  const { gateway } = gatewayOver(docs, options);
  return commitReferralSale(gateway, input(overrides), () => settings);
}

/* ----------------------------------------------------------- happy paths */

test('a fixed discount is applied, attributed and rewarded in one transaction', async () => {
  const docs = storeWith();
  const outcome = await commit(docs);

  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;

  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.ok(sale, 'the sale was not written');
  // The customer pays 450 and earns points on what they paid, not on the
  // pre-discount amount.
  assert.equal(sale.amount, 450);
  assert.equal(sale.gross_amount, 500);
  assert.equal(sale.points, 4);
  assert.equal(sale.referral_benefit_type, 'FIXED_AMOUNT');
  assert.equal(sale.referral_benefit_amount, 50);
  assert.equal(sale.affiliate_code_id, 'ac1');
  assert.equal(sale.referral_status, 'ATTRIBUTED');
  assert.equal(sale.cancellation_status, 'ACTIVE');
  assert.equal(
    sale.referral_idempotency_key,
    saleIdempotencyKey('d1', 'l1'),
  );

  const attribution = docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
  assert.equal(attribution?.status, 'CONFIRMED');
  assert.equal(attribution?.first_sale_id, SALE_ID);

  const reward = docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID));
  assert.equal(reward?.status, 'PENDING');
  assert.equal(reward?.value, 100);
  assert.equal(reward?.trigger_sale_id, SALE_ID);

  // The code was spent exactly once.
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);

  const attributedEvent = affiliateIds.event(MERCHANT, 'REFERRAL_ATTRIBUTED', SALE_ID);
  assert.ok(docs.has(referralPaths.event(MERCHANT, attributedEvent)));
  const rewardEvent = affiliateIds.event(MERCHANT, 'AFFILIATE_REWARD_CREATED', SALE_ID);
  assert.ok(docs.has(referralPaths.event(MERCHANT, rewardEvent)));

  // The message is queued in the transaction and sent by a worker later.
  const outbox = affiliateIds.outbox(MERCHANT, 'affiliate_new_customer', SALE_ID);
  assert.equal(docs.get(referralPaths.outbox(MERCHANT, outbox))?.status, 'QUEUED');

  assert.equal(outcome.result.referral.attribution_id, ATTRIBUTION_ID);
  assert.equal(outcome.result.referral.reward?.status, 'PENDING');
  assert.equal(outcome.result.replayed, false);
});

test('a percentage is taken in centavos and never rounds in the code favour', async () => {
  const docs = storeWith({
    code: { benefit_type: 'PERCENTAGE', benefit_value: 10 },
  });
  const outcome = await commit(docs, { grossAmount: 99.99 });

  assert.equal(outcome.status, 'committed');
  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  // 10% of 99.99 is 9.999; rounding up would give away a centavo per sale.
  assert.equal(sale?.referral_benefit_amount, 9.99);
  assert.equal(sale?.amount, 90);
  assert.equal(sale?.gross_amount, 99.99);
});

test('a points benefit adds a ledger entry and leaves the price alone', async () => {
  const docs = storeWith({
    code: { benefit_type: 'POINTS', benefit_value: 25 },
    customer: { confirmed_points: 7 },
  });
  const outcome = await commit(docs);

  assert.equal(outcome.status, 'committed');
  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.equal(sale?.amount, 500, 'a points benefit is not a discount');
  assert.equal(sale?.referral_benefit_amount, 25);

  const entry = docs.get(
    referralPaths.ledgerEntry(MERCHANT, referralBonusLedgerEntryId(SALE_ID)),
  );
  assert.ok(entry, 'the promotional points were not written to the ledger');
  assert.equal(entry.entry_type, 'REFERRAL_BONUS');
  assert.equal(entry.source_type, 'referral');
  assert.equal(entry.source_id, SALE_ID);
  assert.equal(entry.points_delta, 25);
  assert.equal(entry.balance_after, 32);
  // Just before the sale, so the sale's own entry stays the newest one.
  assert.ok((entry.occurred_at as number) < NOW);
});

test('an existing customer under an open code gets the benefit and nothing else', async () => {
  const docs = storeWith({
    code: { first_visit_only: false },
    extra: {
      [`${referralPaths.sales(MERCHANT)}/old-sale`]: {
        id: 'old-sale',
        customer_id: CUSTOMER,
        amount: 200,
        cancellation_status: 'ACTIVE',
      },
    },
  });

  test('a prior rejected attribution is confirmed by a later valid acquisition', async () => {
    const attributionPath = referralPaths.attribution(MERCHANT, ATTRIBUTION_ID);
    const docs = storeWith({
      extra: {
        [attributionPath]: {
          id: ATTRIBUTION_ID,
          merchant_id: MERCHANT,
          affiliate_id: 'af-old',
          affiliate_code_id: 'old-code',
          customer_id: CUSTOMER,
          first_sale_id: 'old-sale',
          status: 'REJECTED',
          rejection_reason: 'CODE_EXPIRED',
          attributed_at: NOW - 1000,
          created_at: NOW - 1000,
          updated_at: NOW - 1000,
        },
      },
    });

    const outcome = await commit(docs);

    assert.equal(outcome.status, 'committed');
    const attribution = docs.get(attributionPath);
    assert.equal(attribution?.status, 'CONFIRMED');
    assert.equal(attribution?.affiliate_id, 'af1');
    assert.equal(attribution?.affiliate_code_id, 'ac1');
    assert.equal(attribution?.first_sale_id, SALE_ID);
    assert.equal(attribution?.rejection_reason, null);
    assert.equal(attribution?.created_at, NOW - 1000);
    assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    assert.equal(
      docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status,
      'PENDING',
    );
  });

  const outcome = await commit(docs);

  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;
  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.equal(sale?.amount, 450, 'the benefit was not applied');
  assert.equal(sale?.referral_status, 'PENDING');
  // No acquisition happened, so nothing is owed and the code is not spent.
  assert.equal(docs.has(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)), false);
  assert.equal(docs.has(referralPaths.reward(MERCHANT, FIRST_REWARD_ID)), false);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
  assert.equal(outcome.result.referral.attribution_id, null);
  assert.equal(outcome.result.referral.reward, null);
});

/* -------------------------------------------------------------- refusals */

test('a code that expired since the preview is refused, and nothing is written', async () => {
  const docs = storeWith({ code: { expires_at: NOW - 1 } });
  const before = new Set(docs.keys());

  const outcome = await commit(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CODE_EXPIRED');
  assert.equal(typeof outcome.message, 'string');
  assert.equal(docs.has(referralPaths.sale(MERCHANT, SALE_ID)), false);
  assert.equal(docs.has(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)), false);

  // The refusal itself is recorded, and it is the only thing written.
  const added = [...docs.keys()].filter((key) => !before.has(key));
  assert.equal(added.length, 1);
  assert.ok(added[0].includes('affiliate_events'));
});

test('an existing customer under a first-visit code is refused by eligibility', async () => {
  const docs = storeWith({
    extra: {
      [`${referralPaths.sales(MERCHANT)}/old-sale`]: {
        id: 'old-sale',
        customer_id: CUSTOMER,
        amount: 200,
      },
    },
  });

  const outcome = await commit(docs);
  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CUSTOMER_NOT_ELIGIBLE');
});

test("another business's code is not found, and its documents are never read", async () => {
  const docs = storeWith({ lookupMerchantId: 'm2' });
  const outcome = await commit(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  // Not AFFILIATE_INACTIVE, not CODE_DISABLED: a distinguishable answer is a
  // way to enumerate another business's codes.
  assert.equal(outcome.reason, 'CODE_NOT_FOUND');
  assert.equal(docs.has(referralPaths.sale(MERCHANT, SALE_ID)), false);
});

test('an affiliate selling to themselves is refused', async () => {
  const docs = storeWith({ affiliate: { phone_e164: PHONE } });
  const outcome = await commit(docs);
  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'SELF_REFERRAL_NOT_ALLOWED');
});

test('a customer the server has never seen cannot be attributed anything', async () => {
  const docs = storeWith();
  docs.delete(referralPaths.customer(MERCHANT, CUSTOMER));

  const outcome = await commit(docs);
  assert.equal(outcome.status, 'customer_not_found');
  assert.equal(docs.has(referralPaths.sale(MERCHANT, SALE_ID)), false);
});

/* ---------------------------------------------------------------- replay */

test('the same request twice makes one sale, one attribution and one reward', async () => {
  const docs = storeWith();
  const first = await commit(docs);
  const second = await commit(docs);

  assert.equal(first.status, 'committed');
  assert.equal(second.status, 'replayed');
  if (second.status !== 'replayed') return;

  const sales = [...docs.keys()].filter((key) =>
    key.startsWith(`${referralPaths.sales(MERCHANT)}/`));
  assert.deepEqual(sales, [referralPaths.sale(MERCHANT, SALE_ID)]);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
  assert.equal(second.result.replayed, true);
  assert.equal(second.result.referral.attribution_id, ATTRIBUTION_ID);
  assert.equal(second.result.referral.reward?.id, FIRST_REWARD_ID);

  const rewards = [...docs.keys()].filter((key) =>
    key.includes('affiliate_rewards/'));
  assert.equal(rewards.length, 1);
});

test('reusing a local sale id for a different sale is a conflict, not a sale', async () => {
  const docs = storeWith();
  await commit(docs);

  const outcome = await commit(docs, { grossAmount: 900 });

  assert.equal(outcome.status, 'conflict');
  // The committed sale is untouched.
  assert.equal(docs.get(referralPaths.sale(MERCHANT, SALE_ID))?.gross_amount, 500);
});

test('changing an item under the same local sale id is a conflict', async () => {
  const docs = storeWith();
  const original = {
    id: 'rsi-1',
    merchantItemId: 'service-1',
    nameSnapshot: 'Corte',
    typeSnapshot: 'SERVICE',
    quantity: 1,
    unitPrice: 500,
    subtotal: 500,
  };
  await commit(docs, { items: [original] });

  const outcome = await commit(docs, {
    items: [
      {
        ...original,
        merchantItemId: 'service-2',
        nameSnapshot: 'Barba',
      },
    ],
  });

  assert.equal(outcome.status, 'conflict');
  assert.equal(
    docs.get(referralPaths.saleItem(MERCHANT, original.id))
      ?.merchant_item_id,
    'service-1',
  );
});

/* ------------------------------------------------------------- atomicity */

test('a failure partway through leaves nothing behind', async () => {
  const docs = storeWith();
  const before = new Map([...docs].map(([key, value]) => [key, JSON.stringify(value)]));

  await assert.rejects(
    () => commit(docs, {}, config(), { failAfterWrites: 2 }),
    /injected transaction failure/,
  );

  assert.deepEqual(
    new Map([...docs].map(([key, value]) => [key, JSON.stringify(value)])),
    before,
    'a partial commit reached the store',
  );
  assert.equal(docs.has(referralPaths.sale(MERCHANT, SALE_ID)), false);
  assert.equal(docs.has(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)), false);
});

test('the sale is written before anything that depends on it', async () => {
  const docs = storeWith();
  const { gateway, applied } = gatewayOver(docs);
  await commitReferralSale(gateway, input(), () => config());

  const paths = applied.map((operation) => operation.path);
  assert.equal(paths[0], referralPaths.sale(MERCHANT, SALE_ID));
  assert.ok(paths.includes(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)));
  assert.ok(paths.includes(referralPaths.reward(MERCHANT, FIRST_REWARD_ID)));
  assert.ok(paths.includes(referralPaths.code(MERCHANT, 'ac1')));
});

/* ---------------------------------------------------------- cancellation */

async function cancel(docs: Store, saleId = SALE_ID, merchantId = MERCHANT) {
  const { gateway } = gatewayOver(docs);
  return reverseReferralSale(gateway, {
    merchantId,
    saleId,
    cancelledAt: NOW + 1000,
    actorId: 'u1',
  });
}

test('cancelling a referred sale cancels the acquisition and the unpaid reward once', async () => {
  const docs = storeWith();
  await commit(docs);

  const first = await cancel(docs);
  assert.equal(first.status, 'reversed');
  assert.equal(first.attribution_cancelled, true);
  assert.deepEqual(first.rewards_cancelled, [FIRST_REWARD_ID]);

  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CANCELLED',
  );
  assert.equal(
    docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status,
    'CANCELLED',
  );
  // The code was used. Cancelling the sale does not give the use back.
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);

  const second = await cancel(docs);
  assert.equal(second.status, 'already_reversed');
  assert.deepEqual(second.rewards_cancelled, []);
});

test('a reward already paid is left alone and raised for a person', async () => {
  const docs = storeWith();
  await commit(docs);
  docs.set(referralPaths.reward(MERCHANT, FIRST_REWARD_ID), {
    ...docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID)),
    status: 'PAID',
    paid_at: NOW + 1,
  });

  const outcome = await cancel(docs);

  assert.deepEqual(outcome.rewards_cancelled, []);
  assert.deepEqual(outcome.rewards_needing_review, [FIRST_REWARD_ID]);
  assert.equal(
    docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status,
    'PAID',
    'points already handed over were unpaid by a status change',
  );
  const signalId = affiliateIds.fraudSignal(
    MERCHANT,
    'PAID_REWARD_SALE_CANCELLED',
    FIRST_REWARD_ID,
  );
  assert.equal(
    docs.get(referralPaths.fraudSignal(MERCHANT, signalId))?.requires_manual_review,
    true,
  );
});

test('a sale with no code cancels without touching anything of the referral', async () => {
  const docs = storeWith({
    extra: {
      [referralPaths.sale(MERCHANT, 'plain')]: {
        id: 'plain',
        merchant_id: MERCHANT,
        customer_id: CUSTOMER,
        amount: 200,
      },
    },
  });

  const outcome = await cancel(docs, 'plain');
  assert.equal(outcome.status, 'not_referred');
  assert.equal(outcome.attribution_cancelled, false);
});

test('a cancellation cannot reach a sale of another business', async () => {
  const docs = storeWith();
  await commit(docs);

  // Same sale id, asked for as another business: the path does not resolve.
  const outcome = await cancel(docs, SALE_ID, 'm2');
  assert.equal(outcome.status, 'not_referred');
  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CONFIRMED',
  );
});

/* --------------------------------------------------------------- returns */

async function recordReturn(
  docs: Store,
  saleId: string,
  occurredAt: number,
  settings: AffiliateConfig,
) {
  const { gateway } = gatewayOver(docs);
  return recordReferredCustomerReturn(
    gateway,
    {
      merchantId: MERCHANT,
      saleId,
      customerId: CUSTOMER,
      amount: 300,
      occurredAt,
    },
    settings,
  );
}

const RETURNS_ON = config({
  returnRewardEnabled: true,
  returnRewardPoints: 40,
  returnWindowDays: 30,
});

test('a referred customer coming back is recorded once and rewarded once', async () => {
  const docs = storeWith();
  await commit(docs);

  const first = await recordReturn(docs, 'sale-2', NOW + 86_400_000, RETURNS_ON);
  const second = await recordReturn(docs, 'sale-2', NOW + 86_400_000, RETURNS_ON);

  assert.equal(first.status, 'recorded');
  assert.equal(second.status, 'already_recorded');

  const reward = docs.get(referralPaths.reward(MERCHANT, RETURN_REWARD_ID));
  assert.equal(reward?.value, 40);
  assert.equal(reward?.status, 'PENDING');
  assert.equal(reward?.trigger_sale_id, 'sale-2');

  const eventId = affiliateIds.event(MERCHANT, 'REFERRED_CUSTOMER_RETURNED', 'sale-2');
  assert.ok(docs.has(referralPaths.event(MERCHANT, eventId)));
});

test('the sale that made the attribution is not a return', async () => {
  const docs = storeWith();
  await commit(docs);

  const outcome = await recordReturn(docs, SALE_ID, NOW, RETURNS_ON);
  assert.equal(outcome.status, 'first_sale');
  assert.equal(docs.has(referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
});

test('a return outside the window is recorded but earns nothing', async () => {
  const docs = storeWith();
  await commit(docs);

  const outcome = await recordReturn(
    docs,
    'sale-late',
    NOW + 31 * 86_400_000,
    RETURNS_ON,
  );

  assert.equal(outcome.status, 'out_of_window');
  assert.equal(docs.has(referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
  const eventId = affiliateIds.event(MERCHANT, 'REFERRED_CUSTOMER_RETURNED', 'sale-late');
  assert.ok(
    docs.has(referralPaths.event(MERCHANT, eventId)),
    'the visit still happened and is still history',
  );
});

test('a customer nobody referred triggers nothing on a second sale', async () => {
  const docs = storeWith();
  const outcome = await recordReturn(docs, 'sale-2', NOW, RETURNS_ON);
  assert.equal(outcome.status, 'not_referred');
});

test('a retriggered return writes one event, one reward and one message', async () => {
  // The hook hangs off the ordinary sale write, and Firestore fires that
  // trigger at least once — sometimes more. Every document it writes is keyed
  // by the fact rather than by the firing, so the second one adds nothing.
  const docs = storeWith();
  await commit(docs);

  const eventId = affiliateIds.event(MERCHANT, 'REFERRED_CUSTOMER_RETURNED', 'sale-2');
  const rewardEventId = affiliateIds.event(
    MERCHANT,
    'AFFILIATE_REWARD_CREATED',
    RETURN_REWARD_ID,
  );
  const outboxId = affiliateIds.outbox(MERCHANT, 'affiliate_customer_returned', 'sale-2');

  const writes: WriteOperation[] = [];
  for (let firing = 0; firing < 3; firing++) {
    const { gateway, applied } = gatewayOver(docs);
    await recordReferredCustomerReturn(
      gateway,
      {
        merchantId: MERCHANT,
        saleId: 'sale-2',
        customerId: CUSTOMER,
        amount: 300,
        occurredAt: NOW + 86_400_000,
      },
      RETURNS_ON,
    );
    writes.push(...applied);
  }

  const created = (docPath: string) =>
    writes.filter((write) => write.kind === 'create' && write.path === docPath).length;

  assert.equal(created(referralPaths.event(MERCHANT, eventId)), 1, 'return event');
  assert.equal(created(referralPaths.event(MERCHANT, rewardEventId)), 1, 'reward event');
  assert.equal(created(referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), 1, 'reward');
  assert.equal(created(referralPaths.outbox(MERCHANT, outboxId)), 1, 'queued message');
});

test('a queued message names the reward it is about, not a frozen status', async () => {
  // The worker re-reads the reward at delivery time, so a merchant who
  // approves in the meantime is quoted correctly rather than as still
  // deciding. That is only possible if the row says which reward it means.
  const docs = storeWith();
  await commit(docs);
  await recordReturn(docs, 'sale-2', NOW + 86_400_000, RETURNS_ON);

  const firstSale = docs.get(
    referralPaths.outbox(
      MERCHANT,
      affiliateIds.outbox(MERCHANT, 'affiliate_new_customer', SALE_ID),
    ),
  );
  const returned = docs.get(
    referralPaths.outbox(
      MERCHANT,
      affiliateIds.outbox(MERCHANT, 'affiliate_customer_returned', 'sale-2'),
    ),
  );

  assert.equal(
    (firstSale?.payload as DocumentData | undefined)?.reward_id,
    FIRST_REWARD_ID,
  );
  assert.equal(
    (returned?.payload as DocumentData | undefined)?.reward_id,
    RETURN_REWARD_ID,
  );
});

test('cancelling a return sale cancels its reward and leaves the acquisition', async () => {
  const docs = storeWith();
  await commit(docs);
  await recordReturn(docs, 'sale-2', NOW + 86_400_000, RETURNS_ON);
  docs.set(referralPaths.sale(MERCHANT, 'sale-2'), {
    id: 'sale-2',
    merchant_id: MERCHANT,
    customer_id: CUSTOMER,
    amount: 300,
    affiliate_code_id: 'ac1',
    affiliate_id: 'af1',
  });

  const outcome = await cancel(docs, 'sale-2');

  assert.equal(outcome.attribution_cancelled, false);
  assert.deepEqual(outcome.rewards_cancelled, [RETURN_REWARD_ID]);
  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CONFIRMED',
  );
  assert.equal(
    docs.get(referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status,
    'PENDING',
  );
});

/* ------------------------------------------------- source-level obligations */

const COMMIT_SOURCE = readFileSync(
  path.join(__dirname, '..', 'src', 'affiliate_sale_commit.ts'),
  'utf8',
);

test('the commit re-runs the validation instead of trusting the preview', () => {
  assert.ok(
    COMMIT_SOURCE.includes('validateReferral('),
    'the sale commit no longer runs the shared validation',
  );
  assert.ok(
    COMMIT_SOURCE.includes('saleAmount: input.grossAmount'),
    'the commit validates against something other than the real sale amount',
  );
});

test('no value a client could send decides what anything is worth', () => {
  // The benefit comes off the code, the reward off the settings, the points off
  // the business's loyalty config. A request field named like any of them would
  // be a way to price your own discount.
  for (const forbidden of [
    'payload.benefit',
    'input.benefitValue',
    'input.rewardValue',
    'input.pointsAwarded',
    'input.affiliateId',
  ]) {
    assert.ok(
      !COMMIT_SOURCE.includes(forbidden),
      `${forbidden} is read from the request`,
    );
  }
  assert.ok(COMMIT_SOURCE.includes('calculateBenefit(code, input.grossAmount)'));
  assert.ok(COMMIT_SOURCE.includes('planFirstSaleReward(config)'));
});

test('no phone number reaches an id, an event or a stored document', () => {
  const stored = COMMIT_SOURCE.split('\n').filter((line) => {
    const text = line.replace(/\r$/, '').trim();
    if (text.startsWith('*') || text.startsWith('//') || text.startsWith('/*')) return false;
    return /phone/i.test(text);
  });
  for (const line of stored) {
    assert.ok(
      /phoneFingerprint|customerPhoneE164|phoneAlreadyKnown|phoneMatchCount|phoneE164|'phone'/.test(line),
      `a phone is used in an unreviewed way: ${line.trim()}`,
    );
  }
});

test('the usage count is only ever increased', () => {
  assert.ok(COMMIT_SOURCE.includes('usage_count: code.usageCount + 1'));
  assert.ok(
    !/usage_count:\s*[^+\n]*-\s*1/.test(COMMIT_SOURCE),
    'something decrements the usage count',
  );
});
