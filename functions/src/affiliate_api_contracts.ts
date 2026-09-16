import {
  AFFILIATE_CODE_STATUS,
  AFFILIATE_STATUS,
  BENEFIT_TYPE,
  PERCENTAGE_RANGE,
  REFERRAL_REASON_MESSAGE,
  REWARD_STATUS,
  type AffiliateCodeStatus,
  type AffiliateLinkStatus,
  type AffiliateStatus,
  type BenefitType,
  type ReferralReason,
  type RewardStatus,
} from './affiliate_contracts.js';
import { maskPhone } from './affiliate_notifications.js';
import { asBool, asEpoch, asNumber, asString } from './merchant_records.js';

/**
 * The wire shape of `/merchant/affiliate*` and `/admin/affiliate*`, and the
 * only place an incoming field is allowed to be interpreted.
 *
 * Two rules shape everything here.
 *
 * The first is that a field is read exactly once, by a function that either
 * returns a value or returns a refusal with a stable code. There is no
 * `?? default` anywhere in a route: a benefit value of `"cinquenta"` must not
 * silently become the default benefit, and a percentage of `500` must not
 * quietly become 50. Both are refusals, and both name the field.
 *
 * The second is that the client never states what something is worth. The
 * benefit lives on the code, the reward value comes from the business's
 * settings, and an approval carries no amount — a request that sends one is
 * not honoured, it is simply not read. That is why `parseRewardDecision` takes
 * no value at all.
 *
 * The Portuguese lives beside the code that raises it, in the arrangement
 * `affiliate_contracts.ts` already uses for reason codes.
 */

/* ------------------------------------------------------------------ errors */

export type AffiliateApiFailure = {
  status: 400 | 403 | 404 | 409 | 429 | 500;
  /** Stable, machine-readable, and safe to branch on in a client. */
  code: string;
  message: string;
};

export class AffiliateApiError extends Error {
  readonly status: AffiliateApiFailure['status'];
  readonly code: string;

  constructor(failure: AffiliateApiFailure) {
    super(failure.message);
    this.name = 'AffiliateApiError';
    this.status = failure.status;
    this.code = failure.code;
  }

  toFailure(): AffiliateApiFailure {
    return { status: this.status, code: this.code, message: this.message };
  }
}

/**
 * Every message a merchant can be shown by this API.
 *
 * Short, in Mozambican Portuguese, and none of them names another business, a
 * phone number or an internal id. Kept as one table so that changing what a
 * merchant reads is one edit, and so a new route cannot invent a ninth way of
 * saying "não encontrado".
 */
export const AFFILIATE_API_MESSAGE = {
  invalid_body: 'Pedido inválido.',
  invalid_name: 'Indique o nome do afiliado (2 a 60 letras).',
  invalid_phone: 'Use um número de Moçambique válido (8X XXX XXXX).',
  invalid_benefit_type: 'Escolha um benefício: desconto fixo, percentagem ou pontos.',
  invalid_benefit_value: 'Valor do benefício inválido.',
  invalid_percentage: `A percentagem deve estar entre ${PERCENTAGE_RANGE.min}% e ${PERCENTAGE_RANGE.max}%.`,
  invalid_usage_limit: 'O limite de utilizações deve ser um número inteiro positivo.',
  invalid_dates: 'As datas de validade do código são inválidas.',
  invalid_status: 'Estado inválido.',
  invalid_code: 'Indique o código de indicação.',
  invalid_first_visit_only: 'Indique se o código é só para clientes novos.',
  affiliate_not_found: 'Afiliado não encontrado.',
  affiliate_suspended: 'Este afiliado está suspenso e não pode ser adicionado.',
  affiliate_already_linked: 'Este afiliado já está ligado a este negócio.',
  code_not_found: 'Código não encontrado.',
  code_already_exists: 'Este afiliado já tem um código neste negócio.',
  referral_not_found: 'Indicação não encontrada.',
  reward_not_found: 'Recompensa não encontrada.',
  reward_not_pending: 'Só uma recompensa pendente pode ser aprovada.',
  reward_already_closed: 'Esta recompensa já foi fechada.',
  reward_paid: 'Uma recompensa já paga tem de ser revista manualmente.',
  merchant_not_found: 'Negócio não encontrado.',
  forbidden_role: 'Só o responsável do negócio pode fazer esta alteração.',
  rate_limited: 'Demasiadas tentativas. Tente daqui a pouco.',
  identity_unavailable: 'Não foi possível criar a identidade do afiliado.',
  invalid_sale_amount: 'Indique o valor da venda.',
  invalid_sale_reference: 'Referência da venda inválida.',
  invalid_sale_items: 'Os artigos da venda são inválidos.',
  invalid_customer: 'Indique o cliente da venda.',
  customer_not_found: 'Cliente não encontrado neste negócio.',
  referral_rejected: 'Não foi possível aplicar este código a esta venda.',
  sale_conflict: 'Esta venda já foi registada com dados diferentes.',
} as const;

export type AffiliateApiMessageKey = keyof typeof AFFILIATE_API_MESSAGE;

export function affiliateApiError(
  status: AffiliateApiFailure['status'],
  code: AffiliateApiMessageKey,
): AffiliateApiError {
  return new AffiliateApiError({
    status,
    code,
    message: AFFILIATE_API_MESSAGE[code],
  });
}

/** The 403 every mutation raises, so the wording cannot drift between routes. */
export function ownerOnlyError(): AffiliateApiError {
  return affiliateApiError(403, 'forbidden_role');
}

/* -------------------------------------------------------------- validation */

const NAME_PATTERN = /^[\p{L}][\p{L}\p{M}'\-. ]{1,59}$/u;

export type ParsedName = {
  firstName: string;
  lastName: string | null;
  displayName: string;
};

/**
 * A person's name, and the first word of it.
 *
 * The first word matters beyond display: it is what the code is built from, so
 * a name that folds to nothing would produce `AFI--XXXX`. Rejecting it here is
 * the only place that can still explain itself to whoever typed it.
 */
export function parseAffiliateName(raw: unknown): ParsedName {
  if (typeof raw !== 'string') throw affiliateApiError(400, 'invalid_name');
  const collapsed = raw.trim().replace(/\s+/g, ' ');
  if (!NAME_PATTERN.test(collapsed)) throw affiliateApiError(400, 'invalid_name');

  const parts = collapsed.split(' ');
  const firstName = parts[0];
  if (firstName.replace(/[^\p{L}]/gu, '') === '') {
    throw affiliateApiError(400, 'invalid_name');
  }

  return {
    firstName,
    lastName: parts.length > 1 ? parts.slice(1).join(' ') : null,
    displayName: collapsed,
  };
}

/**
 * A phone, normalised by the same function the rest of the product uses.
 *
 * The normaliser is passed in rather than imported: it lives in index.ts
 * beside the customer-core rules that define what a valid Mozambican number
 * is, and duplicating it here is how two definitions of "valid" start.
 */
export function parsePhone(
  raw: unknown,
  normalize: (value: unknown) => string | null,
): string {
  const normalized = normalize(raw);
  if (normalized === null) throw affiliateApiError(400, 'invalid_phone');
  return normalized;
}

export type ParsedBenefit = { type: BenefitType; value: number };

const MAX_FIXED_AMOUNT = 1_000_000;
const MAX_POINTS = 100_000;

function hasAtMostTwoDecimals(value: number): boolean {
  return Math.round(value * 100) === Number((value * 100).toFixed(6));
}

/**
 * What a code takes off a sale.
 *
 * Every branch has both a floor and a ceiling. An unbounded `FIXED_AMOUNT`
 * would let a typo write a code that pays out a million meticais, and an
 * unbounded `POINTS` would do the same to the loyalty ledger — neither is
 * caught later, because by then the value is simply what the code says.
 */
export function parseBenefit(rawType: unknown, rawValue: unknown): ParsedBenefit {
  if (typeof rawType !== 'string') throw affiliateApiError(400, 'invalid_benefit_type');
  const type = rawType.trim().toUpperCase() as BenefitType;
  if (!(BENEFIT_TYPE as readonly string[]).includes(type)) {
    throw affiliateApiError(400, 'invalid_benefit_type');
  }

  if (typeof rawValue !== 'number' || !Number.isFinite(rawValue) || rawValue <= 0) {
    throw affiliateApiError(400, 'invalid_benefit_value');
  }

  if (type === 'PERCENTAGE') {
    if (rawValue < PERCENTAGE_RANGE.min || rawValue > PERCENTAGE_RANGE.max) {
      throw affiliateApiError(400, 'invalid_percentage');
    }
    if (!hasAtMostTwoDecimals(rawValue)) {
      throw affiliateApiError(400, 'invalid_benefit_value');
    }
    return { type, value: rawValue };
  }

  if (type === 'FIXED_AMOUNT') {
    if (rawValue > MAX_FIXED_AMOUNT || !hasAtMostTwoDecimals(rawValue)) {
      throw affiliateApiError(400, 'invalid_benefit_value');
    }
    return { type, value: rawValue };
  }

  if (!Number.isInteger(rawValue) || rawValue > MAX_POINTS) {
    throw affiliateApiError(400, 'invalid_benefit_value');
  }
  return { type, value: rawValue };
}

const MAX_USAGE_LIMIT = 100_000;

/** `null` is unlimited and is the default; absent and explicit null are one. */
export function parseUsageLimit(raw: unknown): number | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'number' || !Number.isInteger(raw)) {
    throw affiliateApiError(400, 'invalid_usage_limit');
  }
  if (raw < 1 || raw > MAX_USAGE_LIMIT) {
    throw affiliateApiError(400, 'invalid_usage_limit');
  }
  return raw;
}

export function parseFirstVisitOnly(raw: unknown, fallback: boolean): boolean {
  if (raw === undefined || raw === null) return fallback;
  if (typeof raw !== 'boolean') {
    throw affiliateApiError(400, 'invalid_first_visit_only');
  }
  return raw;
}

export type ParsedValidity = { startsAt: number; expiresAt: number };

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_BACKDATE_MS = 365 * DAY_MS;
const MAX_VALIDITY_MS = 730 * DAY_MS;

/**
 * When a code is live.
 *
 * A window that has already closed is refused rather than stored: a code
 * created expired cannot be used, cannot be shared and would sit in the list
 * looking like a bug in the validation rules rather than a typo in a form.
 */
export function parseValidity(
  rawStartsAt: unknown,
  rawExpiresAt: unknown,
  now: number,
  defaultValidityDays: number,
): ParsedValidity {
  const startsAt = parseEpoch(rawStartsAt, now);
  const expiresAt = parseEpoch(
    rawExpiresAt,
    startsAt + defaultValidityDays * DAY_MS,
  );

  if (startsAt < now - MAX_BACKDATE_MS) throw affiliateApiError(400, 'invalid_dates');
  if (expiresAt <= startsAt) throw affiliateApiError(400, 'invalid_dates');
  if (expiresAt - startsAt > MAX_VALIDITY_MS) {
    throw affiliateApiError(400, 'invalid_dates');
  }
  if (expiresAt <= now) throw affiliateApiError(400, 'invalid_dates');

  return { startsAt, expiresAt };
}

/**
 * The same window, but on an edit, where a default would be a silent change.
 *
 * A PATCH that sent only a new expiry and let the start fall back to "now"
 * would move a code that has not begun yet to today without anyone asking, so
 * both ends are required together or neither is touched.
 */
export function parseValidityPair(
  rawStartsAt: unknown,
  rawExpiresAt: unknown,
  now: number,
): ParsedValidity {
  if (
    rawStartsAt === undefined ||
    rawStartsAt === null ||
    rawExpiresAt === undefined ||
    rawExpiresAt === null
  ) {
    throw affiliateApiError(400, 'invalid_dates');
  }
  return parseValidity(rawStartsAt, rawExpiresAt, now, 0);
}

function parseEpoch(raw: unknown, fallback: number): number {
  if (raw === undefined || raw === null) return fallback;
  if (typeof raw !== 'number' || !Number.isInteger(raw) || raw <= 0) {
    throw affiliateApiError(400, 'invalid_dates');
  }
  return raw;
}

export function parseCodeText(raw: unknown): string {
  if (typeof raw !== 'string') throw affiliateApiError(400, 'invalid_code');
  const trimmed = raw.trim();
  if (trimmed.length < 3 || trimmed.length > 40) {
    throw affiliateApiError(400, 'invalid_code');
  }
  return trimmed;
}

/** A positive sale amount, or nothing. A preview may run before one exists. */
export function parseOptionalSaleAmount(raw: unknown): number | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) {
    throw affiliateApiError(400, 'invalid_body');
  }
  return raw;
}

export function parseIdParam(raw: unknown, code: AffiliateApiMessageKey): string {
  if (typeof raw !== 'string') throw affiliateApiError(404, code);
  const trimmed = raw.trim();
  if (trimmed === '' || trimmed.length > 200) throw affiliateApiError(404, code);
  return trimmed;
}

/* ------------------------------------------------------- committing a sale */

/**
 * What a till may say about a referred sale, and nothing more.
 *
 * The list of fields this reads is the whole security argument for the commit
 * endpoint. It takes the sale's local identity, who it was for, what it was
 * worth before any discount, and the code that was typed. It does not take the
 * benefit, the discount, the points, the reward, the affiliate or the business
 * — every one of those is decided on the server, from the code and the
 * business's own settings, because a request that could state them could award
 * itself money.
 *
 * `gross_amount` is read rather than a net: the server applies the discount,
 * so a till that sent an already-discounted amount would have the discount
 * taken twice, and one that sent the wrong net would decide its own price.
 */
export type ParsedReferralSaleItem = {
  id: string;
  merchantItemId: string;
  nameSnapshot: string;
  typeSnapshot: string;
  quantity: number;
  unitPrice: number | null;
  subtotal: number | null;
};

export type ParsedReferralSaleCommit = {
  deviceId: string;
  localSaleId: string;
  customerId: string;
  customerPhoneE164: string;
  grossAmount: number;
  rawCode: string;
  items: ParsedReferralSaleItem[];
};

const MAX_SALE_AMOUNT = 10_000_000;
const MAX_SALE_ITEMS = 100;

function parseReference(raw: unknown): string {
  if (typeof raw !== 'string') throw affiliateApiError(400, 'invalid_sale_reference');
  const trimmed = raw.trim();
  if (trimmed === '' || trimmed.length > 120) {
    throw affiliateApiError(400, 'invalid_sale_reference');
  }
  return trimmed;
}

function parseGrossAmount(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) {
    throw affiliateApiError(400, 'invalid_sale_amount');
  }
  if (raw > MAX_SALE_AMOUNT) throw affiliateApiError(400, 'invalid_sale_amount');
  // Money has two decimal places. Anything finer is a rounding argument with
  // the client that the server would lose silently.
  if (Math.round(raw * 100) !== Number((raw * 100).toFixed(6))) {
    throw affiliateApiError(400, 'invalid_sale_amount');
  }
  return raw;
}

function parseSaleItems(raw: unknown): ParsedReferralSaleItem[] {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw) || raw.length > MAX_SALE_ITEMS) {
    throw affiliateApiError(400, 'invalid_sale_items');
  }

  return raw.map((entry) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      throw affiliateApiError(400, 'invalid_sale_items');
    }
    const item = entry as Record<string, unknown>;
    const text = (value: unknown, max: number): string => {
      if (typeof value !== 'string') throw affiliateApiError(400, 'invalid_sale_items');
      const trimmed = value.trim();
      if (trimmed === '' || trimmed.length > max) {
        throw affiliateApiError(400, 'invalid_sale_items');
      }
      return trimmed;
    };
    const money = (value: unknown): number | null => {
      if (value === undefined || value === null) return null;
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
        throw affiliateApiError(400, 'invalid_sale_items');
      }
      return value;
    };
    const quantity = item.quantity;
    if (
      typeof quantity !== 'number' ||
      !Number.isInteger(quantity) ||
      quantity < 1 ||
      quantity > 999
    ) {
      throw affiliateApiError(400, 'invalid_sale_items');
    }

    // The item's own id becomes a document id. A slash in it would write to a
    // path the caller chose rather than the one this endpoint owns.
    const id = text(item.id, 120);
    if (!/^[A-Za-z0-9_-]+$/.test(id)) {
      throw affiliateApiError(400, 'invalid_sale_items');
    }

    return {
      id,
      merchantItemId: text(item.merchant_item_id, 120),
      nameSnapshot: text(item.name_snapshot, 200),
      typeSnapshot: text(item.type_snapshot, 40),
      quantity,
      unitPrice: money(item.unit_price),
      subtotal: money(item.subtotal),
    };
  });
}

export function parseReferralSaleCommit(
  payload: Record<string, unknown>,
  normalize: (value: unknown) => string | null,
): ParsedReferralSaleCommit {
  const customerId = payload.customer_id;
  if (typeof customerId !== 'string' || customerId.trim() === '' || customerId.length > 200) {
    throw affiliateApiError(400, 'invalid_customer');
  }

  return {
    deviceId: parseReference(payload.device_id),
    localSaleId: parseReference(payload.local_sale_id),
    customerId: customerId.trim(),
    customerPhoneE164: parsePhone(payload.customer_phone, normalize),
    grossAmount: parseGrossAmount(payload.gross_amount),
    rawCode: parseCodeText(payload.code),
    items: parseSaleItems(payload.items),
  };
}

/* ------------------------------------------------------- offline reconcile */

export type ParsedOfflineBenefit = {
  type: BenefitType;
  value: number;
  discountAmount: number;
  pointsAwarded: number;
};

export type ParsedOfflineReferralSale = ParsedReferralSaleCommit & {
  offlineBenefitApplied: boolean;
  appliedBenefit: ParsedOfflineBenefit | null;
  localCreatedAt: number;
};

function parseAppliedBenefit(raw: unknown): ParsedOfflineBenefit {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw affiliateApiError(400, 'invalid_benefit_value');
  }
  const benefit = raw as Record<string, unknown>;
  const type = typeof benefit.type === 'string' ? benefit.type.trim().toUpperCase() : '';
  if (!(BENEFIT_TYPE as readonly string[]).includes(type)) {
    throw affiliateApiError(400, 'invalid_benefit_type');
  }
  const money = (value: unknown): number => {
    if (value === undefined || value === null) return 0;
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
      throw affiliateApiError(400, 'invalid_benefit_value');
    }
    return value;
  };
  const points = money(benefit.points_awarded);
  if (!Number.isInteger(points)) throw affiliateApiError(400, 'invalid_benefit_value');
  return {
    type: type as BenefitType,
    value: money(benefit.value),
    discountAmount: money(benefit.discount_amount),
    pointsAwarded: points,
  };
}

/**
 * A queued offline sale, read strictly.
 *
 * Everything the online commit reads, plus the one fact only the till knows:
 * whether it already took money off the bill. That flag decides whether the
 * server is reconciling a discount it has to honour or judging a code that has
 * so far cost nobody anything, so it is read as a boolean and never inferred
 * from the presence of a benefit object.
 *
 * `local_created_at` is the device's clock and is treated as information, not
 * as truth: it is stored on the sale and measured against the server's own
 * clock, and a wild value is recorded rather than used to refuse a real sale.
 */
export function parseOfflineReferralSale(
  payload: Record<string, unknown>,
  normalize: (value: unknown) => string | null,
  now: number,
): ParsedOfflineReferralSale {
  const base = parseReferralSaleCommit(payload, normalize);
  const offlineBenefitApplied = payload.offline_benefit_applied === true;
  const appliedBenefit = offlineBenefitApplied
    ? parseAppliedBenefit(payload.applied_benefit)
    : null;
  if (appliedBenefit !== null && appliedBenefit.discountAmount > base.grossAmount) {
    throw affiliateApiError(400, 'invalid_benefit_value');
  }
  const rawCreatedAt = payload.created_at ?? payload.local_created_at;
  const localCreatedAt =
    typeof rawCreatedAt === 'number' && Number.isFinite(rawCreatedAt) && rawCreatedAt > 0
      ? Math.floor(rawCreatedAt)
      : now;

  return {
    ...base,
    offlineBenefitApplied,
    appliedBenefit,
    localCreatedAt,
  };
}

/**
 * An affiliate an owner added with no connection.
 *
 * The same fields the online create takes, plus the queue's own identifiers so
 * the answer can be matched back to the row the device is holding. The local id
 * is carried, never trusted: the affiliate's real identity is still derived
 * from the phone, server-side, exactly as it is online.
 */
export type ParsedOfflineAffiliateCreate = {
  localId: string;
  localAffiliateId: string;
  deviceId: string;
  idempotencyKey: string;
  createdAt: number;
};

export function parseOfflineAffiliateCreate(
  payload: Record<string, unknown>,
  now: number,
): ParsedOfflineAffiliateCreate {
  const text = (value: unknown, max: number): string => {
    if (typeof value !== 'string') throw affiliateApiError(400, 'invalid_sale_reference');
    const trimmed = value.trim();
    if (trimmed === '' || trimmed.length > max) {
      throw affiliateApiError(400, 'invalid_sale_reference');
    }
    return trimmed;
  };
  const rawCreatedAt = payload.created_at;
  return {
    localId: text(payload.local_id, 120),
    localAffiliateId: text(payload.local_affiliate_id, 200),
    deviceId: text(payload.device_id, 120),
    idempotencyKey: text(payload.idempotency_key, 200),
    createdAt:
      typeof rawCreatedAt === 'number' && Number.isFinite(rawCreatedAt) && rawCreatedAt > 0
        ? Math.floor(rawCreatedAt)
        : now,
  };
}

export function parseBodyObject(raw: unknown): Record<string, unknown> {  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw affiliateApiError(400, 'invalid_body');
  }
  return raw as Record<string, unknown>;
}

export function parseAffiliateStatus(raw: unknown): AffiliateStatus {
  if (typeof raw !== 'string') throw affiliateApiError(400, 'invalid_status');
  const value = raw.trim().toUpperCase() as AffiliateStatus;
  if (!(AFFILIATE_STATUS as readonly string[]).includes(value)) {
    throw affiliateApiError(400, 'invalid_status');
  }
  return value;
}

/* ------------------------------------------------------- reward transitions */

/**
 * Which reward status may follow which.
 *
 * `PAID` leads nowhere on purpose. Points already handed to an affiliate are
 * not taken back by a status change, so a cancel on a paid reward is refused
 * and left for a person — `rewardsAffectedByCancellation` in the engine makes
 * the same distinction for the sale-cancellation path.
 */
export const REWARD_TRANSITIONS: Record<RewardStatus, readonly RewardStatus[]> = {
  PENDING: ['APPROVED', 'CANCELLED'],
  APPROVED: ['PAID', 'CANCELLED'],
  PAID: [],
  CANCELLED: [],
};

export function canTransitionReward(from: RewardStatus, to: RewardStatus): boolean {
  return REWARD_TRANSITIONS[from]?.includes(to) ?? false;
}

export function parseRewardStatus(raw: unknown): RewardStatus {
  const value = String(raw ?? '').trim().toUpperCase() as RewardStatus;
  if (!(REWARD_STATUS as readonly string[]).includes(value)) {
    throw affiliateApiError(400, 'invalid_status');
  }
  return value;
}

/**
 * Why a decision was refused, in the words the approver needs.
 *
 * A single "estado inválido" would leave someone staring at a reward that is
 * already approved wondering what they did wrong, so the three reasons that
 * actually happen are told apart.
 */
export function rewardTransitionError(
  from: RewardStatus,
  to: RewardStatus,
): AffiliateApiError {
  if (from === 'PAID') return affiliateApiError(409, 'reward_paid');
  if (from === 'CANCELLED') return affiliateApiError(409, 'reward_already_closed');
  if (to === 'APPROVED') return affiliateApiError(409, 'reward_not_pending');
  return affiliateApiError(409, 'reward_already_closed');
}

/* --------------------------------------------------------------------- DTOs */

export type AffiliateDto = {
  id: string;
  name: string;
  first_name: string;
  last_name: string | null;
  /** E.164. The merchant typed it and needs it to share the code on WhatsApp. */
  phone: string | null;
  phone_last4: string | null;
  status: AffiliateStatus;
  created_at: number | null;
  updated_at: number | null;
};

export type AffiliateCodeDto = {
  id: string;
  merchant_id: string;
  affiliate_id: string;
  code: string;
  normalized_code: string;
  benefit_type: BenefitType;
  benefit_value: number;
  starts_at: number | null;
  expires_at: number | null;
  usage_limit: number | null;
  usage_count: number;
  first_visit_only: boolean;
  status: AffiliateCodeStatus;
  created_at: number | null;
  updated_at: number | null;
};

export type MerchantAffiliateDto = AffiliateDto & {
  merchant_id: string;
  link_status: AffiliateLinkStatus;
  linked_at: number | null;
  code: AffiliateCodeDto | null;
};

export type ReferralAttributionDto = {
  id: string;
  merchant_id: string;
  affiliate_id: string;
  affiliate_code_id: string | null;
  customer_id: string | null;
  first_sale_id: string | null;
  status: string;
  rejection_reason: string | null;
  attributed_at: number | null;
  created_at: number | null;
  updated_at: number | null;
};

export type AffiliateRewardDto = {
  id: string;
  merchant_id: string;
  affiliate_id: string;
  attribution_id: string | null;
  type: string;
  value: number;
  value_type: string;
  status: RewardStatus;
  trigger_sale_id: string | null;
  approved_by: string | null;
  approved_at: number | null;
  paid_at: number | null;
  cancelled_at: number | null;
  created_at: number | null;
  updated_at: number | null;
};

export type AffiliateMetricsDto = {
  merchant_id: string;
  affiliate_id: string | null;
  unique_validation_attempts: number;
  confirmed_attributions: number;
  rejected_attributions: number;
  returned_customers: number;
  pending_reward_count: number;
  pending_reward_points: number;
  approved_reward_count: number;
  approved_reward_points: number;
  conversion_rate: number;
  last_activity_at: number | null;
  truncated: boolean;
};

/** The console's view. It carries no reachable phone number, only a mask. */
export type AdminAffiliateDto = {
  id: string;
  name: string;
  phone_masked: string;
  phone_last4: string | null;
  status: AffiliateStatus;
  merchant_count: number;
  merchant_ids: string[];
  created_at: number | null;
  updated_at: number | null;
};

export type ReferralBenefitDto = {
  type: BenefitType;
  value: number;
  display_text: string;
};

export type ReferralValidationDto =
  | {
      valid: true;
      affiliate_id: string;
      affiliate_name: string;
      affiliate_code_id: string;
      normalized_code: string;
      first_visit_only: boolean;
      /** Advisory. The sale commit recalculates it against the real sale. */
      benefit: ReferralBenefitDto;
      validated_at: number;
    }
  | {
      valid: false;
      reason: ReferralReason;
      message: string;
      validated_at: number;
    };

export function referralRejection(
  reason: ReferralReason,
  now: number,
): ReferralValidationDto {
  return {
    valid: false,
    reason,
    message: REFERRAL_REASON_MESSAGE[reason],
    validated_at: now,
  };
}

export type ReferralValidationSource = {
  validation: { ok: true } | { ok: false; reason: ReferralReason };
  affiliateId: string | null;
  affiliateName: string | null;
  codeId: string | null;
  normalizedCode: string;
  firstVisitOnly: boolean;
  benefit: { type: BenefitType; value: number; displayText: string } | null;
};

/**
 * Turns what the store found into what the till is told.
 *
 * Pure, so the mapping is testable without an emulator, and so the one case
 * that would otherwise be a silent hole has somewhere to be handled: a
 * validation that passed but produced no benefit. That cannot happen — the
 * benefit is read off the same code that was just validated — but answering
 * "valid" with an empty benefit would put a discount of zero on a receipt, so
 * it degrades to `BENEFIT_INVALID` instead.
 */
export function referralValidationResponse(
  source: ReferralValidationSource,
  now: number,
): ReferralValidationDto {
  if (!source.validation.ok) return referralRejection(source.validation.reason, now);
  if (source.benefit === null) return referralRejection('BENEFIT_INVALID', now);

  return {
    valid: true,
    affiliate_id: source.affiliateId ?? '',
    affiliate_name: source.affiliateName ?? '',
    affiliate_code_id: source.codeId ?? '',
    normalized_code: source.normalizedCode,
    first_visit_only: source.firstVisitOnly,
    benefit: {
      type: source.benefit.type,
      value: source.benefit.value,
      display_text: source.benefit.displayText,
    },
    validated_at: now,
  };
}

export type RateLimitedHttpResponse = {
  status: 429;
  headers: { 'Retry-After': string };
  body: { success: false; code: 'rate_limited'; message: string };
};

/**
 * What a caller over the limit is told.
 *
 * The body is identical whatever the code was, and carries no reason beyond
 * "too many": a 429 that differed for a real code would be a slower way of
 * asking the same question the limit exists to stop. `Retry-After` is in whole
 * seconds because that is what the header means.
 */
export function rateLimitedResponse(retryAfterMs: number): RateLimitedHttpResponse {
  return {
    status: 429,
    headers: {
      'Retry-After': String(Math.max(1, Math.ceil(retryAfterMs / 1000))),
    },
    body: {
      success: false,
      code: 'rate_limited',
      message: AFFILIATE_API_MESSAGE.rate_limited,
    },
  };
}

/* ------------------------------------------------------------------ mappers */

type Row = Record<string, unknown>;

export function toAffiliateDto(id: string, data: Row): AffiliateDto {
  const phone = asString(data, 'phone_e164', 'phone');
  return {
    id: asString(data, 'id') ?? id,
    name: asString(data, 'display_name', 'name') ?? '',
    first_name: asString(data, 'first_name') ?? '',
    last_name: asString(data, 'last_name'),
    phone,
    phone_last4: asString(data, 'phone_last4') ?? (phone ? phone.slice(-4) : null),
    status: readAffiliateStatus(data),
    created_at: asEpoch(data, 'created_at'),
    updated_at: asEpoch(data, 'updated_at'),
  };
}

export function toAdminAffiliateDto(id: string, data: Row): AdminAffiliateDto {
  const base = toAffiliateDto(id, data);
  const merchantIds = Array.isArray(data.merchant_ids)
    ? (data.merchant_ids as unknown[]).filter(
        (value): value is string => typeof value === 'string' && value !== '',
      )
    : [];
  return {
    id: base.id,
    name: base.name,
    phone_masked: maskPhone(base.phone ?? ''),
    phone_last4: base.phone_last4,
    status: base.status,
    merchant_count: merchantIds.length,
    merchant_ids: merchantIds,
    created_at: base.created_at,
    updated_at: base.updated_at,
  };
}

export function toAffiliateCodeDto(id: string, data: Row): AffiliateCodeDto {
  const benefitType = String(asString(data, 'benefit_type') ?? '')
    .trim()
    .toUpperCase();
  return {
    id: asString(data, 'id') ?? id,
    merchant_id: asString(data, 'merchant_id') ?? '',
    affiliate_id: asString(data, 'affiliate_id') ?? '',
    code: asString(data, 'code') ?? '',
    normalized_code: asString(data, 'normalized_code') ?? '',
    benefit_type: (BENEFIT_TYPE as readonly string[]).includes(benefitType)
      ? (benefitType as BenefitType)
      : 'FIXED_AMOUNT',
    benefit_value: asNumber(data, 'benefit_value') ?? 0,
    starts_at: asEpoch(data, 'starts_at'),
    expires_at: asEpoch(data, 'expires_at'),
    usage_limit: asNumber(data, 'usage_limit'),
    usage_count: asNumber(data, 'usage_count') ?? 0,
    first_visit_only: asBool(data, 'first_visit_only') ?? true,
    status: readCodeStatus(data),
    created_at: asEpoch(data, 'created_at'),
    updated_at: asEpoch(data, 'updated_at'),
  };
}

export function toReferralAttributionDto(
  id: string,
  data: Row,
): ReferralAttributionDto {
  return {
    id: asString(data, 'id') ?? id,
    merchant_id: asString(data, 'merchant_id') ?? '',
    affiliate_id: asString(data, 'affiliate_id') ?? '',
    affiliate_code_id: asString(data, 'affiliate_code_id'),
    customer_id: asString(data, 'customer_id'),
    first_sale_id: asString(data, 'first_sale_id'),
    status: (asString(data, 'status') ?? '').toUpperCase(),
    rejection_reason: asString(data, 'rejection_reason'),
    attributed_at: asEpoch(data, 'attributed_at'),
    created_at: asEpoch(data, 'created_at'),
    updated_at: asEpoch(data, 'updated_at'),
  };
}

export function toAffiliateRewardDto(id: string, data: Row): AffiliateRewardDto {
  return {
    id: asString(data, 'id') ?? id,
    merchant_id: asString(data, 'merchant_id') ?? '',
    affiliate_id: asString(data, 'affiliate_id') ?? '',
    attribution_id: asString(data, 'attribution_id'),
    type: (asString(data, 'type') ?? '').toUpperCase(),
    value: asNumber(data, 'value') ?? 0,
    value_type: (asString(data, 'value_type') ?? 'POINTS').toUpperCase(),
    status: readRewardStatus(data),
    trigger_sale_id: asString(data, 'trigger_sale_id'),
    approved_by: asString(data, 'approved_by'),
    approved_at: asEpoch(data, 'approved_at'),
    paid_at: asEpoch(data, 'paid_at'),
    cancelled_at: asEpoch(data, 'cancelled_at'),
    created_at: asEpoch(data, 'created_at'),
    updated_at: asEpoch(data, 'updated_at'),
  };
}

function readAffiliateStatus(data: Row): AffiliateStatus {
  const value = (asString(data, 'status') ?? '').trim().toUpperCase();
  return (AFFILIATE_STATUS as readonly string[]).includes(value)
    ? (value as AffiliateStatus)
    : 'INACTIVE';
}

function readCodeStatus(data: Row): AffiliateCodeStatus {
  const value = (asString(data, 'status') ?? '').trim().toUpperCase();
  return (AFFILIATE_CODE_STATUS as readonly string[]).includes(value)
    ? (value as AffiliateCodeStatus)
    : 'DISABLED';
}

/**
 * An unreadable status reads as `CANCELLED`, not as `PENDING`.
 *
 * A corrupt row that defaulted to pending would appear in the approvals queue
 * and could be approved into points nobody earned. Defaulting to a terminal
 * state fails closed.
 */
function readRewardStatus(data: Row): RewardStatus {
  const value = (asString(data, 'status') ?? '').trim().toUpperCase();
  return (REWARD_STATUS as readonly string[]).includes(value)
    ? (value as RewardStatus)
    : 'CANCELLED';
}
