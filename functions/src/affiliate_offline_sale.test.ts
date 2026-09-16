import assert from 'node:assert/strict';
import test from 'node:test';

import { DEFAULT_AFFILIATE_CONFIG, type AffiliateConfig } from './affiliate_contracts.js';
import {
  CLOCK_SKEW_SIGNAL_MS,
  affiliateIds,
  referralIdempotencyKeys,
  referralPhoneHash,
  saleIdempotencyKey,
} from './affiliate_engine.js';
import {
  commitOfflineReferralSale,
  type OfflineReferralSaleInput,
} from './affiliate_offline_sale.js';
import {
  referralBonusLedgerEntryId,
  referralPaths,
  type DocumentData,
  type ReferralSaleGateway,
  type ReferralSaleTransaction,
  type StoredDocument,
  type WriteOperation,
} from './affiliate_sale_commit.js';

/**
 * Reconciling a sale the till already made.
 *
 * Everything here turns on one asymmetry the online commit does not have: the
 * customer has already paid and gone. A refusal cannot un-charge them, and an
 * acceptance cannot refund them. So the properties under test are about money
 * that has already moved:
 *
 *   a refused code keeps its discount and pays the affiliate nothing;
 *   a valid code the till could not price earns the acquisition but no refund;
 *   a POINTS benefit survives either way, because points are a ledger entry.
 *
 * The same fake transaction as `affiliate_sale_commit.test.ts`: it refuses a
 * read after a write and a `create` on an existing document, so a plan that
 * Firestore would reject fails here instead of in production.
 */

const NOW = 1_800_000_000_000;
const MERCHANT = 'm1';
const CODE = 'AFI-ANA-7K2P';
const CUSTOMER = 'c1';
const PHONE = '+258841234567';

type Store = Map<string, DocumentData>;

function gatewayOver(docs: Store): {
  gateway: ReferralSaleGateway;
  applied: WriteOperation[];
} {
  const applied: WriteOperation[] = [];

  const gateway: ReferralSaleGateway = {
    async runTransaction<T>(
      run: (transaction: ReferralSaleTransaction) => Promise<T>,
    ): Promise<T> {
      const staged: WriteOperation[] = [];
      let hasWritten = false;

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
        create: (docPath, data) => {
          hasWritten = true;
          staged.push({ kind: 'create', path: docPath, data });
        },
        merge: (docPath, data) => {
          hasWritten = true;
          staged.push({ kind: 'merge', path: docPath, data });
        },
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

const LINK_ID = affiliateIds.link('af1', MERCHANT);
const ATTRIBUTION_ID = affiliateIds.attribution(MERCHANT, CUSTOMER);
const SALE_ID = affiliateIds.sale('d1', 'l1');
const REWARD_ID = affiliateIds.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE');
const SIGNAL_ID = affiliateIds.fraudSignal(
  MERCHANT,
  'OFFLINE_CODE_REJECTED',
  SALE_ID,
);

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
    withLookup?: boolean;
    extra?: Record<string, DocumentData>;
  } = {},
): Store {
  const docs: Store = new Map();
  docs.set(referralPaths.business(MERCHANT), {
    id: MERCHANT,
    loyalty_config: { points_per_mzn: 100, version: 2 },
  });
  if (overrides.withLookup !== false) {
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
  }
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

function input(
  overrides: Partial<OfflineReferralSaleInput> = {},
): OfflineReferralSaleInput {
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
    offlineBenefitApplied: true,
    appliedBenefit: {
      type: 'FIXED_AMOUNT',
      value: 50,
      discountAmount: 50,
      pointsAwarded: 0,
    },
    localCreatedAt: NOW - 60_000,
    ...overrides,
  };
}

async function reconcile(
  docs: Store,
  overrides: Partial<OfflineReferralSaleInput> = {},
  settings: AffiliateConfig = config(),
) {
  const { gateway } = gatewayOver(docs);
  return commitOfflineReferralSale(gateway, input(overrides), () => settings);
}

/* ------------------------------------------------------- the benefit given */

test('a cached benefit already given is honoured exactly as charged', async () => {
  const docs = storeWith();
  const outcome = await reconcile(docs);

  assert.equal(outcome.status, 'committed');
  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.equal(sale?.amount, 450);
  assert.equal(sale?.gross_amount, 500);
  assert.equal(sale?.referral_benefit_amount, 50);
  assert.equal(sale?.referral_status, 'ATTRIBUTED');
  assert.equal(sale?.referral_source, 'OFFLINE');
  // Points are earned on what the customer paid, exactly as online.
  assert.equal(sale?.points, 4);
  assert.equal(sale?.referral_idempotency_key, saleIdempotencyKey('d1', 'l1'));
});

test('a code changed to points never erases a discount already given', async () => {
  const docs = storeWith({
    code: { benefit_type: 'POINTS', benefit_value: 120 },
  });

  const outcome = await reconcile(docs);

  assert.equal(outcome.status, 'committed');
  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.equal(sale?.amount, 450);
  assert.equal(sale?.gross_amount, 500);
  assert.equal(sale?.referral_benefit_type, 'FIXED_AMOUNT');
  assert.equal(sale?.referral_benefit_value, 50);
  assert.equal(sale?.referral_benefit_amount, 50);
  assert.equal(sale?.points, 4);
  assert.equal(
    docs.has(
      referralPaths.ledgerEntry(
        MERCHANT,
        referralBonusLedgerEntryId(SALE_ID),
      ),
    ),
    false,
    'the customer must not receive both the stale discount and new points',
  );
});

test('the acquisition, the reward and the usage count move together', async () => {
  const docs = storeWith();
  await reconcile(docs);

  const attribution = docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
  assert.equal(attribution?.status, 'CONFIRMED');
  assert.equal(
    attribution?.idempotency_key,
    referralIdempotencyKeys.attribution(MERCHANT, referralPhoneHash(PHONE)),
  );
  const reward = docs.get(referralPaths.reward(MERCHANT, REWARD_ID));
  assert.equal(reward?.status, 'PENDING');
  assert.equal(reward?.value, 100);
  assert.equal(
    reward?.idempotency_key,
    referralIdempotencyKeys.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE'),
  );
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
});

test('a key never carries the number it identifies', () => {
  const key = referralIdempotencyKeys.attribution(
    MERCHANT,
    referralPhoneHash(PHONE),
  );
  assert.ok(!key.includes('841234567'));
  assert.ok(!key.includes(PHONE));
});

/* --------------------------------------------------------------- refusals */

test('a refused code keeps the sale and the discount and pays nobody', async () => {
  const docs = storeWith({ code: { expires_at: NOW - 1 } });
  const outcome = await reconcile(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CODE_EXPIRED');

  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  // The discount stands: reversing it is an invoice sent to somebody who left
  // the shop an hour ago.
  assert.equal(sale?.amount, 450);
  assert.equal(sale?.referral_benefit_amount, 50);
  assert.equal(sale?.referral_status, 'REJECTED');
  assert.equal(sale?.referral_rejection_reason, 'CODE_EXPIRED');

  const attribution = docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
  assert.equal(attribution?.status, 'REJECTED');
  assert.equal(attribution?.rejection_reason, 'CODE_EXPIRED');
  assert.equal(docs.has(referralPaths.reward(MERCHANT, REWARD_ID)), false);
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
});

test('a refusal that cost the business money raises a HIGH signal', async () => {
  const docs = storeWith({ code: { status: 'DISABLED' } });
  await reconcile(docs);

  const signal = docs.get(referralPaths.fraudSignal(MERCHANT, SIGNAL_ID));
  assert.equal(signal?.signal_type, 'OFFLINE_CODE_REJECTED');
  assert.equal(signal?.severity, 'HIGH');
  assert.equal((signal?.metadata as DocumentData).benefit_retained, true);
  assert.equal((signal?.metadata as DocumentData).retained_amount, 50);
});

test('a refusal that cost nothing is still recorded, at lower severity', async () => {
  const docs = storeWith({ code: { status: 'DISABLED' } });
  await reconcile(docs, {
    offlineBenefitApplied: false,
    appliedBenefit: null,
  });

  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.equal(sale?.amount, 500);
  assert.equal(sale?.referral_benefit_amount, null);
  const signal = docs.get(referralPaths.fraudSignal(MERCHANT, SIGNAL_ID));
  assert.equal(signal?.severity, 'MEDIUM');
});

test('a refusal never overwrites an acquisition another affiliate already has', async () => {
  const docs = storeWith({
    // With `firstVisitOnly` off the validation reaches the clause that is
    // actually about this: the customer belongs to somebody already.
    code: { first_visit_only: false },
    extra: {
      [referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)]: {
        id: ATTRIBUTION_ID,
        merchant_id: MERCHANT,
        affiliate_id: 'af-other',
        affiliate_code_id: 'ac-other',
        customer_id: CUSTOMER,
        status: 'CONFIRMED',
      },
    },
  });

  const outcome = await reconcile(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  assert.equal(outcome.reason, 'CUSTOMER_ALREADY_REFERRED');
  // Somebody else's customer is still theirs.
  const attribution = docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
  assert.equal(attribution?.affiliate_id, 'af-other');
  assert.equal(attribution?.status, 'CONFIRMED');
});

/* ------------------------------------------------------- the uncached code */

test('a valid code the till could not price earns the acquisition, not a refund', async () => {
  const docs = storeWith();
  const outcome = await reconcile(docs, {
    offlineBenefitApplied: false,
    appliedBenefit: null,
  });

  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;
  assert.equal(outcome.result.referral.monetary_benefit_applied, false);
  assert.equal(outcome.result.referral.retroactive_discount_applied, false);

  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  // Charged in full, and it stays charged in full: money is not refunded by a
  // sync.
  assert.equal(sale?.amount, 500);
  assert.equal(sale?.referral_benefit_amount, 0);
  assert.equal(sale?.referral_status, 'ATTRIBUTED');
  // The affiliate is still credited: the acquisition happened.
  assert.equal(
    docs.get(referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status,
    'CONFIRMED',
  );
  assert.ok(docs.has(referralPaths.reward(MERCHANT, REWARD_ID)));
});

test('a POINTS benefit is credited even when the till could not price it', async () => {
  const docs = storeWith({
    code: { benefit_type: 'POINTS', benefit_value: 120 },
  });
  const outcome = await reconcile(docs, {
    offlineBenefitApplied: false,
    appliedBenefit: null,
  });

  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;
  assert.equal(outcome.result.referral.points_benefit_credited, true);

  // Points are an entry in a ledger, and adding one costs the customer nothing
  // they have already paid.
  const ledger = docs.get(
    referralPaths.ledgerEntry(MERCHANT, referralBonusLedgerEntryId(SALE_ID)),
  );
  assert.equal(ledger?.points_delta, 120);
  assert.equal(ledger?.entry_type, 'REFERRAL_BONUS');
  assert.equal(docs.get(referralPaths.sale(MERCHANT, SALE_ID))?.amount, 500);
});

test('a discount larger than the bill is capped, never negative', async () => {
  const docs = storeWith();
  await reconcile(docs, {
    grossAmount: 30,
    appliedBenefit: {
      type: 'FIXED_AMOUNT',
      value: 50,
      discountAmount: 50,
      pointsAwarded: 0,
    },
  });

  const sale = docs.get(referralPaths.sale(MERCHANT, SALE_ID));
  assert.ok((sale?.amount as number) >= 0);
});

/* --------------------------------------------------------- ordering, replay */

test('a competing sale that finds the limit reached is refused', async () => {
  const docs = storeWith({ code: { usage_limit: 1, usage_count: 1 } });
  const outcome = await reconcile(docs);

  assert.equal(outcome.status, 'rejected');
  if (outcome.status !== 'rejected') return;
  // The earliest qualifying sale to reach the server spent the use; a later
  // arrival is told so.
  assert.equal(outcome.reason, 'CODE_USAGE_LIMIT_REACHED');
  assert.equal(docs.get(referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
});

test('replaying the same reconciliation writes nothing new', async () => {
  const docs = storeWith();
  await reconcile(docs);
  const sizeAfterFirst = docs.size;

  const { gateway, applied } = gatewayOver(docs);
  const outcome = await commitOfflineReferralSale(
    gateway,
    input(),
    () => config(),
  );

  assert.equal(outcome.status, 'replayed');
  assert.deepEqual(applied, []);
  assert.equal(docs.size, sizeAfterFirst);
});

test('the same local id for a different sale is a conflict, not a replay', async () => {
  const docs = storeWith();
  await reconcile(docs);

  const outcome = await reconcile(docs, { grossAmount: 900 });
  assert.equal(outcome.status, 'conflict');
});

test('a customer the server has not seen yet is deferred, not refused', async () => {
  const docs = storeWith();
  docs.delete(referralPaths.customer(MERCHANT, CUSTOMER));

  const outcome = await reconcile(docs);

  // The customer's own create is usually right in front of this in the queue.
  // Refusing here would throw away the sale for being early.
  assert.equal(outcome.status, 'deferred');
  assert.equal(docs.has(referralPaths.sale(MERCHANT, SALE_ID)), false);
});

/* ------------------------------------------------------------- clock skew */

test('a device whose clock is a day out still has its sale processed', async () => {
  const docs = storeWith();
  const outcome = await reconcile(docs, {
    localCreatedAt: NOW - CLOCK_SKEW_SIGNAL_MS - 60_000,
  });

  assert.equal(outcome.status, 'committed');
  if (outcome.status !== 'committed') return;
  assert.ok(outcome.result.clock_skew_ms > CLOCK_SKEW_SIGNAL_MS);

  // Recorded on the event so a run of them is visible, never used to refuse a
  // real purchase.
  const eventId = affiliateIds.event(MERCHANT, 'REFERRAL_ATTRIBUTED', SALE_ID);
  const event = docs.get(referralPaths.event(MERCHANT, eventId));
  assert.equal((event?.metadata as DocumentData).clock_skew_exceeded, true);
  // The sale keeps the till's own timestamp, which is what the receipt says.
  assert.equal(
    docs.get(referralPaths.sale(MERCHANT, SALE_ID))?.created_at,
    NOW - CLOCK_SKEW_SIGNAL_MS - 60_000,
  );
});

/* ------------------------------------------------------------- sale items */

test('sale items are written once, under deterministic ids', async () => {
  const docs = storeWith();
  await reconcile(docs, {
    items: [
      {
        id: 'rsi_1',
        merchantItemId: 'mi1',
        nameSnapshot: 'Corte',
        typeSnapshot: 'SERVICE',
        quantity: 1,
        unitPrice: 500,
        subtotal: 500,
      },
    ],
  });

  const item = docs.get(referralPaths.saleItem(MERCHANT, 'rsi_1'));
  assert.equal(item?.sale_id, SALE_ID);
  assert.equal(item?.quantity, 1);
});
