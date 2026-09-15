import { createHash } from 'crypto';

import {
  REFERRAL_REASON_MESSAGE,
  type AffiliateConfig,
  type AffiliateEventType,
  type AttributionStatus,
  type BenefitType,
  type ReferralReason,
  type RewardStatus,
} from './affiliate_contracts.js';
import {
  affiliateIds,
  calculateBenefit,
  isNewCustomer,
  isWithinReturnWindow,
  normalizeAffiliateCode,
  planFirstSaleReward,
  planReturnReward,
  referralRequestFingerprint,
  rewardsAffectedByCancellation,
  saleIdempotencyKey,
  validateReferral,
  type CalculatedBenefit,
  type ReferralCodeSnapshot,
} from './affiliate_engine.js';

/**
 * The sale side of the referral feature: one transaction, decided in advance.
 *
 * A referred sale is seven facts that are only true together — the sale, the
 * customer's benefit, the acquisition, the affiliate's reward, the code's
 * usage count, the history and the messages that follow. Writing six of them
 * is worse than writing none: a reward with no sale behind it is money owed
 * for nothing, and a sale with no attribution is an acquisition the affiliate
 * never gets paid for. So they are one transaction, and this file is the only
 * place that knows how to build it.
 *
 * It is written in three parts, in the order Firestore forces:
 *
 *   `readReferralSaleFacts` does every read, including the queries, before
 *   anything is written. A transaction that queries after a write is rejected,
 *   and a helper that reads outside the transaction reads a value nobody is
 *   holding — the check would pass and the write would race.
 *
 *   `planReferralSaleCommit` is pure. Given the facts it returns the exact
 *   list of documents to write, or a refusal. No I/O, no clock, no Firestore:
 *   the whole decision is testable without an emulator, and the plan can be
 *   inspected — which is how "all seven or none" becomes an assertion rather
 *   than a hope.
 *
 *   `applyReferralSalePlan` writes the plan and nothing else.
 *
 * Nothing here trusts the preview. §5.5 requires the commit to re-run every
 * check against the real sale, so `validateReferral` runs again on what the
 * transaction just read — the same function the preview called, against the
 * current code, affiliate, link, customer and the real gross amount.
 *
 * And nothing here takes a value from the caller. The benefit comes off the
 * code, the reward off the business's settings, the loyalty points off the
 * business's loyalty config. The request says what was sold and to whom; the
 * server says what it is worth.
 */

/* ------------------------------------------------------------------- ports */

export type DocumentData = Record<string, unknown>;

export type StoredDocument = { id: string; data: DocumentData };

/** Reads. Every one of them happens before the first write. */
export interface ReferralSaleReader {
  getDoc(path: string): Promise<DocumentData | null>;
  queryDocs(
    collectionPath: string,
    field: string,
    value: string,
    limit: number,
  ): Promise<StoredDocument[]>;
}

/** Writes. `create` fails if the document exists, which is the point. */
export interface ReferralSaleWriter {
  create(path: string, data: DocumentData): void;
  merge(path: string, data: DocumentData): void;
}

export type ReferralSaleTransaction = ReferralSaleReader & ReferralSaleWriter;

export interface ReferralSaleGateway {
  runTransaction<T>(
    run: (transaction: ReferralSaleTransaction) => Promise<T>,
  ): Promise<T>;
}

/* ------------------------------------------------------------------- paths */

export const referralPaths = {
  business: (merchantId: string) => `businesses/${merchantId}`,
  sale: (merchantId: string, saleId: string) =>
    `businesses/${merchantId}/sales/${saleId}`,
  saleItem: (merchantId: string, itemId: string) =>
    `businesses/${merchantId}/sale_items/${itemId}`,
  customer: (merchantId: string, customerId: string) =>
    `businesses/${merchantId}/customers/${customerId}`,
  customers: (merchantId: string) => `businesses/${merchantId}/customers`,
  sales: (merchantId: string) => `businesses/${merchantId}/sales`,
  code: (merchantId: string, codeId: string) =>
    `businesses/${merchantId}/affiliate_codes/${codeId}`,
  link: (merchantId: string, linkId: string) =>
    `businesses/${merchantId}/affiliate_merchants/${linkId}`,
  attribution: (merchantId: string, attributionId: string) =>
    `businesses/${merchantId}/affiliate_attributions/${attributionId}`,
  reward: (merchantId: string, rewardId: string) =>
    `businesses/${merchantId}/affiliate_rewards/${rewardId}`,
  event: (merchantId: string, eventId: string) =>
    `businesses/${merchantId}/affiliate_events/${eventId}`,
  outbox: (merchantId: string, outboxId: string) =>
    `businesses/${merchantId}/affiliate_outbox/${outboxId}`,
  fraudSignal: (merchantId: string, signalId: string) =>
    `businesses/${merchantId}/affiliate_fraud_signals/${signalId}`,
  ledgerEntry: (merchantId: string, entryId: string) =>
    `businesses/${merchantId}/loyalty_ledger/${entryId}`,
  affiliate: (affiliateId: string) => `affiliates/${affiliateId}`,
  /**
   * The global lookup document, keyed by the code itself.
   *
   * A slash would split the key into extra path segments and make the read
   * throw rather than answer. Codes are `AFI-NAME-XXXX` and never contain one,
   * so a typed code that does is escaped into a key that cannot exist — which
   * is the right answer for it anyway: not found.
   */
  codeLookup: (normalizedCode: string) =>
    `affiliate_code_lookup/${normalizeAffiliateCode(normalizedCode).replace(/\//g, '%2F')}`,
};

/**
 * The extra loyalty entry a POINTS benefit writes.
 *
 * Declared here rather than reusing the sale's own entry id: the bonus is a
 * separate, immutable fact with its own source, and folding it into the sale
 * entry would make the customer's balance disagree with the points the sale
 * itself earned.
 */
export const REFERRAL_BONUS_ENTRY_TYPE = 'REFERRAL_BONUS';
export const REFERRAL_BONUS_SOURCE_TYPE = 'referral';

export function referralBonusLedgerEntryId(saleId: string): string {
  return `referral_bonus_${saleId}`;
}

/* ------------------------------------------------------------------ inputs */

export type ReferralSaleItemInput = {
  id: string;
  merchantItemId: string;
  nameSnapshot: string;
  typeSnapshot: string;
  quantity: number;
  unitPrice: number | null;
  subtotal: number | null;
};

export type ReferralSaleCommitInput = {
  /** Always the resolved business of the session, never a body field. */
  merchantId: string;
  deviceId: string;
  localSaleId: string;
  customerId: string;
  customerPhoneE164: string;
  /** What the sale was before any discount. */
  grossAmount: number;
  rawCode: string;
  items: ReferralSaleItemInput[];
  appUserId: string;
  now: number;
};

/* ----------------------------------------------------------------- outcomes */

export type CommittedReferralSale = {
  sale: DocumentData;
  referral: {
    affiliate_id: string;
    affiliate_code_id: string;
    normalized_code: string;
    benefit: {
      type: BenefitType;
      value: number;
      discount_amount: number;
      points_awarded: number;
      display_text: string;
    };
    attribution_id: string | null;
    attribution_status: AttributionStatus | null;
    reward: {
      id: string;
      type: string;
      value: number;
      status: RewardStatus;
    } | null;
  };
  idempotency_key: string;
  replayed: boolean;
};

export type ReferralSaleCommitOutcome =
  | { status: 'committed'; result: CommittedReferralSale }
  | { status: 'replayed'; result: CommittedReferralSale }
  /** The code cannot be used for this sale. The till may sell without one. */
  | { status: 'rejected'; reason: ReferralReason; message: string }
  /** The same local sale id was reused for a different sale. */
  | { status: 'conflict' }
  /** The customer has not reached the server yet; nothing can be attributed. */
  | { status: 'customer_not_found' };

/* -------------------------------------------------------------------- facts */

export type ReferralSaleFacts = {
  business: DocumentData | null;
  lookup: { merchantId: string; affiliateId: string; codeId: string } | null;
  code: DocumentData | null;
  affiliate: DocumentData | null;
  link: DocumentData | null;
  customer: DocumentData | null;
  /** Other customer records sharing the phone: a duplicate is not a new visit. */
  phoneMatchCount: number;
  hasPreviousCompletedSale: boolean;
  attribution: DocumentData | null;
  existingSale: DocumentData | null;
  existingAttributionDoc: DocumentData | null;
  existingRewardDoc: DocumentData | null;
  existingBonusLedger: DocumentData | null;
  existingEventIds: Set<string>;
  existingOutboxIds: Set<string>;
  existingSaleItemIds: Set<string>;
};

/* ------------------------------------------------------------------ helpers */

function str(data: DocumentData | null, ...keys: string[]): string | null {
  if (data === null) return null;
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim() !== '') return value;
  }
  return null;
}

function num(data: DocumentData | null, key: string): number | null {
  if (data === null) return null;
  const value = data[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function flag(data: DocumentData | null, ...keys: string[]): boolean {
  if (data === null) return false;
  return keys.some((key) => data[key] === true);
}

/** Compared, never printed, and never stored: the phone stays out of the data. */
function phoneFingerprint(phoneE164: string | null): string {
  if (phoneE164 === null || phoneE164 === '') return '';
  return createHash('sha256').update(`affiliate-phone-v1:${phoneE164}`).digest('hex');
}

/**
 * The business's loyalty rule, read from the business document.
 *
 * Mirrors `getBusinessLoyaltyConfig` in index.ts, which is where the sale
 * trigger reads it from. Both have to agree: the trigger derives the ledger
 * entry from the same amount and would refuse the sale as drifted if this
 * wrote a different number of points.
 */
export function loyaltyRuleFrom(business: DocumentData | null): {
  pointsPerMzn: number;
  configVersion: number;
} {
  const raw =
    business !== null &&
    business.loyalty_config != null &&
    typeof business.loyalty_config === 'object'
      ? (business.loyalty_config as DocumentData)
      : {};
  const positive = (value: unknown, fallback: number): number => {
    return typeof value === 'number' && Number.isFinite(value) && value > 0
      ? Math.floor(value)
      : fallback;
  };
  return {
    pointsPerMzn: positive(raw.points_per_mzn, 100),
    configVersion: positive(raw.version, 1),
  };
}

export function calculateSalePoints(amount: number, pointsPerMzn: number): number {
  return Math.floor(amount / pointsPerMzn);
}

function attributionStatusOf(data: DocumentData | null): AttributionStatus | null {
  const status = (str(data, 'status') ?? '').toUpperCase();
  if (status === 'CONFIRMED' || status === 'REJECTED' || status === 'CANCELLED') {
    return status;
  }
  return null;
}

function codeSnapshotFrom(
  merchantId: string,
  codeId: string,
  code: DocumentData,
): ReferralCodeSnapshot {
  return {
    codeId,
    merchantId: str(code, 'merchant_id') ?? '',
    affiliateId: str(code, 'affiliate_id') ?? '',
    status: (str(code, 'status') ?? '').toUpperCase() === 'DISABLED' ? 'DISABLED' : 'ACTIVE',
    startsAt: num(code, 'starts_at') ?? 0,
    expiresAt: num(code, 'expires_at') ?? Number.MAX_SAFE_INTEGER,
    usageLimit: num(code, 'usage_limit'),
    usageCount: num(code, 'usage_count') ?? 0,
    firstVisitOnly: code.first_visit_only !== false,
    benefitType: ((str(code, 'benefit_type') ?? 'FIXED_AMOUNT').toUpperCase() as BenefitType),
    benefitValue: num(code, 'benefit_value') ?? 0,
  };
}

/* ------------------------------------------------------------------- reads */

/**
 * Everything the decision needs, read once, before a single write.
 *
 * The order matters only in that it all happens here. Firestore rejects a
 * query issued after a write in the same transaction, and — worse — a read
 * done outside the transaction is not held, so the usage count checked against
 * a limit could be stale by the time the increment lands.
 */
export async function readReferralSaleFacts(
  read: ReferralSaleReader,
  input: ReferralSaleCommitInput,
): Promise<ReferralSaleFacts> {
  const { merchantId } = input;
  const normalizedCode = normalizeAffiliateCode(input.rawCode);
  const saleId = affiliateIds.sale(input.deviceId, input.localSaleId);

  const [business, lookupDoc, customer, existingSale] = await Promise.all([
    read.getDoc(referralPaths.business(merchantId)),
    read.getDoc(referralPaths.codeLookup(normalizedCode)),
    read.getDoc(referralPaths.customer(merchantId, input.customerId)),
    read.getDoc(referralPaths.sale(merchantId, saleId)),
  ]);

  const lookupMerchantId = str(lookupDoc, 'merchant_id');
  const lookupAffiliateId = str(lookupDoc, 'affiliate_id');
  const lookupCodeId = str(lookupDoc, 'code_id');
  // A code that belongs to somebody else is not read any further. Fetching it
  // would be a way to learn that another business has it.
  const lookup =
    lookupMerchantId === merchantId &&
    lookupAffiliateId !== null &&
    lookupCodeId !== null
      ? {
          merchantId: lookupMerchantId,
          affiliateId: lookupAffiliateId,
          codeId: lookupCodeId,
        }
      : null;

  const [code, affiliate, link] =
    lookup === null
      ? [null, null, null]
      : await Promise.all([
          read.getDoc(referralPaths.code(merchantId, lookup.codeId)),
          read.getDoc(referralPaths.affiliate(lookup.affiliateId)),
          read.getDoc(
            referralPaths.link(
              merchantId,
              affiliateIds.link(lookup.affiliateId, merchantId),
            ),
          ),
        ]);

  const attributionId = affiliateIds.attribution(merchantId, input.customerId);
  const attribution = await read.getDoc(
    referralPaths.attribution(merchantId, attributionId),
  );

  // Both shapes a phone is stored in, the same candidates the rest of the
  // product matches on.
  const candidates = [input.customerPhoneE164, input.customerPhoneE164.slice(-9)];
  const matched = new Set<string>();
  for (const candidate of candidates) {
    if (candidate === '') continue;
    const rows = await read.queryDocs(
      referralPaths.customers(merchantId),
      'phone',
      candidate,
      25,
    );
    for (const row of rows) matched.add(row.id);
  }
  matched.add(input.customerId);

  let hasPreviousCompletedSale = false;
  for (const customerIdCandidate of [...matched].slice(0, 5)) {
    const sales = await read.queryDocs(
      referralPaths.sales(merchantId),
      'customer_id',
      customerIdCandidate,
      25,
    );
    for (const sale of sales) {
      if (sale.id === saleId) continue;
      const cancellation = (str(sale.data, 'cancellation_status') ?? '').toUpperCase();
      const confirmation = (str(sale.data, 'confirmation_status') ?? '').toUpperCase();
      if (cancellation === 'CANCELLED' || confirmation === 'CANCELLED') continue;
      if ((num(sale.data, 'amount') ?? 0) > 0) hasPreviousCompletedSale = true;
    }
  }

  const rewardId = affiliateIds.reward(attributionId, 'FIRST_QUALIFYING_SALE');
  const eventIds = [
    affiliateIds.event(merchantId, 'REFERRAL_ATTRIBUTED', saleId),
    affiliateIds.event(merchantId, 'AFFILIATE_REWARD_CREATED', saleId),
    affiliateIds.event(
      merchantId,
      'REFERRAL_REJECTED',
      saleIdempotencyKey(input.deviceId, input.localSaleId),
    ),
  ];
  const outboxIds = [
    affiliateIds.outbox(merchantId, 'affiliate_new_customer', saleId),
    affiliateIds.outbox(merchantId, 'customer_referral_thanks', saleId),
  ];

  const [
    existingRewardDoc,
    existingBonusLedger,
    eventDocs,
    outboxDocs,
    saleItemDocs,
  ] = await Promise.all([
    read.getDoc(referralPaths.reward(merchantId, rewardId)),
    read.getDoc(
      referralPaths.ledgerEntry(merchantId, referralBonusLedgerEntryId(saleId)),
    ),
    Promise.all(
      eventIds.map(async (id) => ({
        id,
        exists: (await read.getDoc(referralPaths.event(merchantId, id))) !== null,
      })),
    ),
    Promise.all(
      outboxIds.map(async (id) => ({
        id,
        exists: (await read.getDoc(referralPaths.outbox(merchantId, id))) !== null,
      })),
    ),
    Promise.all(
      input.items.map(async (item) => ({
        id: item.id,
        exists:
          (await read.getDoc(referralPaths.saleItem(merchantId, item.id))) !== null,
      })),
    ),
  ]);

  return {
    business,
    lookup,
    code,
    affiliate,
    link,
    customer,
    phoneMatchCount: matched.size,
    hasPreviousCompletedSale,
    attribution,
    existingSale,
    existingAttributionDoc: attribution,
    existingRewardDoc,
    existingBonusLedger,
    existingEventIds: new Set(
      eventDocs.filter((entry) => entry.exists).map((entry) => entry.id),
    ),
    existingOutboxIds: new Set(
      outboxDocs.filter((entry) => entry.exists).map((entry) => entry.id),
    ),
    existingSaleItemIds: new Set(
      saleItemDocs.filter((entry) => entry.exists).map((entry) => entry.id),
    ),
  };
}

/* -------------------------------------------------------------------- plan */

export type WriteOperation = {
  kind: 'create' | 'merge';
  path: string;
  data: DocumentData;
};

export type ReferralSalePlan =
  | { status: 'committed' | 'replayed'; writes: WriteOperation[]; result: CommittedReferralSale }
  | { status: 'rejected'; writes: WriteOperation[]; reason: ReferralReason; message: string }
  | { status: 'conflict'; writes: [] }
  | { status: 'customer_not_found'; writes: [] };

/**
 * The whole decision, as data.
 *
 * Pure: the same facts always produce the same writes, which is what makes
 * "the sale, the attribution, the reward and the count move together" a thing
 * a test can read off a list rather than infer from behaviour.
 */
export function planReferralSaleCommit(
  facts: ReferralSaleFacts,
  input: ReferralSaleCommitInput,
  config: AffiliateConfig,
): ReferralSalePlan {
  const { merchantId } = input;
  const normalizedCode = normalizeAffiliateCode(input.rawCode);
  const saleId = affiliateIds.sale(input.deviceId, input.localSaleId);
  const idempotencyKey = saleIdempotencyKey(input.deviceId, input.localSaleId);
  const attributionId = affiliateIds.attribution(merchantId, input.customerId);
  const fingerprint = referralRequestFingerprint({
    merchantId,
    customerId: input.customerId,
    grossAmount: input.grossAmount,
    normalizedCode,
    items: input.items.map((item) => ({
      id: item.id,
      merchantItemId: item.merchantItemId,
      nameSnapshot: item.nameSnapshot,
      typeSnapshot: item.typeSnapshot,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      subtotal: item.subtotal,
    })),
  });

  // A sale is attributed to a customer the server can see. A record that has
  // not synced yet cannot be given points, and inventing one here would create
  // a second customer for a phone that already has one.
  if (facts.customer === null) return { status: 'customer_not_found', writes: [] };

  if (facts.existingSale !== null) {
    const storedKey = str(facts.existingSale, 'referral_idempotency_key');
    const storedFingerprint = str(facts.existingSale, 'referral_request_hash');
    if (storedKey !== idempotencyKey || storedFingerprint !== fingerprint) {
      return { status: 'conflict', writes: [] };
    }
    return {
      status: 'replayed',
      writes: [],
      result: replayResult(facts, input, saleId, attributionId, idempotencyKey),
    };
  }

  const snapshot =
    facts.lookup === null || facts.code === null
      ? null
      : codeSnapshotFrom(merchantId, facts.lookup.codeId, facts.code);

  const customerIsNew = isNewCustomer({
    hasPreviousCompletedSale: facts.hasPreviousCompletedSale,
    hasNonRejectedAttribution:
      attributionStatusOf(facts.attribution) !== null &&
      attributionStatusOf(facts.attribution) !== 'REJECTED',
    phoneAlreadyKnown: facts.phoneMatchCount > 1,
    isAffiliate: false,
    isTestAccount: flag(facts.customer, 'is_test', 'is_test_account'),
    isBlocked:
      flag(facts.customer, 'is_blocked') ||
      (str(facts.customer, 'relationship_status') ?? '').toUpperCase() === 'BLOCKED',
  });

  const validation = validateReferral(snapshot, {
    merchantId,
    now: input.now,
    affiliateStatus:
      facts.affiliate === null
        ? 'INACTIVE'
        : ((str(facts.affiliate, 'status') ?? 'INACTIVE').toUpperCase() as 'ACTIVE'),
    linkStatus:
      facts.link === null
        ? 'INACTIVE'
        : (str(facts.link, 'status') ?? '').toUpperCase() === 'ACTIVE'
          ? 'ACTIVE'
          : 'INACTIVE',
    affiliatePhoneHash: phoneFingerprint(
      str(facts.affiliate, 'phone_e164', 'phone'),
    ),
    customerPhoneHash: phoneFingerprint(input.customerPhoneE164),
    customerIsNew,
    existingAttributionStatus: attributionStatusOf(facts.attribution),
    saleAmount: input.grossAmount,
  });

  if (!validation.ok) {
    // The refusal is a fact too, and the metrics screen counts it. Nothing else
    // is written: no sale, no benefit, no attribution.
    const rejectionEventId = affiliateIds.event(
      merchantId,
      'REFERRAL_REJECTED',
      idempotencyKey,
    );
    const writes: WriteOperation[] = facts.existingEventIds.has(rejectionEventId)
      ? []
      : [
          eventWrite(merchantId, rejectionEventId, {
            eventType: 'REFERRAL_REJECTED',
            affiliateId: facts.lookup?.affiliateId ?? null,
            customerId: input.customerId,
            saleId: null,
            dedupeKey: idempotencyKey,
            now: input.now,
            metadata: {
              code_id: facts.lookup?.codeId ?? null,
              reason: validation.reason,
              stage: 'COMMIT',
            },
          }),
        ];
    return {
      status: 'rejected',
      writes,
      reason: validation.reason,
      message: REFERRAL_REASON_MESSAGE[validation.reason],
    };
  }

  // Validation passed, so `snapshot` is a code of this business.
  const code = snapshot as ReferralCodeSnapshot;
  const benefit = calculateBenefit(code, input.grossAmount);
  const loyalty = loyaltyRuleFrom(facts.business);
  const points = calculateSalePoints(benefit.netAmount, loyalty.pointsPerMzn);

  // An existing customer under a code that allows them (`firstVisitOnly` off)
  // gets the benefit and nothing else: there is no acquisition to attribute
  // and so no reward to owe.
  const acquires = customerIsNew;
  const writes: WriteOperation[] = [];

  const saleData: DocumentData = {
    id: saleId,
    merchant_id: merchantId,
    customer_id: input.customerId,
    // `amount` keeps meaning what the customer paid, so loyalty points and
    // every existing report stay right for a sale with a discount.
    amount: benefit.netAmount,
    points,
    gross_amount: input.grossAmount,
    referral_benefit_type: benefit.type,
    referral_benefit_value: benefit.value,
    referral_benefit_amount:
      benefit.type === 'POINTS' ? benefit.pointsAwarded : benefit.discountAmount,
    affiliate_code_id: code.codeId,
    affiliate_id: code.affiliateId,
    referral_status: acquires ? 'ATTRIBUTED' : 'PENDING',
    referral_idempotency_key: idempotencyKey,
    referral_request_hash: fingerprint,
    created_at: input.now,
    updated_at: input.now,
    device_id: input.deviceId,
    created_by_app_user_id: input.appUserId,
    updated_by_app_user_id: input.appUserId,
    cancellation_status: 'ACTIVE',
  };
  writes.push({ kind: 'create', path: referralPaths.sale(merchantId, saleId), data: saleData });

  for (const item of input.items) {
    if (facts.existingSaleItemIds.has(item.id)) continue;
    writes.push({
      kind: 'create',
      path: referralPaths.saleItem(merchantId, item.id),
      data: {
        id: item.id,
        merchant_id: merchantId,
        sale_id: saleId,
        merchant_item_id: item.merchantItemId,
        name_snapshot: item.nameSnapshot,
        type_snapshot: item.typeSnapshot,
        quantity: item.quantity,
        unit_price: item.unitPrice,
        subtotal: item.subtotal,
        created_at: input.now,
        updated_at: input.now,
        created_by_app_user_id: input.appUserId,
        updated_by_app_user_id: input.appUserId,
      },
    });
  }

  // A POINTS benefit is a server-owned ledger entry, not a number added to a
  // total. The balance the customer sees is the ledger's, and an entry is the
  // only way to move it that survives a reconciliation.
  if (benefit.type === 'POINTS' && benefit.pointsAwarded > 0 && facts.existingBonusLedger === null) {
    writes.push({
      kind: 'create',
      path: referralPaths.ledgerEntry(merchantId, referralBonusLedgerEntryId(saleId)),
      data: {
        id: referralBonusLedgerEntryId(saleId),
        merchant_id: merchantId,
        customer_id: input.customerId,
        entry_type: REFERRAL_BONUS_ENTRY_TYPE,
        source_type: REFERRAL_BONUS_SOURCE_TYPE,
        source_id: saleId,
        // Just before the sale, so the sale's own entry stays the latest one
        // and the balance a client reads off it is the final balance.
        occurred_at: input.now - 1,
        points_delta: benefit.pointsAwarded,
        policy_version: loyalty.configVersion,
        balance_after: (num(facts.customer, 'confirmed_points') ?? 0) + benefit.pointsAwarded,
        canonical_customer_id: str(facts.customer, 'canonical_customer_id') ?? null,
        amount_mzn: 0,
        reward_id: null,
        idempotency_key: idempotencyKey,
        created_at: input.now,
        updated_at: input.now,
      },
    });
  }

  let rewardSummary: CommittedReferralSale['referral']['reward'] = null;

  if (acquires) {
    const existingAttribution = facts.existingAttributionDoc;
    writes.push({
      kind: existingAttribution === null ? 'create' : 'merge',
      path: referralPaths.attribution(merchantId, attributionId),
      data: {
        id: attributionId,
        merchant_id: merchantId,
        affiliate_id: code.affiliateId,
        affiliate_code_id: code.codeId,
        customer_id: input.customerId,
        first_sale_id: saleId,
        status: 'CONFIRMED',
        rejection_reason: null,
        attributed_at: input.now,
        created_at:
          existingAttribution === null
            ? input.now
            : num(existingAttribution, 'created_at') ?? input.now,
        updated_at: input.now,
      },
    });

    // Only the first acquisition spends the code. The count never decreases,
    // so a cancellation later does not give the use back.
    writes.push({
      kind: 'merge',
      path: referralPaths.code(merchantId, code.codeId),
      data: { usage_count: code.usageCount + 1, updated_at: input.now },
    });

    // The global lookup is how a typed code finds its business. It is repaired
    // only when what it says has drifted from what the code actually is.
    const lookupDrifted =
      facts.lookup !== null &&
      (facts.lookup.codeId !== code.codeId ||
        facts.lookup.affiliateId !== code.affiliateId);
    if (lookupDrifted) {
      writes.push({
        kind: 'merge',
        path: referralPaths.codeLookup(normalizedCode),
        data: {
          code: normalizedCode,
          merchant_id: merchantId,
          affiliate_id: code.affiliateId,
          code_id: code.codeId,
          updated_at: input.now,
        },
      });
    }

    const plannedReward = planFirstSaleReward(config);
    const rewardId = affiliateIds.reward(attributionId, 'FIRST_QUALIFYING_SALE');
    if (plannedReward !== null && facts.existingRewardDoc === null) {
      writes.push({
        kind: 'create',
        path: referralPaths.reward(merchantId, rewardId),
        data: {
          id: rewardId,
          merchant_id: merchantId,
          affiliate_id: code.affiliateId,
          attribution_id: attributionId,
          type: plannedReward.type,
          value: plannedReward.value,
          value_type: plannedReward.valueType,
          status: plannedReward.status,
          trigger_sale_id: saleId,
          approved_by: null,
          approved_at: plannedReward.status === 'APPROVED' ? input.now : null,
          paid_at: null,
          cancelled_at: null,
          created_at: input.now,
          updated_at: input.now,
        },
      });
    }
    if (plannedReward !== null) {
      rewardSummary = {
        id: rewardId,
        type: plannedReward.type,
        value: plannedReward.value,
        status: (str(facts.existingRewardDoc, 'status') ?? plannedReward.status) as RewardStatus,
      };
    }

    pushEvent(writes, facts, merchantId, 'REFERRAL_ATTRIBUTED', saleId, {
      affiliateId: code.affiliateId,
      customerId: input.customerId,
      saleId,
      dedupeKey: idempotencyKey,
      now: input.now,
      metadata: {
        attribution_id: attributionId,
        code_id: code.codeId,
        benefit_type: benefit.type,
        net_amount: benefit.netAmount,
        gross_amount: input.grossAmount,
      },
    });
    pushOutbox(writes, facts, merchantId, 'affiliate_new_customer', saleId, {
      affiliateId: code.affiliateId,
      now: input.now,
      payload: {
        attribution_id: attributionId,
        reward_points: rewardSummary?.value ?? 0,
        reward_status: rewardSummary?.status ?? null,
      },
    });

    if (rewardSummary !== null) {
      pushEvent(writes, facts, merchantId, 'AFFILIATE_REWARD_CREATED', saleId, {
        affiliateId: code.affiliateId,
        customerId: input.customerId,
        saleId,
        dedupeKey: idempotencyKey,
        now: input.now,
        metadata: {
          reward_id: rewardSummary.id,
          value: rewardSummary.value,
          status: rewardSummary.status,
          type: rewardSummary.type,
        },
      });
    }
  }

  pushOutbox(writes, facts, merchantId, 'customer_referral_thanks', saleId, {
    affiliateId: code.affiliateId,
    now: input.now,
    payload: { points, benefit_type: benefit.type, customer_id: input.customerId },
  });

  return {
    status: 'committed',
    writes,
    result: {
      sale: saleData,
      referral: {
        affiliate_id: code.affiliateId,
        affiliate_code_id: code.codeId,
        normalized_code: normalizedCode,
        benefit: benefitSummary(benefit),
        attribution_id: acquires ? attributionId : null,
        attribution_status: acquires ? 'CONFIRMED' : null,
        reward: rewardSummary,
      },
      idempotency_key: idempotencyKey,
      replayed: false,
    },
  };
}

function benefitSummary(benefit: CalculatedBenefit) {
  return {
    type: benefit.type,
    value: benefit.value,
    discount_amount: benefit.discountAmount,
    points_awarded: benefit.pointsAwarded,
    display_text: benefit.displayText,
  };
}

/** What a retry is told: the sale that exists, not a second one. */
function replayResult(
  facts: ReferralSaleFacts,
  input: ReferralSaleCommitInput,
  saleId: string,
  attributionId: string,
  idempotencyKey: string,
): CommittedReferralSale {
  const sale = facts.existingSale ?? {};
  const benefitType = ((str(sale, 'referral_benefit_type') ?? 'FIXED_AMOUNT').toUpperCase() as BenefitType);
  const benefitValue = num(sale, 'referral_benefit_value') ?? 0;
  const benefitAmount = num(sale, 'referral_benefit_amount') ?? 0;
  const attributionStatus = attributionStatusOf(facts.existingAttributionDoc);
  const reward = facts.existingRewardDoc;

  return {
    sale: { ...sale, id: saleId },
    referral: {
      affiliate_id: str(sale, 'affiliate_id') ?? '',
      affiliate_code_id: str(sale, 'affiliate_code_id') ?? '',
      normalized_code: normalizeAffiliateCode(input.rawCode),
      benefit: {
        type: benefitType,
        value: benefitValue,
        discount_amount: benefitType === 'POINTS' ? 0 : benefitAmount,
        points_awarded: benefitType === 'POINTS' ? benefitAmount : 0,
        display_text: '',
      },
      attribution_id: attributionStatus === null ? null : attributionId,
      attribution_status: attributionStatus,
      reward:
        reward === null
          ? null
          : {
              id: str(reward, 'id') ?? '',
              type: str(reward, 'type') ?? '',
              value: num(reward, 'value') ?? 0,
              status: ((str(reward, 'status') ?? 'PENDING').toUpperCase() as RewardStatus),
            },
    },
    idempotency_key: idempotencyKey,
    replayed: true,
  };
}

function eventWrite(
  merchantId: string,
  eventId: string,
  event: {
    eventType: AffiliateEventType;
    affiliateId: string | null;
    customerId: string | null;
    saleId: string | null;
    dedupeKey: string;
    now: number;
    metadata: DocumentData;
  },
): WriteOperation {
  return {
    kind: 'create',
    path: referralPaths.event(merchantId, eventId),
    data: {
      id: eventId,
      merchant_id: merchantId,
      affiliate_id: event.affiliateId,
      customer_id: event.customerId,
      sale_id: event.saleId,
      event_type: event.eventType,
      dedupe_key: event.dedupeKey,
      metadata: event.metadata,
      created_at: event.now,
    },
  };
}

function pushEvent(
  writes: WriteOperation[],
  facts: ReferralSaleFacts,
  merchantId: string,
  eventType: AffiliateEventType,
  sourceKey: string,
  event: {
    affiliateId: string | null;
    customerId: string | null;
    saleId: string | null;
    dedupeKey: string;
    now: number;
    metadata: DocumentData;
  },
): void {
  const eventId = affiliateIds.event(merchantId, eventType, sourceKey);
  if (facts.existingEventIds.has(eventId)) return;
  writes.push(eventWrite(merchantId, eventId, { eventType, ...event }));
}

/**
 * The message Phase 5 will send, recorded now.
 *
 * Written inside the transaction because the fact is part of the sale; sent
 * outside it, by a worker that does not exist yet. A row that is queued and
 * never delivered is a backlog; a message sent for a sale that rolled back is
 * a correction nobody can make.
 */
function pushOutbox(
  writes: WriteOperation[],
  facts: ReferralSaleFacts,
  merchantId: string,
  template: string,
  sourceKey: string,
  entry: { affiliateId: string | null; now: number; payload: DocumentData },
): void {
  const outboxId = affiliateIds.outbox(merchantId, template, sourceKey);
  if (facts.existingOutboxIds.has(outboxId)) return;
  writes.push({
    kind: 'create',
    path: referralPaths.outbox(merchantId, outboxId),
    data: {
      id: outboxId,
      merchant_id: merchantId,
      affiliate_id: entry.affiliateId,
      template,
      source_key: sourceKey,
      status: 'QUEUED',
      attempts: 0,
      next_attempt_at: entry.now,
      last_error: null,
      payload: entry.payload,
      created_at: entry.now,
      updated_at: entry.now,
    },
  });
}

/* ------------------------------------------------------------------ writes */

export function applyReferralSalePlan(
  write: ReferralSaleWriter,
  writes: WriteOperation[],
): void {
  for (const operation of writes) {
    if (operation.kind === 'create') write.create(operation.path, operation.data);
    else write.merge(operation.path, operation.data);
  }
}

/* ----------------------------------------------------------------- command */

/**
 * The authoritative command: read, decide, write, once.
 *
 * `loadConfig` is separate because the business document is read inside the
 * transaction anyway — the settings that price a reward have to be the ones in
 * force when the sale commits, not the ones a route read a moment earlier.
 */
export async function commitReferralSale(
  gateway: ReferralSaleGateway,
  input: ReferralSaleCommitInput,
  loadConfig: (business: DocumentData | null) => AffiliateConfig,
): Promise<ReferralSaleCommitOutcome> {
  return gateway.runTransaction(async (transaction) => {
    const facts = await readReferralSaleFacts(transaction, input);
    const plan = planReferralSaleCommit(facts, input, loadConfig(facts.business));

    applyReferralSalePlan(transaction, plan.writes);

    switch (plan.status) {
      case 'committed':
        return { status: 'committed' as const, result: plan.result };
      case 'replayed':
        return { status: 'replayed' as const, result: plan.result };
      case 'rejected':
        return {
          status: 'rejected' as const,
          reason: plan.reason,
          message: plan.message,
        };
      case 'conflict':
        return { status: 'conflict' as const };
      default:
        return { status: 'customer_not_found' as const };
    }
  });
}

/* ------------------------------------------------------------ cancellation */

export type ReferralReversalOutcome = {
  status: 'not_referred' | 'reversed' | 'already_reversed';
  attribution_cancelled: boolean;
  rewards_cancelled: string[];
  rewards_needing_review: string[];
};

/**
 * What a cancelled sale takes back, and what it cannot.
 *
 * An acquisition that has been undone is not an acquisition: the attribution
 * becomes `CANCELLED` and any reward still `PENDING` or `APPROVED` goes with
 * it. A `PAID` reward does not — points already handed to an affiliate are not
 * unpaid by a status change — so it raises a signal for a person instead, which
 * is the same line `rewardsAffectedByCancellation` draws for every caller.
 *
 * `usage_count` is never decremented. The code was used; the sale being
 * cancelled afterwards does not make it unused, and a count that could go down
 * would let a limit be walked around by cancelling.
 */
export async function reverseReferralSale(
  gateway: ReferralSaleGateway,
  input: { merchantId: string; saleId: string; cancelledAt: number; actorId: string },
): Promise<ReferralReversalOutcome> {
  return gateway.runTransaction(async (transaction) => {
    const sale = await transaction.getDoc(
      referralPaths.sale(input.merchantId, input.saleId),
    );
    const saleMerchantId = str(sale, 'merchant_id');
    // A sale of another business is not reachable by path, and a document that
    // disagrees with its own path is not trusted either.
    if (
      sale === null ||
      (saleMerchantId !== null && saleMerchantId !== input.merchantId) ||
      str(sale, 'affiliate_code_id') === null
    ) {
      return {
        status: 'not_referred' as const,
        attribution_cancelled: false,
        rewards_cancelled: [],
        rewards_needing_review: [],
      };
    }

    const customerId = str(sale, 'customer_id');
    if (customerId === null) {
      return {
        status: 'not_referred' as const,
        attribution_cancelled: false,
        rewards_cancelled: [],
        rewards_needing_review: [],
      };
    }

    const attributionId = affiliateIds.attribution(input.merchantId, customerId);
    const attribution = await transaction.getDoc(
      referralPaths.attribution(input.merchantId, attributionId),
    );
    const firstSaleId = str(attribution, 'first_sale_id');
    const cancelsAcquisition =
      attribution !== null && firstSaleId === input.saleId;

    const rewardIds = {
      FIRST_QUALIFYING_SALE: affiliateIds.reward(attributionId, 'FIRST_QUALIFYING_SALE'),
      CUSTOMER_RETURN: affiliateIds.reward(attributionId, 'CUSTOMER_RETURN'),
    } as const;
    const cancelledEventIds = {
      FIRST_QUALIFYING_SALE: affiliateIds.event(
        input.merchantId,
        'AFFILIATE_REWARD_CANCELLED',
        rewardIds.FIRST_QUALIFYING_SALE,
      ),
      CUSTOMER_RETURN: affiliateIds.event(
        input.merchantId,
        'AFFILIATE_REWARD_CANCELLED',
        rewardIds.CUSTOMER_RETURN,
      ),
    } as const;
    // Every read first: a transaction that reads after it writes is rejected,
    // so even the "has this event been written already?" checks happen here.
    const [firstReward, returnReward, firstEvent, returnEvent] = await Promise.all([
      transaction.getDoc(referralPaths.reward(input.merchantId, rewardIds.FIRST_QUALIFYING_SALE)),
      transaction.getDoc(referralPaths.reward(input.merchantId, rewardIds.CUSTOMER_RETURN)),
      transaction.getDoc(
        referralPaths.event(input.merchantId, cancelledEventIds.FIRST_QUALIFYING_SALE),
      ),
      transaction.getDoc(
        referralPaths.event(input.merchantId, cancelledEventIds.CUSTOMER_RETURN),
      ),
    ]);
    const existingCancelEvents = new Set(
      [
        firstEvent === null ? null : cancelledEventIds.FIRST_QUALIFYING_SALE,
        returnEvent === null ? null : cancelledEventIds.CUSTOMER_RETURN,
      ].filter((id): id is string => id !== null),
    );

    const candidates: Array<{ id: string; status: string; data: DocumentData }> = [];
    if (firstReward !== null && cancelsAcquisition) {
      candidates.push({
        id: rewardIds.FIRST_QUALIFYING_SALE,
        status: str(firstReward, 'status') ?? '',
        data: firstReward,
      });
    }
    if (
      returnReward !== null &&
      (cancelsAcquisition || str(returnReward, 'trigger_sale_id') === input.saleId)
    ) {
      candidates.push({
        id: rewardIds.CUSTOMER_RETURN,
        status: str(returnReward, 'status') ?? '',
        data: returnReward,
      });
    }

    const { cancellable, needsManualReview } = rewardsAffectedByCancellation(candidates);

    const attributionAlreadyCancelled =
      attributionStatusOf(attribution) === 'CANCELLED';
    const attributionCancels = cancelsAcquisition && !attributionAlreadyCancelled;

    // Nothing left to move: a second cancel of the same sale writes nothing.
    if (!attributionCancels && cancellable.length === 0 && needsManualReview.length === 0) {
      return {
        status: (cancelsAcquisition || candidates.length > 0
          ? 'already_reversed'
          : 'not_referred') as 'already_reversed' | 'not_referred',
        attribution_cancelled: false,
        rewards_cancelled: [],
        rewards_needing_review: [],
      };
    }

    if (attributionCancels) {
      transaction.merge(referralPaths.attribution(input.merchantId, attributionId), {
        status: 'CANCELLED',
        rejection_reason: 'SALE_CANCELLED',
        cancelled_at: input.cancelledAt,
        updated_at: input.cancelledAt,
      });
    }

    const affiliateId = str(sale, 'affiliate_id') ?? str(attribution, 'affiliate_id');

    for (const rewardId of cancellable) {
      transaction.merge(referralPaths.reward(input.merchantId, rewardId), {
        status: 'CANCELLED',
        cancelled_at: input.cancelledAt,
        updated_at: input.cancelledAt,
      });
      const eventId = affiliateIds.event(
        input.merchantId,
        'AFFILIATE_REWARD_CANCELLED',
        rewardId,
      );
      if (!existingCancelEvents.has(eventId)) {
        transaction.create(referralPaths.event(input.merchantId, eventId), {
          id: eventId,
          merchant_id: input.merchantId,
          affiliate_id: affiliateId,
          customer_id: customerId,
          sale_id: input.saleId,
          event_type: 'AFFILIATE_REWARD_CANCELLED',
          dedupe_key: rewardId,
          metadata: { reward_id: rewardId, cause: 'SALE_CANCELLED', actor_id: input.actorId },
          created_at: input.cancelledAt,
        });
      }
    }

    for (const rewardId of needsManualReview) {
      const signalId = affiliateIds.fraudSignal(
        input.merchantId,
        'PAID_REWARD_SALE_CANCELLED',
        rewardId,
      );
      transaction.merge(referralPaths.fraudSignal(input.merchantId, signalId), {
        id: signalId,
        merchant_id: input.merchantId,
        affiliate_id: affiliateId,
        signal_type: 'PAID_REWARD_SALE_CANCELLED',
        severity: 'HIGH',
        requires_manual_review: true,
        sale_id: input.saleId,
        reward_id: rewardId,
        attribution_id: attributionId,
        actor_id: input.actorId,
        created_at: input.cancelledAt,
        updated_at: input.cancelledAt,
      });
    }

    return {
      status: 'reversed' as const,
      attribution_cancelled: attributionCancels,
      rewards_cancelled: cancellable,
      rewards_needing_review: needsManualReview,
    };
  });
}

/* ----------------------------------------------------------------- returns */

export type ReferredReturnOutcome = {
  status: 'not_referred' | 'first_sale' | 'recorded' | 'already_recorded' | 'out_of_window';
  reward_id: string | null;
};

/**
 * A referred customer coming back, recorded once.
 *
 * Hooked to the sale the business already processes, not to the referral
 * commit, so an ordinary sale synced from the till counts too — which is the
 * only way this works at all: the second visit usually has no code on it.
 *
 * Both the event and the reward are keyed deterministically, so the trigger
 * firing twice for the same write records one return and owes one reward.
 */
export async function recordReferredCustomerReturn(
  gateway: ReferralSaleGateway,
  input: {
    merchantId: string;
    saleId: string;
    customerId: string;
    amount: number;
    occurredAt: number;
  },
  config: AffiliateConfig,
): Promise<ReferredReturnOutcome> {
  return gateway.runTransaction(async (transaction) => {
    const attributionId = affiliateIds.attribution(input.merchantId, input.customerId);
    const attribution = await transaction.getDoc(
      referralPaths.attribution(input.merchantId, attributionId),
    );
    if (attribution === null || attributionStatusOf(attribution) !== 'CONFIRMED') {
      return { status: 'not_referred' as const, reward_id: null };
    }
    if (str(attribution, 'first_sale_id') === input.saleId) {
      return { status: 'first_sale' as const, reward_id: null };
    }

    const firstSaleAt =
      num(attribution, 'attributed_at') ?? num(attribution, 'created_at') ?? 0;
    const affiliateId = str(attribution, 'affiliate_id');
    const eventId = affiliateIds.event(
      input.merchantId,
      'REFERRED_CUSTOMER_RETURNED',
      input.saleId,
    );
    const rewardId = affiliateIds.reward(attributionId, 'CUSTOMER_RETURN');
    const rewardEventId = affiliateIds.event(
      input.merchantId,
      'AFFILIATE_REWARD_CREATED',
      rewardId,
    );
    const outboxId = affiliateIds.outbox(
      input.merchantId,
      'affiliate_customer_returned',
      input.saleId,
    );
    const [existingEvent, existingReward, existingRewardEvent, existingOutbox] =
      await Promise.all([
        transaction.getDoc(referralPaths.event(input.merchantId, eventId)),
        transaction.getDoc(referralPaths.reward(input.merchantId, rewardId)),
        transaction.getDoc(referralPaths.event(input.merchantId, rewardEventId)),
        transaction.getDoc(referralPaths.outbox(input.merchantId, outboxId)),
      ]);

    const planned = planReturnReward(config, firstSaleAt, input.occurredAt);
    if (existingEvent !== null && (planned === null || existingReward !== null)) {
      return {
        status: 'already_recorded' as const,
        reward_id: existingReward === null ? null : rewardId,
      };
    }

    if (existingEvent === null) {
      transaction.create(referralPaths.event(input.merchantId, eventId), {
        id: eventId,
        merchant_id: input.merchantId,
        affiliate_id: affiliateId,
        customer_id: input.customerId,
        sale_id: input.saleId,
        event_type: 'REFERRED_CUSTOMER_RETURNED',
        dedupe_key: input.saleId,
        metadata: {
          attribution_id: attributionId,
          amount: input.amount,
          within_window: isWithinReturnWindow(config, firstSaleAt, input.occurredAt),
        },
        created_at: input.occurredAt,
      });
    }

    if (planned === null) {
      return { status: 'out_of_window' as const, reward_id: null };
    }

    if (existingReward === null) {
      transaction.create(referralPaths.reward(input.merchantId, rewardId), {
        id: rewardId,
        merchant_id: input.merchantId,
        affiliate_id: affiliateId,
        attribution_id: attributionId,
        type: planned.type,
        value: planned.value,
        value_type: planned.valueType,
        status: planned.status,
        trigger_sale_id: input.saleId,
        approved_by: null,
        approved_at: planned.status === 'APPROVED' ? input.occurredAt : null,
        paid_at: null,
        cancelled_at: null,
        created_at: input.occurredAt,
        updated_at: input.occurredAt,
      });

      const rewardEventPath = referralPaths.event(input.merchantId, rewardEventId);
      if (existingRewardEvent === null) {
        transaction.create(rewardEventPath, {
          id: rewardEventId,
          merchant_id: input.merchantId,
          affiliate_id: affiliateId,
          customer_id: input.customerId,
          sale_id: input.saleId,
          event_type: 'AFFILIATE_REWARD_CREATED',
          dedupe_key: rewardId,
          metadata: { reward_id: rewardId, value: planned.value, type: planned.type },
          created_at: input.occurredAt,
        });
      }

      const outboxPath = referralPaths.outbox(input.merchantId, outboxId);
      if (existingOutbox === null) {
        transaction.create(outboxPath, {
          id: outboxId,
          merchant_id: input.merchantId,
          affiliate_id: affiliateId,
          template: 'affiliate_customer_returned',
          source_key: input.saleId,
          status: 'QUEUED',
          attempts: 0,
          next_attempt_at: input.occurredAt,
          last_error: null,
          payload: { reward_points: planned.value, reward_status: planned.status },
          created_at: input.occurredAt,
          updated_at: input.occurredAt,
        });
      }
    }

    return { status: 'recorded' as const, reward_id: rewardId };
  });
}
