import { createHash } from 'crypto';

import {
  PERCENTAGE_RANGE,
  type AffiliateConfig,
  type AffiliateStatus,
  type AffiliateLinkStatus,
  type AttributionStatus,
  type BenefitType,
  type ReferralReason,
  type RewardType,
  type RewardValueType,
} from './affiliate_contracts.js';

/**
 * The referral engine, as functions with no I/O.
 *
 * Every decision the feature makes lives here: whether a code may be used, what
 * it is worth, what the resulting ids are. Reading and writing happen in the
 * route and transaction layers, which call into this file and never re-decide
 * anything themselves.
 *
 * That split is what makes the commit path trustworthy. §5.5 of the prompt
 * requires the sale transaction to re-run every check against the real sale
 * rather than trust what the preview said — and it can only be the *same*
 * check if the check is a function both sides call.
 */

/* ------------------------------------------------------------------- codes */

/**
 * The suffix alphabet, missing 0, O, 1, I and L on purpose.
 *
 * Codes are read aloud across a counter and typed by someone in a hurry. The
 * pairs that get confused are left out rather than corrected afterwards.
 */
export const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const CODE_SUFFIX_LENGTH = 4;
export const CODE_NAME_MAX = 8;

/**
 * How a typed code is matched.
 *
 * Outer spaces only: a code is one token, so collapsing inner whitespace would
 * quietly accept something that is not the code. Upper-cased because the stored
 * form is upper-case, and lookup is by exact key on the normalised value.
 */
export function normalizeAffiliateCode(raw: string): string {
  return raw.trim().toUpperCase();
}

/**
 * The name segment: ASCII-folded, letters and digits only, capped.
 *
 * "João" becomes JOAO rather than JO?O — a code nobody can dictate over the
 * phone is a code nobody uses.
 */
export function foldCodeName(rawName: string): string {
  const first = rawName.trim().split(/\s+/)[0] ?? '';
  const folded = first
    .normalize('NFD')
    // Strip combining marks left behind by the decomposition.
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
  return folded.slice(0, CODE_NAME_MAX);
}

/**
 * Builds `AFI-{NAME}-{XXXX}`.
 *
 * A name that folds away to nothing — punctuation, or a script with no ASCII
 * equivalent — still has to produce a usable code, so it falls back to a fixed
 * segment rather than yielding `AFI--XXXX`.
 */
export function buildAffiliateCode(rawName: string, suffix: string): string {
  const name = foldCodeName(rawName) || 'AFILIADO';
  return `AFI-${name}-${suffix}`;
}

/**
 * Four characters from [CODE_ALPHABET].
 *
 * `randomByte` is injected so a test can pin the output; production passes a
 * CSPRNG. Bytes are rejected past the largest whole multiple of the alphabet
 * size rather than taken modulo, which would make the first few characters
 * measurably more likely.
 */
export function generateCodeSuffix(
  randomByte: () => number,
  length = CODE_SUFFIX_LENGTH,
): string {
  const limit = Math.floor(256 / CODE_ALPHABET.length) * CODE_ALPHABET.length;
  let out = '';
  let guard = 0;
  while (out.length < length) {
    if (guard++ > 1000) throw new Error('Code suffix generation made no progress');
    const byte = randomByte() & 0xff;
    if (byte >= limit) continue;
    out += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  }
  return out;
}

/* --------------------------------------------------------------------- ids */

function digest(parts: string[]): string {
  return createHash('sha256').update(parts.join('\u001f')).digest('hex').slice(0, 40);
}

/**
 * Deterministic ids, which is how uniqueness is enforced.
 *
 * Firestore has no partial unique index, so "one active attribution per
 * customer" has to be a document that can only exist once. Deriving the id from
 * the pair turns a uniqueness constraint into a primary key, and a concurrent
 * duplicate becomes a lost create rather than a second row.
 *
 * None of these take a phone number. An id is stored, logged and read by people
 * who have no business learning a customer's number from it.
 */
export const affiliateIds = {
  link: (affiliateId: string, merchantId: string) =>
    `am_${digest([affiliateId, merchantId])}`,

  /** One code per affiliate–merchant pair in the MVP, so the same shape. */
  code: (affiliateId: string, merchantId: string) =>
    `ac_${digest([affiliateId, merchantId])}`,

  /** One live attribution per customer per business. */
  attribution: (merchantId: string, customerId: string) =>
    `aa_${digest([merchantId, customerId])}`,

  /** One reward per attribution per type. */
  reward: (attributionId: string, type: RewardType) =>
    `ar_${digest([attributionId, type])}`,

  /** The global lookup key, which is the normalised code itself. */
  lookup: (code: string) => normalizeAffiliateCode(code),

  /**
   * The sale a till commits, derived from the till and the sale's local id.
   *
   * The same pair that makes `saleIdempotencyKey` makes the document, so a
   * replay resolves to the sale already written instead of creating a second
   * one under a fresh uuid. The till keeps its own local id; the canonical id
   * comes back in the response.
   */
  sale: (deviceId: string, localSaleId: string) =>
    `sale_${digest([deviceId, localSaleId])}`,

  /**
   * One event per fact, so a retry appends nothing.
   *
   * `sourceKey` is whatever makes the fact unique — a sale id for an
   * attribution, an idempotency key for a refusal. Never a phone number.
   */
  event: (merchantId: string, eventType: string, sourceKey: string) =>
    `ae_${digest([merchantId, eventType, sourceKey])}`,

  /** One queued message per fact, for the worker Phase 5 will add. */
  outbox: (merchantId: string, template: string, sourceKey: string) =>
    `ao_${digest([merchantId, template, sourceKey])}`,

  /** One signal per fact a person has to look at. */
  fraudSignal: (merchantId: string, signalType: string, sourceKey: string) =>
    `afs_${digest([merchantId, signalType, sourceKey])}`,
};

/**
 * The key that makes a sale commit replay-safe.
 *
 * Derived from the till and the sale's local id, so a retry after a dropped
 * response resolves to the work already done instead of a second sale.
 */
export function saleIdempotencyKey(deviceId: string, localSaleId: string): string {
  return `sale:${deviceId}:${localSaleId}`;
}

/**
 * What a replay has to match to be the same request.
 *
 * A till that retries after a dropped response sends the same sale again and
 * must get the same answer. A till that reuses the same local id for a
 * *different* sale — a bug, or a tampered request — must not silently take
 * over the committed one, so everything immutable about the request is folded
 * into one value and stored beside the sale.
 *
 * Money is compared in centavos: 100 and 100.00 are the same sale, and
 * comparing floats as text would say otherwise.
 */
export function referralRequestFingerprint(input: {
  merchantId: string;
  customerId: string;
  grossAmount: number;
  normalizedCode: string;
  items: Array<{
    id: string;
    merchantItemId: string;
    nameSnapshot: string;
    typeSnapshot: string;
    quantity: number;
    unitPrice: number | null;
    subtotal: number | null;
  }>;
}): string {
  const items = [...input.items]
    .map((item) =>
      digest([
        item.id,
        item.merchantItemId,
        item.nameSnapshot,
        item.typeSnapshot,
        String(item.quantity),
        item.unitPrice === null
          ? 'null'
          : String(Math.round(item.unitPrice * 100)),
        item.subtotal === null
          ? 'null'
          : String(Math.round(item.subtotal * 100)),
      ]),
    )
    .sort();
  return digest([
    input.merchantId,
    input.customerId,
    String(Math.round(input.grossAmount * 100)),
    input.normalizedCode,
    items.join(','),
  ]);
}

/* -------------------------------------------------------------- validation */

export type ReferralCodeSnapshot = {
  codeId: string;
  merchantId: string;
  affiliateId: string;
  /**
   * Mirrors the stored enum rather than collapsing it to a boolean.
   *
   * AffiliateCodeStatus in affiliate_code.dart is ACTIVE|DISABLED, and a mapper
   * writing `enabled = status !== 'DISABLED'` and one writing
   * `enabled = status === 'ACTIVE'` read identically and disagree the day a
   * third state exists. Reading the enum has no such polarity to get backwards.
   */
  status: 'ACTIVE' | 'DISABLED';
  /** Named for the stored column, `starts_at`. */
  startsAt: number;
  expiresAt: number;
  usageLimit: number | null;
  usageCount: number;
  firstVisitOnly: boolean;
  benefitType: BenefitType;
  benefitValue: number;
};

export type ReferralContext = {
  /** The business the request is acting as; never taken from the client. */
  merchantId: string;
  now: number;
  affiliateStatus: AffiliateStatus;
  linkStatus: AffiliateLinkStatus;
  /** Already HMAC-derived or normalised; compared, never printed. */
  affiliatePhoneHash: string;
  customerPhoneHash: string;
  /** §5.2 — no prior sale, no prior attribution, not blocked, not a test. */
  customerIsNew: boolean;
  /** The status of any attribution this customer already has, if any. */
  existingAttributionStatus: AttributionStatus | null;
  /** Null at preview time: the amount is not known until the sale exists. */
  saleAmount: number | null;
};

export type ReferralValidation =
  | { ok: true }
  | { ok: false; reason: ReferralReason };

/**
 * §5.1, in order, returning the first failure.
 *
 * The order is not arbitrary and is not an implementation detail: a disabled
 * code that is also expired must say "desativado", because that is the one the
 * merchant can act on. Reordering these changes what a cashier is told.
 *
 * Called by both the preview and the commit. The preview is advisory — nothing
 * is reserved by it — so the commit runs this again inside the transaction
 * against the real sale.
 */
export function validateReferral(
  code: ReferralCodeSnapshot | null,
  context: ReferralContext,
): ReferralValidation {
  const fail = (reason: ReferralReason): ReferralValidation => ({ ok: false, reason });

  // A code belonging to another business is indistinguishable from one that
  // does not exist. Anything else lets a caller probe for other businesses.
  if (code === null || code.merchantId !== context.merchantId) {
    return fail('CODE_NOT_FOUND');
  }
  if (code.status !== 'ACTIVE') return fail('CODE_DISABLED');
  if (context.now < code.startsAt) return fail('CODE_NOT_STARTED');
  if (context.now >= code.expiresAt) return fail('CODE_EXPIRED');
  if (code.usageLimit !== null && code.usageCount >= code.usageLimit) {
    return fail('CODE_USAGE_LIMIT_REACHED');
  }
  if (context.affiliateStatus !== 'ACTIVE' || context.linkStatus !== 'ACTIVE') {
    return fail('AFFILIATE_INACTIVE');
  }
  if (
    context.affiliatePhoneHash !== '' &&
    context.affiliatePhoneHash === context.customerPhoneHash
  ) {
    return fail('SELF_REFERRAL_NOT_ALLOWED');
  }
  if (code.firstVisitOnly && !context.customerIsNew) {
    return fail('CUSTOMER_NOT_ELIGIBLE');
  }
  // A rejected attribution is not a claim on the customer; anything else is.
  if (
    context.existingAttributionStatus !== null &&
    context.existingAttributionStatus !== 'REJECTED'
  ) {
    return fail('CUSTOMER_ALREADY_REFERRED');
  }
  if (!isBenefitValid(code, context.saleAmount)) return fail('BENEFIT_INVALID');

  return { ok: true };
}

/**
 * §5.4. At preview time the sale does not exist yet, so a null amount checks
 * only what can be checked without it — the code's own shape.
 */
export function isBenefitValid(
  code: Pick<ReferralCodeSnapshot, 'benefitType' | 'benefitValue'>,
  saleAmount: number | null,
): boolean {
  if (!Number.isFinite(code.benefitValue) || code.benefitValue <= 0) return false;

  switch (code.benefitType) {
    case 'PERCENTAGE':
      return (
        code.benefitValue >= PERCENTAGE_RANGE.min &&
        code.benefitValue <= PERCENTAGE_RANGE.max
      );
    case 'FIXED_AMOUNT':
      if (saleAmount === null) return true;
      return saleAmount > 0 && code.benefitValue <= saleAmount;
    case 'POINTS':
      return Number.isInteger(code.benefitValue);
  }
}

/* --------------------------------------------------------------- eligibility */

export type CustomerEligibilityInput = {
  hasPreviousCompletedSale: boolean;
  hasNonRejectedAttribution: boolean;
  /** Another customer record shares the normalised phone. */
  phoneAlreadyKnown: boolean;
  isAffiliate: boolean;
  isTestAccount: boolean;
  isBlocked: boolean;
};

/** §5.2. Every clause disqualifies; none of them is a warning. */
export function isNewCustomer(input: CustomerEligibilityInput): boolean {
  return (
    !input.hasPreviousCompletedSale &&
    !input.hasNonRejectedAttribution &&
    !input.phoneAlreadyKnown &&
    !input.isAffiliate &&
    !input.isTestAccount &&
    !input.isBlocked
  );
}

export type SaleQualificationInput = {
  belongsToMerchant: boolean;
  hasCustomer: boolean;
  amount: number;
  isCompleted: boolean;
  isCancelled: boolean;
  isRefunded: boolean;
  isReversed: boolean;
  isDuplicate: boolean;
  meetsMinimumAmount: boolean;
};

/** §5.3. */
export function isQualifyingSale(input: SaleQualificationInput): boolean {
  return (
    input.belongsToMerchant &&
    input.hasCustomer &&
    input.amount > 0 &&
    input.isCompleted &&
    !input.isCancelled &&
    !input.isRefunded &&
    !input.isReversed &&
    !input.isDuplicate &&
    input.meetsMinimumAmount
  );
}

/* ----------------------------------------------------------------- benefit */

export type CalculatedBenefit = {
  type: BenefitType;
  /** What the code declares — a percentage, an amount, or a points count. */
  value: number;
  /** Money taken off this sale. Always 0 for a POINTS benefit. */
  discountAmount: number;
  /** Extra loyalty points for the customer. Always 0 for a money benefit. */
  pointsAwarded: number;
  /** What the sale is finally charged at. */
  netAmount: number;
  /** One short line for a receipt or a confirmation sheet. */
  displayText: string;
};

/**
 * Computed on the server and never sent by the client, which posts only a code.
 *
 * Percentages are worked in centavos and rounded down, so a discount can never
 * come out a centavo larger than the percentage allows. The floor is also what
 * keeps `netAmount` from drifting below zero on a rounding edge.
 *
 * `amount` keeps meaning what it has always meant — what the customer actually
 * paid — so loyalty points are earned on `netAmount` and nothing about the
 * existing sale path changes for a sale with no code.
 */
export function calculateBenefit(
  code: Pick<ReferralCodeSnapshot, 'benefitType' | 'benefitValue'>,
  grossAmount: number,
): CalculatedBenefit {
  const gross = Math.max(0, grossAmount);

  if (code.benefitType === 'POINTS') {
    const points = Math.floor(code.benefitValue);
    return {
      type: 'POINTS',
      value: points,
      discountAmount: 0,
      pointsAwarded: points,
      netAmount: gross,
      displayText: `${formatPoints(points)} pontos extra`,
    };
  }

  const grossCents = Math.round(gross * 100);
  const rawCents =
    code.benefitType === 'PERCENTAGE'
      ? Math.floor((grossCents * code.benefitValue) / 100)
      : Math.round(code.benefitValue * 100);
  // Never more than the sale: a discount larger than the bill would turn into
  // money owed to the customer, which this product does not do.
  const discountCents = Math.min(Math.max(0, rawCents), grossCents);
  const discountAmount = discountCents / 100;

  return {
    type: code.benefitType,
    value: code.benefitValue,
    discountAmount,
    pointsAwarded: 0,
    netAmount: (grossCents - discountCents) / 100,
    displayText:
      code.benefitType === 'PERCENTAGE'
        ? `${code.benefitValue}% de desconto (${formatMoney(discountAmount)})`
        : `${formatMoney(discountAmount)} de desconto`,
  };
}

function formatMoney(value: number): string {
  const whole = Number.isInteger(value) ? value.toFixed(0) : value.toFixed(2);
  return `${whole} MT`;
}

function formatPoints(value: number): string {
  return value.toLocaleString('pt-PT');
}

/* ----------------------------------------------------------------- rewards */

export type PlannedReward = {
  type: RewardType;
  value: number;
  valueType: RewardValueType;
  status: 'PENDING' | 'APPROVED';
};

/**
 * The reward a confirmed acquisition earns.
 *
 * Returns null when the business has affiliates on but has left the reward at
 * zero — a reward of nothing is not a reward, and writing one would put a row
 * in the approvals queue that means nothing.
 */
export function planFirstSaleReward(config: AffiliateConfig): PlannedReward | null {
  if (config.firstSaleRewardPoints <= 0) return null;
  return {
    type: 'FIRST_QUALIFYING_SALE',
    value: Math.floor(config.firstSaleRewardPoints),
    valueType: 'POINTS',
    status: config.rewardApprovalRequired ? 'PENDING' : 'APPROVED',
  };
}

/**
 * §5.6. A return reward exists only inside the window, counted from the first
 * qualifying sale — not from the attribution, which can be written later.
 */
export function planReturnReward(
  config: AffiliateConfig,
  firstSaleAt: number,
  returnSaleAt: number,
): PlannedReward | null {
  if (!config.returnRewardEnabled) return null;
  if (config.returnRewardPoints <= 0) return null;
  if (!isWithinReturnWindow(config, firstSaleAt, returnSaleAt)) return null;
  return {
    type: 'CUSTOMER_RETURN',
    value: Math.floor(config.returnRewardPoints),
    valueType: 'POINTS',
    status: config.rewardApprovalRequired ? 'PENDING' : 'APPROVED',
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

export function isWithinReturnWindow(
  config: AffiliateConfig,
  firstSaleAt: number,
  returnSaleAt: number,
): boolean {
  if (returnSaleAt < firstSaleAt) return false;
  return returnSaleAt - firstSaleAt <= config.returnWindowDays * DAY_MS;
}

/**
 * Which rewards a cancellation may take back.
 *
 * `PAID` is deliberately excluded: money or points already handed over are not
 * undone by a status change, so those surface for a person to deal with. The
 * caller is expected to raise them rather than ignore the list.
 */
export function rewardsAffectedByCancellation(
  rewards: Array<{ id: string; status: string }>,
): { cancellable: string[]; needsManualReview: string[] } {
  const cancellable: string[] = [];
  const needsManualReview: string[] = [];
  for (const reward of rewards) {
    const status = (reward.status ?? '').toUpperCase();
    if (status === 'PENDING' || status === 'APPROVED') cancellable.push(reward.id);
    else if (status === 'PAID') needsManualReview.push(reward.id);
  }
  return { cancellable, needsManualReview };
}

/* ----------------------------------------------------------------- metrics */

export type AffiliateMetricsInput = {
  /** Distinct validation attempts; replays of one idempotency key count once. */
  uniqueValidationAttempts: number;
  confirmedAttributions: number;
  rejectedAttributions: number;
  returnedCustomers: number;
  pendingRewardCount: number;
  pendingRewardPoints: number;
  approvedRewardCount: number;
  approvedRewardPoints: number;
  lastEventAt: number | null;
};

export type AffiliateMetrics = AffiliateMetricsInput & {
  /** 0 when nothing has been attempted — not NaN, and not hidden. */
  conversionRate: number;
};

/** §D14. Carries no phone, name or customer id: this payload is analytics. */
export function summarizeAffiliateMetrics(
  input: AffiliateMetricsInput,
): AffiliateMetrics {
  const attempts = Math.max(0, input.uniqueValidationAttempts);
  return {
    ...input,
    conversionRate:
      attempts === 0 ? 0 : Math.max(0, input.confirmedAttributions) / attempts,
  };
}
