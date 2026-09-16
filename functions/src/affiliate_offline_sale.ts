import {
  REFERRAL_REASON_MESSAGE,
  type AffiliateConfig,
  type AffiliateEventType,
  type AttributionStatus,
  type BenefitType,
  type FraudSeverity,
  type ReferralReason,
  type RewardStatus,
} from './affiliate_contracts.js';
import {
  CLOCK_SKEW_SIGNAL_MS,
  affiliateIds,
  calculateBenefit,
  isNewCustomer,
  normalizeAffiliateCode,
  planFirstSaleReward,
  referralIdempotencyKeys,
  referralPhoneHash,
  referralRequestFingerprint,
  saleIdempotencyKey,
  validateReferral,
  type ReferralCodeSnapshot,
} from './affiliate_engine.js';
import {
  REFERRAL_BONUS_ENTRY_TYPE,
  REFERRAL_BONUS_SOURCE_TYPE,
  calculateSalePoints,
  loyaltyRuleFrom,
  readReferralSaleFacts,
  referralBonusLedgerEntryId,
  referralPaths,
  type DocumentData,
  type ReferralSaleCommitInput,
  type ReferralSaleFacts,
  type ReferralSaleGateway,
  type WriteOperation,
} from './affiliate_sale_commit.js';

/**
 * Reconciling a sale a till already made.
 *
 * The online commit decides whether a sale happens. This does not: the sale has
 * happened, the customer has paid and gone, and the only open questions are who
 * gets credited and what the business owes. That difference is the whole file.
 *
 * Two facts arrive with the request and change everything about the answer:
 *
 *   `offlineBenefitApplied` — whether the till already took money off the bill.
 *   If it did, the discount stands whatever the server thinks of the code. A
 *   refusal that reversed it would be an invoice sent to someone who left the
 *   shop an hour ago.
 *
 *   whether the code was in the till's cache at all. A code the till had never
 *   been told about was charged in full, and a valid one cannot be discounted
 *   after the fact — money is not refunded by a sync. It can still earn the
 *   affiliate the acquisition, and a POINTS benefit can still be credited,
 *   because points are a ledger entry and a ledger entry is not a refund.
 *
 * What the server never does is take back a benefit, and never pays a reward
 * for a code it refused. Both of those are written down: a refusal creates a
 * `REJECTED` attribution with its reason and an `OFFLINE_CODE_REJECTED` signal,
 * so a merchant who wonders why a discount was given and nobody was credited
 * has the answer in one place.
 */

/* ------------------------------------------------------------------ inputs */

/** What the till applied on its own, in the words it recorded it. */
export type AppliedOfflineBenefit = {
  type: BenefitType;
  value: number;
  discountAmount: number;
  pointsAwarded: number;
};

export type OfflineReferralSaleInput = ReferralSaleCommitInput & {
  /** True when a discount was already taken off the bill at the counter. */
  offlineBenefitApplied: boolean;
  /** Null whenever nothing was applied. */
  appliedBenefit: AppliedOfflineBenefit | null;
  /** The device's own clock when the sale was made. */
  localCreatedAt: number;
};

/* ---------------------------------------------------------------- outcomes */

export type OfflineReferralSummary = {
  sale: DocumentData;
  referral: {
    affiliate_id: string | null;
    affiliate_code_id: string | null;
    normalized_code: string;
    benefit: {
      type: BenefitType | null;
      value: number;
      discount_amount: number;
      points_awarded: number;
      display_text: string;
    };
    attribution: DocumentData | null;
    attribution_id: string | null;
    attribution_status: AttributionStatus | null;
    reward_record: DocumentData | null;
    reward: { id: string; type: string; value: number; status: RewardStatus } | null;
    /**
     * Whether money actually came off this sale. Named explicitly because the
     * two ways it can be false mean opposite things to a merchant: a POINTS
     * code takes nothing off by design, and an uncached code took nothing off
     * because the till could not price it and the server will not refund it.
     */
    monetary_benefit_applied: boolean;
    /**
     * Always false. A discount is never granted after the customer has paid;
     * sent as a field rather than implied so a client cannot read its absence
     * as "not decided".
     */
    retroactive_discount_applied: false;
    /** True when a POINTS benefit was credited by this reconciliation. */
    points_benefit_credited: boolean;
  };
  events: DocumentData[];
  idempotency_key: string;
  clock_skew_ms: number;
};

export type OfflineReferralSalePlan =
  | {
      status: 'committed' | 'replayed';
      writes: WriteOperation[];
      result: OfflineReferralSummary;
    }
  | {
      status: 'rejected';
      writes: WriteOperation[];
      reason: ReferralReason;
      message: string;
      result: OfflineReferralSummary;
    }
  /** The same local sale id was reused for a different sale. */
  | { status: 'conflict'; writes: [] }
  /** The customer has not reached the server yet. Try again, do not refuse. */
  | { status: 'deferred'; writes: [] };

export type OfflineReferralSaleOutcome =
  | { status: 'committed' | 'replayed'; result: OfflineReferralSummary }
  | {
      status: 'rejected';
      reason: ReferralReason;
      message: string;
      result: OfflineReferralSummary;
    }
  | { status: 'conflict' }
  | { status: 'deferred' };

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

function cents(value: number): number {
  return Math.round(value * 100);
}

/** Never below zero and never more than the bill, whatever the till recorded. */
function honouredDiscount(input: OfflineReferralSaleInput): number {
  if (!input.offlineBenefitApplied || input.appliedBenefit === null) return 0;
  if (input.appliedBenefit.type === 'POINTS') return 0;
  const grossCents = cents(input.grossAmount);
  const appliedCents = cents(input.appliedBenefit.discountAmount);
  if (!Number.isFinite(appliedCents) || appliedCents <= 0) return 0;
  return Math.min(appliedCents, grossCents) / 100;
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

function fraudSignalWrite(
  merchantId: string,
  signalId: string,
  signal: {
    affiliateId: string | null;
    customerId: string | null;
    saleId: string | null;
    severity: FraudSeverity;
    metadata: DocumentData;
    now: number;
  },
): WriteOperation {
  return {
    kind: 'merge',
    path: referralPaths.fraudSignal(merchantId, signalId),
    data: {
      id: signalId,
      merchant_id: merchantId,
      affiliate_id: signal.affiliateId,
      customer_id: signal.customerId,
      sale_id: signal.saleId,
      signal_type: 'OFFLINE_CODE_REJECTED',
      severity: signal.severity,
      metadata: signal.metadata,
      created_at: signal.now,
    },
  };
}

function emptyBenefitSummary(): OfflineReferralSummary['referral']['benefit'] {
  return {
    type: null,
    value: 0,
    discount_amount: 0,
    points_awarded: 0,
    display_text: '',
  };
}

/* -------------------------------------------------------------------- plan */

/**
 * The whole decision, as data. Pure, like the online planner and for the same
 * reason: "the discount stood and nobody was credited" is a list a test can
 * read rather than a behaviour it has to infer.
 */
export function planOfflineReferralSale(
  facts: ReferralSaleFacts,
  input: OfflineReferralSaleInput,
  config: AffiliateConfig,
): OfflineReferralSalePlan {
  const { merchantId } = input;
  const normalizedCode = normalizeAffiliateCode(input.rawCode);
  const saleId = affiliateIds.sale(input.deviceId, input.localSaleId);
  const idempotencyKey = saleIdempotencyKey(input.deviceId, input.localSaleId);
  const attributionId = affiliateIds.attribution(merchantId, input.customerId);
  const customerPhoneHash = referralPhoneHash(input.customerPhoneE164);
  const attributionKey = referralIdempotencyKeys.attribution(
    merchantId,
    customerPhoneHash,
  );
  const clockSkewMs = Math.abs(input.now - input.localCreatedAt);
  const fingerprint = referralRequestFingerprint({
    merchantId,
    customerId: input.customerId,
    grossAmount: input.grossAmount,
    normalizedCode,
    items: input.items,
  });

  // A sale belongs to a customer the server can see. The customer's own queued
  // create is usually right in front of this one, so "not yet" is a wait rather
  // than a refusal — refusing here would throw away the sale for being early.
  if (facts.customer === null) return { status: 'deferred', writes: [] };

  if (facts.existingSale !== null) {
    const storedKey = str(facts.existingSale, 'referral_idempotency_key');
    const storedFingerprint = str(facts.existingSale, 'referral_request_hash');
    if (storedKey !== idempotencyKey || storedFingerprint !== fingerprint) {
      return { status: 'conflict', writes: [] };
    }
    return {
      status: 'replayed',
      writes: [],
      result: replaySummary(facts, input, saleId, attributionId, idempotencyKey, {
        normalizedCode,
        clockSkewMs,
      }),
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
    affiliatePhoneHash: referralPhoneHash(str(facts.affiliate, 'phone_e164', 'phone')),
    customerPhoneHash,
    customerIsNew,
    existingAttributionStatus: attributionStatusOf(facts.attribution),
    saleAmount: input.grossAmount,
  });

  const discountGiven = honouredDiscount(input);
  const loyalty = loyaltyRuleFrom(facts.business);

  const saleBase: DocumentData = {
    id: saleId,
    merchant_id: merchantId,
    customer_id: input.customerId,
    gross_amount: input.grossAmount,
    referral_idempotency_key: idempotencyKey,
    referral_request_hash: fingerprint,
    referral_source: 'OFFLINE',
    referral_offline_benefit_applied: input.offlineBenefitApplied,
    created_at: input.localCreatedAt,
    updated_at: input.now,
    device_id: input.deviceId,
    created_by_app_user_id: input.appUserId,
    updated_by_app_user_id: input.appUserId,
    cancellation_status: 'ACTIVE',
  };

  const itemWrites: WriteOperation[] = [];
  for (const item of input.items) {
    if (facts.existingSaleItemIds.has(item.id)) continue;
    itemWrites.push({
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
        created_at: input.localCreatedAt,
        updated_at: input.now,
        created_by_app_user_id: input.appUserId,
        updated_by_app_user_id: input.appUserId,
      },
    });
  }

  if (!validation.ok) {
    return planRefusal({
      facts,
      input,
      config,
      saleId,
      attributionId,
      attributionKey,
      idempotencyKey,
      normalizedCode,
      reason: validation.reason,
      discountGiven,
      saleBase,
      itemWrites,
      loyalty,
      clockSkewMs,
    });
  }

  const code = snapshot as ReferralCodeSnapshot;
  const benefit = calculateBenefit(code, input.grossAmount);
  const isPointsBenefit = benefit.type === 'POINTS';
  const appliedMonetaryBenefit =
    input.offlineBenefitApplied &&
    input.appliedBenefit !== null &&
    input.appliedBenefit.type !== 'POINTS' &&
    discountGiven > 0
      ? input.appliedBenefit
      : null;

  // The two rules that make this an offline reconciliation and not a commit:
  // money already taken off stays off, and money not taken off is never taken
  // off later.
  const monetaryApplied = appliedMonetaryBenefit !== null;
  const netAmount = monetaryApplied
    ? (cents(input.grossAmount) - cents(discountGiven)) / 100
    : input.grossAmount;
  const points = calculateSalePoints(netAmount, loyalty.pointsPerMzn);
  const acquires = customerIsNew;

  const writes: WriteOperation[] = [];
  const events: DocumentData[] = [];

  const saleData: DocumentData = {
    ...saleBase,
    amount: netAmount,
    points,
    referral_benefit_type: appliedMonetaryBenefit?.type ?? benefit.type,
    referral_benefit_value: appliedMonetaryBenefit?.value ?? benefit.value,
    referral_benefit_amount: !monetaryApplied && isPointsBenefit
      ? benefit.pointsAwarded
      : monetaryApplied
        ? discountGiven
        : 0,
    affiliate_code_id: code.codeId,
    affiliate_id: code.affiliateId,
    referral_status: acquires ? 'ATTRIBUTED' : 'PENDING',
  };
  writes.push({ kind: 'create', path: referralPaths.sale(merchantId, saleId), data: saleData });
  writes.push(...itemWrites);

  // A POINTS benefit survives the delay: points are an entry in a ledger, and
  // adding an entry to a ledger costs the customer nothing they have already
  // paid. This is the one benefit an uncached code can still earn.
  const pointsCredited =
    !monetaryApplied &&
    isPointsBenefit &&
    benefit.pointsAwarded > 0 &&
    facts.existingBonusLedger === null;
  if (pointsCredited) {
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

  let attributionData: DocumentData | null = null;
  let rewardData: DocumentData | null = null;
  let rewardSummary: OfflineReferralSummary['referral']['reward'] = null;

  if (acquires) {
    attributionData = {
      id: attributionId,
      merchant_id: merchantId,
      affiliate_id: code.affiliateId,
      affiliate_code_id: code.codeId,
      customer_id: input.customerId,
      first_sale_id: saleId,
      qualifying_sale_id: saleId,
      status: 'CONFIRMED' as AttributionStatus,
      rejection_reason: null,
      idempotency_key: attributionKey,
      attributed_at: input.now,
      created_at:
        facts.existingAttributionDoc === null
          ? input.now
          : num(facts.existingAttributionDoc, 'created_at') ?? input.now,
      updated_at: input.now,
    };
    writes.push({
      kind: facts.existingAttributionDoc === null ? 'create' : 'merge',
      path: referralPaths.attribution(merchantId, attributionId),
      data: attributionData,
    });

    // Only a confirmed acquisition spends the code, and only once. A later
    // arrival that finds the limit reached is refused above, which is exactly
    // the ordering rule the plan asks for: the earliest qualifying sale to
    // reach the server wins.
    writes.push({
      kind: 'merge',
      path: referralPaths.code(merchantId, code.codeId),
      data: { usage_count: code.usageCount + 1, updated_at: input.now },
    });

    const plannedReward = planFirstSaleReward(config);
    const rewardId = affiliateIds.reward(attributionId, 'FIRST_QUALIFYING_SALE');
    if (plannedReward !== null && facts.existingRewardDoc === null) {
      rewardData = {
        id: rewardId,
        merchant_id: merchantId,
        affiliate_id: code.affiliateId,
        attribution_id: attributionId,
        type: plannedReward.type,
        reward_type: plannedReward.type,
        value: plannedReward.value,
        value_type: plannedReward.valueType,
        status: plannedReward.status,
        approval_required: config.rewardApprovalRequired,
        trigger_sale_id: saleId,
        source_sale_id: saleId,
        idempotency_key: referralIdempotencyKeys.reward(
          attributionId,
          plannedReward.type,
        ),
        approved_by: null,
        approved_at: plannedReward.status === 'APPROVED' ? input.now : null,
        paid_at: null,
        cancelled_at: null,
        created_at: input.now,
        updated_at: input.now,
      };
      writes.push({
        kind: 'create',
        path: referralPaths.reward(merchantId, rewardId),
        data: rewardData,
      });
    } else if (plannedReward !== null && facts.existingRewardDoc !== null) {
      rewardData = { ...facts.existingRewardDoc, id: rewardId };
    }
    if (plannedReward !== null) {
      rewardSummary = {
        id: rewardId,
        type: plannedReward.type,
        value: plannedReward.value,
        status: (str(facts.existingRewardDoc, 'status') ?? plannedReward.status) as RewardStatus,
      };
    }

    const attributedEventId = affiliateIds.event(
      merchantId,
      'REFERRAL_ATTRIBUTED',
      saleId,
    );
    if (!facts.existingEventIds.has(attributedEventId)) {
      const write = eventWrite(merchantId, attributedEventId, {
        eventType: 'REFERRAL_ATTRIBUTED',
        affiliateId: code.affiliateId,
        customerId: input.customerId,
        saleId,
        dedupeKey: idempotencyKey,
        now: input.now,
        metadata: {
          attribution_id: attributionId,
          code_id: code.codeId,
          benefit_type: benefit.type,
          net_amount: netAmount,
          gross_amount: input.grossAmount,
          source: 'OFFLINE',
          monetary_benefit_applied: monetaryApplied,
          points_benefit_credited: pointsCredited,
          clock_skew_ms: clockSkewMs,
          clock_skew_exceeded: clockSkewMs > CLOCK_SKEW_SIGNAL_MS,
        },
      });
      writes.push(write);
      events.push(write.data);
    }

    const outboxId = affiliateIds.outbox(merchantId, 'affiliate_new_customer', saleId);
    if (!facts.existingOutboxIds.has(outboxId)) {
      writes.push({
        kind: 'create',
        path: referralPaths.outbox(merchantId, outboxId),
        data: {
          id: outboxId,
          merchant_id: merchantId,
          affiliate_id: code.affiliateId,
          template: 'affiliate_new_customer',
          source_key: saleId,
          status: 'QUEUED',
          attempts: 0,
          retry_count: 0,
          next_attempt_at: input.now,
          last_error: null,
          payload: {
            attribution_id: attributionId,
            reward_id: rewardSummary?.id ?? null,
            reward_points: rewardSummary?.value ?? 0,
            reward_status: rewardSummary?.status ?? null,
          },
          created_at: input.now,
          updated_at: input.now,
        },
      });
    }

    if (rewardSummary !== null) {
      const rewardEventId = affiliateIds.event(
        merchantId,
        'AFFILIATE_REWARD_CREATED',
        saleId,
      );
      if (!facts.existingEventIds.has(rewardEventId)) {
        const write = eventWrite(merchantId, rewardEventId, {
          eventType: 'AFFILIATE_REWARD_CREATED',
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
            source: 'OFFLINE',
          },
        });
        writes.push(write);
        events.push(write.data);
      }
    }
  }

  return {
    status: 'committed',
    writes,
    result: {
      sale: saleData,
      referral: {
        affiliate_id: code.affiliateId,
        affiliate_code_id: code.codeId,
        normalized_code: normalizedCode,
        benefit: {
          type: appliedMonetaryBenefit?.type ?? benefit.type,
          value: appliedMonetaryBenefit?.value ?? benefit.value,
          discount_amount: monetaryApplied ? discountGiven : 0,
          points_awarded: pointsCredited ? benefit.pointsAwarded : 0,
          display_text: monetaryApplied
            ? `${discountGiven} MT de desconto`
            : benefit.displayText,
        },
        attribution: attributionData,
        attribution_id: acquires ? attributionId : null,
        attribution_status: acquires ? 'CONFIRMED' : null,
        reward_record: rewardData,
        reward: rewardSummary,
        monetary_benefit_applied: monetaryApplied,
        retroactive_discount_applied: false,
        points_benefit_credited: pointsCredited,
      },
      events,
      idempotency_key: idempotencyKey,
      clock_skew_ms: clockSkewMs,
    },
  };
}

/**
 * What a refusal writes: the sale, the discount already given, and the reason.
 *
 * Deliberately not "nothing", which is what the online commit writes when it
 * refuses. There the sale does not exist yet and refusing costs nobody
 * anything. Here the sale exists whether the server likes it or not, and the
 * only question left is whether the business can find out why it happened.
 */
function planRefusal(params: {
  facts: ReferralSaleFacts;
  input: OfflineReferralSaleInput;
  config: AffiliateConfig;
  saleId: string;
  attributionId: string;
  attributionKey: string;
  idempotencyKey: string;
  normalizedCode: string;
  reason: ReferralReason;
  discountGiven: number;
  saleBase: DocumentData;
  itemWrites: WriteOperation[];
  loyalty: { pointsPerMzn: number; configVersion: number };
  clockSkewMs: number;
}): OfflineReferralSalePlan {
  const { facts, input, saleId, reason } = params;
  const merchantId = input.merchantId;
  const benefitKept = params.discountGiven > 0;
  const netAmount = benefitKept
    ? (cents(input.grossAmount) - cents(params.discountGiven)) / 100
    : input.grossAmount;
  const points = calculateSalePoints(netAmount, params.loyalty.pointsPerMzn);
  const applied = input.appliedBenefit;
  const affiliateId = facts.lookup?.affiliateId ?? null;
  const codeId = facts.lookup?.codeId ?? null;

  const writes: WriteOperation[] = [];
  const events: DocumentData[] = [];

  const saleData: DocumentData = {
    ...params.saleBase,
    amount: netAmount,
    points,
    // The benefit the customer actually received is recorded even though the
    // code was refused, because it is what the receipt says and what the books
    // have to agree with.
    referral_benefit_type: benefitKept && applied !== null ? applied.type : null,
    referral_benefit_value: benefitKept && applied !== null ? applied.value : null,
    referral_benefit_amount: benefitKept ? params.discountGiven : null,
    affiliate_code_id: codeId,
    affiliate_id: affiliateId,
    referral_status: 'REJECTED',
    referral_rejection_reason: reason,
  };
  writes.push({ kind: 'create', path: referralPaths.sale(merchantId, saleId), data: saleData });
  writes.push(...params.itemWrites);

  // A rejected attribution is only written when this customer has no live one.
  // Overwriting a confirmed acquisition with somebody else's refusal would take
  // an affiliate's customer away from them, which is precisely what
  // `CUSTOMER_ALREADY_REFERRED` is refusing to allow.
  let attributionData: DocumentData | null = null;
  if (affiliateId !== null && codeId !== null && facts.existingAttributionDoc === null) {
    attributionData = {
      id: params.attributionId,
      merchant_id: merchantId,
      affiliate_id: affiliateId,
      affiliate_code_id: codeId,
      customer_id: input.customerId,
      first_sale_id: saleId,
      qualifying_sale_id: saleId,
      status: 'REJECTED' as AttributionStatus,
      rejection_reason: reason,
      rejection_code: reason,
      idempotency_key: params.attributionKey,
      attributed_at: input.now,
      created_at: input.now,
      updated_at: input.now,
    };
    writes.push({
      kind: 'create',
      path: referralPaths.attribution(merchantId, params.attributionId),
      data: attributionData,
    });
  }

  const rejectionEventId = affiliateIds.event(
    merchantId,
    'REFERRAL_REJECTED',
    params.idempotencyKey,
  );
  if (!facts.existingEventIds.has(rejectionEventId)) {
    const write = eventWrite(merchantId, rejectionEventId, {
      eventType: 'REFERRAL_REJECTED',
      affiliateId,
      customerId: input.customerId,
      saleId,
      dedupeKey: params.idempotencyKey,
      now: input.now,
      metadata: {
        code_id: codeId,
        reason,
        stage: 'OFFLINE_SYNC',
        benefit_retained: benefitKept,
        retained_amount: benefitKept ? params.discountGiven : 0,
        clock_skew_ms: params.clockSkewMs,
        clock_skew_exceeded: params.clockSkewMs > CLOCK_SKEW_SIGNAL_MS,
      },
    });
    writes.push(write);
    events.push(write.data);
  }

  // One signal per refused offline sale, keyed by the sale so a replay of the
  // same reconciliation does not look like a second incident.
  writes.push(
    fraudSignalWrite(
      merchantId,
      affiliateIds.fraudSignal(merchantId, 'OFFLINE_CODE_REJECTED', saleId),
      {
        affiliateId,
        customerId: input.customerId,
        saleId,
        // A refusal that cost the business money is worth more attention than
        // one that cost it nothing.
        severity: benefitKept ? 'HIGH' : 'MEDIUM',
        metadata: {
          reason,
          code_id: codeId,
          benefit_retained: benefitKept,
          retained_amount: benefitKept ? params.discountGiven : 0,
          device_id: input.deviceId,
          clock_skew_ms: params.clockSkewMs,
        },
        now: input.now,
      },
    ),
  );

  return {
    status: 'rejected',
    writes,
    reason,
    message: REFERRAL_REASON_MESSAGE[reason],
    result: {
      sale: saleData,
      referral: {
        affiliate_id: affiliateId,
        affiliate_code_id: codeId,
        normalized_code: params.normalizedCode,
        benefit: benefitKept && applied !== null
          ? {
              type: applied.type,
              value: applied.value,
              discount_amount: params.discountGiven,
              points_awarded: 0,
              display_text: '',
            }
          : emptyBenefitSummary(),
        attribution: attributionData,
        attribution_id: attributionData === null ? null : params.attributionId,
        attribution_status: attributionData === null ? null : 'REJECTED',
        reward_record: null,
        reward: null,
        monetary_benefit_applied: benefitKept,
        retroactive_discount_applied: false,
        points_benefit_credited: false,
      },
      events,
      idempotency_key: params.idempotencyKey,
      clock_skew_ms: params.clockSkewMs,
    },
  };
}

function replaySummary(
  facts: ReferralSaleFacts,
  input: OfflineReferralSaleInput,
  saleId: string,
  attributionId: string,
  idempotencyKey: string,
  extra: { normalizedCode: string; clockSkewMs: number },
): OfflineReferralSummary {
  const sale = facts.existingSale ?? {};
  const benefitType = str(sale, 'referral_benefit_type') as BenefitType | null;
  const benefitAmount = num(sale, 'referral_benefit_amount') ?? 0;
  const attributionStatus = attributionStatusOf(facts.existingAttributionDoc);
  const reward = facts.existingRewardDoc;

  return {
    sale: { ...sale, id: saleId },
    referral: {
      affiliate_id: str(sale, 'affiliate_id'),
      affiliate_code_id: str(sale, 'affiliate_code_id'),
      normalized_code: extra.normalizedCode,
      benefit: {
        type: benefitType,
        value: num(sale, 'referral_benefit_value') ?? 0,
        discount_amount: benefitType === 'POINTS' ? 0 : benefitAmount,
        points_awarded: benefitType === 'POINTS' ? benefitAmount : 0,
        display_text: '',
      },
      attribution:
        facts.existingAttributionDoc === null
          ? null
          : { ...facts.existingAttributionDoc, id: attributionId },
      attribution_id: attributionStatus === null ? null : attributionId,
      attribution_status: attributionStatus,
      reward_record: reward,
      reward:
        reward === null
          ? null
          : {
              id: str(reward, 'id') ?? '',
              type: str(reward, 'type', 'reward_type') ?? '',
              value: num(reward, 'value') ?? 0,
              status: ((str(reward, 'status') ?? 'PENDING').toUpperCase() as RewardStatus),
            },
      monetary_benefit_applied: benefitType !== null && benefitType !== 'POINTS' && benefitAmount > 0,
      retroactive_discount_applied: false,
      points_benefit_credited: benefitType === 'POINTS' && benefitAmount > 0,
    },
    events: [],
    idempotency_key: idempotencyKey,
    clock_skew_ms: extra.clockSkewMs,
  };
}

/* ----------------------------------------------------------------- command */

/** Read, decide, write, once — the same shape as the online commit. */
export async function commitOfflineReferralSale(
  gateway: ReferralSaleGateway,
  input: OfflineReferralSaleInput,
  loadConfig: (business: DocumentData | null) => AffiliateConfig,
): Promise<OfflineReferralSaleOutcome> {
  return gateway.runTransaction(async (transaction) => {
    const facts = await readReferralSaleFacts(transaction, input);
    const plan = planOfflineReferralSale(facts, input, loadConfig(facts.business));

    for (const operation of plan.writes) {
      if (operation.kind === 'create') transaction.create(operation.path, operation.data);
      else transaction.merge(operation.path, operation.data);
    }

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
          result: plan.result,
        };
      case 'conflict':
        return { status: 'conflict' as const };
      default:
        return { status: 'deferred' as const };
    }
  });
}
