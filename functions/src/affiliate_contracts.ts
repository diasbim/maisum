/**
 * The vocabulary of the referral engine, in one place.
 *
 * Everything here is a stored value or a wire value: statuses that land in
 * Firestore, reason codes that reach a screen, event names the Retention Engine
 * matches on. Changing a string in this file changes stored data, so none of
 * them is cosmetic.
 *
 * The Portuguese lives here too, beside the code it explains. `engage_labels.dart`
 * and `merchant-labels.ts` keep the same arrangement: a stored enum and the
 * words a merchant reads, written down together so they cannot drift apart
 * quietly.
 */

/* ------------------------------------------------------------------ status */

export const AFFILIATE_STATUS = ['ACTIVE', 'INACTIVE', 'SUSPENDED'] as const;
export type AffiliateStatus = (typeof AFFILIATE_STATUS)[number];

export const AFFILIATE_LINK_STATUS = ['ACTIVE', 'INACTIVE'] as const;
export type AffiliateLinkStatus = (typeof AFFILIATE_LINK_STATUS)[number];

export const ATTRIBUTION_STATUS = ['CONFIRMED', 'REJECTED', 'CANCELLED'] as const;
export type AttributionStatus = (typeof ATTRIBUTION_STATUS)[number];

export const REWARD_STATUS = ['PENDING', 'APPROVED', 'PAID', 'CANCELLED'] as const;
export type RewardStatus = (typeof REWARD_STATUS)[number];

export const REWARD_TYPE = ['FIRST_QUALIFYING_SALE', 'CUSTOMER_RETURN'] as const;
export type RewardType = (typeof REWARD_TYPE)[number];

/**
 * `FIXED_AMOUNT` is declared but unused by the MVP's reward side: an affiliate
 * balance is points only. It exists because the data model is meant to stay
 * open to a money reward later, and widening a stored enum afterwards is the
 * expensive kind of change.
 */
export const REWARD_VALUE_TYPE = ['POINTS', 'FIXED_AMOUNT'] as const;
export type RewardValueType = (typeof REWARD_VALUE_TYPE)[number];

export const BENEFIT_TYPE = ['FIXED_AMOUNT', 'PERCENTAGE', 'POINTS'] as const;
export type BenefitType = (typeof BENEFIT_TYPE)[number];

/* ------------------------------------------------------------- reason codes */

/**
 * Why a code cannot be used, in the order the checks run.
 *
 * A code that belongs to another business answers `CODE_NOT_FOUND`, never
 * `AFFILIATE_INACTIVE` or anything else specific: a distinguishable answer is
 * a way to enumerate another business's codes.
 */
export const REFERRAL_REASON = [
  'CODE_NOT_FOUND',
  'CODE_DISABLED',
  'CODE_NOT_STARTED',
  'CODE_EXPIRED',
  'CODE_USAGE_LIMIT_REACHED',
  'AFFILIATE_INACTIVE',
  'SELF_REFERRAL_NOT_ALLOWED',
  'CUSTOMER_NOT_ELIGIBLE',
  'CUSTOMER_ALREADY_REFERRED',
  'BENEFIT_INVALID',
] as const;
export type ReferralReason = (typeof REFERRAL_REASON)[number];

/**
 * What the cashier reads, with the customer waiting.
 *
 * Short, and every one of them says what to do next rather than what went
 * wrong internally. None names another business, a phone number or an id.
 */
export const REFERRAL_REASON_MESSAGE: Record<ReferralReason, string> = {
  CODE_NOT_FOUND: 'Código não encontrado. Confirme com o cliente.',
  CODE_DISABLED: 'Este código está desativado.',
  CODE_NOT_STARTED: 'Este código ainda não começou a valer.',
  CODE_EXPIRED: 'Este código expirou.',
  CODE_USAGE_LIMIT_REACHED: 'Este código atingiu o limite de utilizações.',
  AFFILIATE_INACTIVE: 'O afiliado deste código não está ativo.',
  SELF_REFERRAL_NOT_ALLOWED: 'Um afiliado não pode indicar-se a si próprio.',
  CUSTOMER_NOT_ELIGIBLE: 'Este código é só para clientes novos.',
  CUSTOMER_ALREADY_REFERRED: 'Este cliente já foi indicado por outro afiliado.',
  BENEFIT_INVALID: 'O desconto não se aplica a esta venda.',
};

/* ------------------------------------------------------------------ events */

/**
 * One list, used by the engine, the Retention Engine and both clients.
 *
 * Append-only in storage, so a rename here orphans history.
 */
export const AFFILIATE_EVENT = [
  'AFFILIATE_CREATED',
  'AFFILIATE_CODE_CREATED',
  'REFERRAL_CODE_VALIDATED',
  'REFERRAL_ATTRIBUTED',
  'REFERRAL_REJECTED',
  'AFFILIATE_REWARD_CREATED',
  'AFFILIATE_REWARD_APPROVED',
  'AFFILIATE_REWARD_CANCELLED',
  'REFERRED_CUSTOMER_RETURNED',
] as const;
export type AffiliateEventType = (typeof AFFILIATE_EVENT)[number];

/**
 * The events that may only be published after the sale transaction commits.
 *
 * Publishing inside the transaction would send a WhatsApp message about a sale
 * that a later rollback un-made.
 */
export const POST_COMMIT_EVENTS: readonly AffiliateEventType[] = [
  'REFERRAL_ATTRIBUTED',
  'REFERRED_CUSTOMER_RETURNED',
  'AFFILIATE_REWARD_CREATED',
];

/* ------------------------------------------------------------ fraud signals */

export const FRAUD_SIGNAL = [
  /** A code accepted offline that the server then refused. */
  'OFFLINE_CODE_REJECTED',
  /** Repeated failed validations from one till in a short window. */
  'VALIDATION_BURST',
  /** The customer's phone matches the affiliate's. */
  'SELF_REFERRAL_ATTEMPT',
  /** A second attribution arrived for a customer who already had one. */
  'DUPLICATE_ATTRIBUTION_ATTEMPT',
] as const;
export type FraudSignalType = (typeof FRAUD_SIGNAL)[number];

export const FRAUD_SEVERITY = ['LOW', 'MEDIUM', 'HIGH'] as const;
export type FraudSeverity = (typeof FRAUD_SEVERITY)[number];

/* ------------------------------------------------------------------ config */

/** Per-business settings. The defaults are the ones the plan fixes. */
export type AffiliateConfig = {
  enabled: boolean;
  /** Must be > 0 to enable affiliates at all: a reward of zero is not one. */
  firstSaleRewardPoints: number;
  returnRewardEnabled: boolean;
  returnRewardPoints: number;
  returnWindowDays: number;
  rewardApprovalRequired: boolean;
  notificationsEnabled: boolean;
};

export const DEFAULT_AFFILIATE_CONFIG: AffiliateConfig = {
  enabled: false,
  firstSaleRewardPoints: 0,
  returnRewardEnabled: false,
  returnRewardPoints: 0,
  returnWindowDays: 30,
  rewardApprovalRequired: true,
  notificationsEnabled: true,
};

/** A percentage benefit outside this range is refused when the code is saved. */
export const PERCENTAGE_RANGE = { min: 1, max: 50 } as const;

/** How long a new code lasts unless the merchant says otherwise. */
export const DEFAULT_CODE_VALIDITY_DAYS = 30;
