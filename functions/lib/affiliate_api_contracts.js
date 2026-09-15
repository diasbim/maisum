"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.REWARD_TRANSITIONS = exports.AFFILIATE_API_MESSAGE = exports.AffiliateApiError = void 0;
exports.affiliateApiError = affiliateApiError;
exports.ownerOnlyError = ownerOnlyError;
exports.parseAffiliateName = parseAffiliateName;
exports.parsePhone = parsePhone;
exports.parseBenefit = parseBenefit;
exports.parseUsageLimit = parseUsageLimit;
exports.parseFirstVisitOnly = parseFirstVisitOnly;
exports.parseValidity = parseValidity;
exports.parseValidityPair = parseValidityPair;
exports.parseCodeText = parseCodeText;
exports.parseOptionalSaleAmount = parseOptionalSaleAmount;
exports.parseIdParam = parseIdParam;
exports.parseBodyObject = parseBodyObject;
exports.parseAffiliateStatus = parseAffiliateStatus;
exports.canTransitionReward = canTransitionReward;
exports.parseRewardStatus = parseRewardStatus;
exports.rewardTransitionError = rewardTransitionError;
exports.referralRejection = referralRejection;
exports.referralValidationResponse = referralValidationResponse;
exports.rateLimitedResponse = rateLimitedResponse;
exports.toAffiliateDto = toAffiliateDto;
exports.toAdminAffiliateDto = toAdminAffiliateDto;
exports.toAffiliateCodeDto = toAffiliateCodeDto;
exports.toReferralAttributionDto = toReferralAttributionDto;
exports.toAffiliateRewardDto = toAffiliateRewardDto;
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
const merchant_records_js_1 = require("./merchant_records.js");
class AffiliateApiError extends Error {
    constructor(failure) {
        super(failure.message);
        this.name = 'AffiliateApiError';
        this.status = failure.status;
        this.code = failure.code;
    }
    toFailure() {
        return { status: this.status, code: this.code, message: this.message };
    }
}
exports.AffiliateApiError = AffiliateApiError;
/**
 * Every message a merchant can be shown by this API.
 *
 * Short, in Mozambican Portuguese, and none of them names another business, a
 * phone number or an internal id. Kept as one table so that changing what a
 * merchant reads is one edit, and so a new route cannot invent a ninth way of
 * saying "não encontrado".
 */
exports.AFFILIATE_API_MESSAGE = {
    invalid_body: 'Pedido inválido.',
    invalid_name: 'Indique o nome do afiliado (2 a 60 letras).',
    invalid_phone: 'Use um número de Moçambique válido (8X XXX XXXX).',
    invalid_benefit_type: 'Escolha um benefício: desconto fixo, percentagem ou pontos.',
    invalid_benefit_value: 'Valor do benefício inválido.',
    invalid_percentage: `A percentagem deve estar entre ${affiliate_contracts_js_1.PERCENTAGE_RANGE.min}% e ${affiliate_contracts_js_1.PERCENTAGE_RANGE.max}%.`,
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
};
function affiliateApiError(status, code) {
    return new AffiliateApiError({
        status,
        code,
        message: exports.AFFILIATE_API_MESSAGE[code],
    });
}
/** The 403 every mutation raises, so the wording cannot drift between routes. */
function ownerOnlyError() {
    return affiliateApiError(403, 'forbidden_role');
}
/* -------------------------------------------------------------- validation */
const NAME_PATTERN = /^[\p{L}][\p{L}\p{M}'\-. ]{1,59}$/u;
/**
 * A person's name, and the first word of it.
 *
 * The first word matters beyond display: it is what the code is built from, so
 * a name that folds to nothing would produce `AFI--XXXX`. Rejecting it here is
 * the only place that can still explain itself to whoever typed it.
 */
function parseAffiliateName(raw) {
    if (typeof raw !== 'string')
        throw affiliateApiError(400, 'invalid_name');
    const collapsed = raw.trim().replace(/\s+/g, ' ');
    if (!NAME_PATTERN.test(collapsed))
        throw affiliateApiError(400, 'invalid_name');
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
function parsePhone(raw, normalize) {
    const normalized = normalize(raw);
    if (normalized === null)
        throw affiliateApiError(400, 'invalid_phone');
    return normalized;
}
const MAX_FIXED_AMOUNT = 1000000;
const MAX_POINTS = 100000;
function hasAtMostTwoDecimals(value) {
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
function parseBenefit(rawType, rawValue) {
    if (typeof rawType !== 'string')
        throw affiliateApiError(400, 'invalid_benefit_type');
    const type = rawType.trim().toUpperCase();
    if (!affiliate_contracts_js_1.BENEFIT_TYPE.includes(type)) {
        throw affiliateApiError(400, 'invalid_benefit_type');
    }
    if (typeof rawValue !== 'number' || !Number.isFinite(rawValue) || rawValue <= 0) {
        throw affiliateApiError(400, 'invalid_benefit_value');
    }
    if (type === 'PERCENTAGE') {
        if (rawValue < affiliate_contracts_js_1.PERCENTAGE_RANGE.min || rawValue > affiliate_contracts_js_1.PERCENTAGE_RANGE.max) {
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
const MAX_USAGE_LIMIT = 100000;
/** `null` is unlimited and is the default; absent and explicit null are one. */
function parseUsageLimit(raw) {
    if (raw === undefined || raw === null)
        return null;
    if (typeof raw !== 'number' || !Number.isInteger(raw)) {
        throw affiliateApiError(400, 'invalid_usage_limit');
    }
    if (raw < 1 || raw > MAX_USAGE_LIMIT) {
        throw affiliateApiError(400, 'invalid_usage_limit');
    }
    return raw;
}
function parseFirstVisitOnly(raw, fallback) {
    if (raw === undefined || raw === null)
        return fallback;
    if (typeof raw !== 'boolean') {
        throw affiliateApiError(400, 'invalid_first_visit_only');
    }
    return raw;
}
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
function parseValidity(rawStartsAt, rawExpiresAt, now, defaultValidityDays) {
    const startsAt = parseEpoch(rawStartsAt, now);
    const expiresAt = parseEpoch(rawExpiresAt, startsAt + defaultValidityDays * DAY_MS);
    if (startsAt < now - MAX_BACKDATE_MS)
        throw affiliateApiError(400, 'invalid_dates');
    if (expiresAt <= startsAt)
        throw affiliateApiError(400, 'invalid_dates');
    if (expiresAt - startsAt > MAX_VALIDITY_MS) {
        throw affiliateApiError(400, 'invalid_dates');
    }
    if (expiresAt <= now)
        throw affiliateApiError(400, 'invalid_dates');
    return { startsAt, expiresAt };
}
/**
 * The same window, but on an edit, where a default would be a silent change.
 *
 * A PATCH that sent only a new expiry and let the start fall back to "now"
 * would move a code that has not begun yet to today without anyone asking, so
 * both ends are required together or neither is touched.
 */
function parseValidityPair(rawStartsAt, rawExpiresAt, now) {
    if (rawStartsAt === undefined ||
        rawStartsAt === null ||
        rawExpiresAt === undefined ||
        rawExpiresAt === null) {
        throw affiliateApiError(400, 'invalid_dates');
    }
    return parseValidity(rawStartsAt, rawExpiresAt, now, 0);
}
function parseEpoch(raw, fallback) {
    if (raw === undefined || raw === null)
        return fallback;
    if (typeof raw !== 'number' || !Number.isInteger(raw) || raw <= 0) {
        throw affiliateApiError(400, 'invalid_dates');
    }
    return raw;
}
function parseCodeText(raw) {
    if (typeof raw !== 'string')
        throw affiliateApiError(400, 'invalid_code');
    const trimmed = raw.trim();
    if (trimmed.length < 3 || trimmed.length > 40) {
        throw affiliateApiError(400, 'invalid_code');
    }
    return trimmed;
}
/** A positive sale amount, or nothing. A preview may run before one exists. */
function parseOptionalSaleAmount(raw) {
    if (raw === undefined || raw === null)
        return null;
    if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) {
        throw affiliateApiError(400, 'invalid_body');
    }
    return raw;
}
function parseIdParam(raw, code) {
    if (typeof raw !== 'string')
        throw affiliateApiError(404, code);
    const trimmed = raw.trim();
    if (trimmed === '' || trimmed.length > 200)
        throw affiliateApiError(404, code);
    return trimmed;
}
function parseBodyObject(raw) {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        throw affiliateApiError(400, 'invalid_body');
    }
    return raw;
}
function parseAffiliateStatus(raw) {
    if (typeof raw !== 'string')
        throw affiliateApiError(400, 'invalid_status');
    const value = raw.trim().toUpperCase();
    if (!affiliate_contracts_js_1.AFFILIATE_STATUS.includes(value)) {
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
exports.REWARD_TRANSITIONS = {
    PENDING: ['APPROVED', 'CANCELLED'],
    APPROVED: ['PAID', 'CANCELLED'],
    PAID: [],
    CANCELLED: [],
};
function canTransitionReward(from, to) {
    return exports.REWARD_TRANSITIONS[from]?.includes(to) ?? false;
}
function parseRewardStatus(raw) {
    const value = String(raw ?? '').trim().toUpperCase();
    if (!affiliate_contracts_js_1.REWARD_STATUS.includes(value)) {
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
function rewardTransitionError(from, to) {
    if (from === 'PAID')
        return affiliateApiError(409, 'reward_paid');
    if (from === 'CANCELLED')
        return affiliateApiError(409, 'reward_already_closed');
    if (to === 'APPROVED')
        return affiliateApiError(409, 'reward_not_pending');
    return affiliateApiError(409, 'reward_already_closed');
}
function referralRejection(reason, now) {
    return {
        valid: false,
        reason,
        message: affiliate_contracts_js_1.REFERRAL_REASON_MESSAGE[reason],
        validated_at: now,
    };
}
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
function referralValidationResponse(source, now) {
    if (!source.validation.ok)
        return referralRejection(source.validation.reason, now);
    if (source.benefit === null)
        return referralRejection('BENEFIT_INVALID', now);
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
/**
 * What a caller over the limit is told.
 *
 * The body is identical whatever the code was, and carries no reason beyond
 * "too many": a 429 that differed for a real code would be a slower way of
 * asking the same question the limit exists to stop. `Retry-After` is in whole
 * seconds because that is what the header means.
 */
function rateLimitedResponse(retryAfterMs) {
    return {
        status: 429,
        headers: {
            'Retry-After': String(Math.max(1, Math.ceil(retryAfterMs / 1000))),
        },
        body: {
            success: false,
            code: 'rate_limited',
            message: exports.AFFILIATE_API_MESSAGE.rate_limited,
        },
    };
}
function toAffiliateDto(id, data) {
    const phone = (0, merchant_records_js_1.asString)(data, 'phone_e164', 'phone');
    return {
        id: (0, merchant_records_js_1.asString)(data, 'id') ?? id,
        name: (0, merchant_records_js_1.asString)(data, 'display_name', 'name') ?? '',
        first_name: (0, merchant_records_js_1.asString)(data, 'first_name') ?? '',
        last_name: (0, merchant_records_js_1.asString)(data, 'last_name'),
        phone,
        phone_last4: (0, merchant_records_js_1.asString)(data, 'phone_last4') ?? (phone ? phone.slice(-4) : null),
        status: readAffiliateStatus(data),
        created_at: (0, merchant_records_js_1.asEpoch)(data, 'created_at'),
        updated_at: (0, merchant_records_js_1.asEpoch)(data, 'updated_at'),
    };
}
function toAdminAffiliateDto(id, data) {
    const base = toAffiliateDto(id, data);
    const merchantIds = Array.isArray(data.merchant_ids)
        ? data.merchant_ids.filter((value) => typeof value === 'string' && value !== '')
        : [];
    return {
        id: base.id,
        name: base.name,
        phone_masked: (0, affiliate_notifications_js_1.maskPhone)(base.phone ?? ''),
        phone_last4: base.phone_last4,
        status: base.status,
        merchant_count: merchantIds.length,
        merchant_ids: merchantIds,
        created_at: base.created_at,
        updated_at: base.updated_at,
    };
}
function toAffiliateCodeDto(id, data) {
    const benefitType = String((0, merchant_records_js_1.asString)(data, 'benefit_type') ?? '')
        .trim()
        .toUpperCase();
    return {
        id: (0, merchant_records_js_1.asString)(data, 'id') ?? id,
        merchant_id: (0, merchant_records_js_1.asString)(data, 'merchant_id') ?? '',
        affiliate_id: (0, merchant_records_js_1.asString)(data, 'affiliate_id') ?? '',
        code: (0, merchant_records_js_1.asString)(data, 'code') ?? '',
        normalized_code: (0, merchant_records_js_1.asString)(data, 'normalized_code') ?? '',
        benefit_type: affiliate_contracts_js_1.BENEFIT_TYPE.includes(benefitType)
            ? benefitType
            : 'FIXED_AMOUNT',
        benefit_value: (0, merchant_records_js_1.asNumber)(data, 'benefit_value') ?? 0,
        starts_at: (0, merchant_records_js_1.asEpoch)(data, 'starts_at'),
        expires_at: (0, merchant_records_js_1.asEpoch)(data, 'expires_at'),
        usage_limit: (0, merchant_records_js_1.asNumber)(data, 'usage_limit'),
        usage_count: (0, merchant_records_js_1.asNumber)(data, 'usage_count') ?? 0,
        first_visit_only: (0, merchant_records_js_1.asBool)(data, 'first_visit_only') ?? true,
        status: readCodeStatus(data),
        created_at: (0, merchant_records_js_1.asEpoch)(data, 'created_at'),
        updated_at: (0, merchant_records_js_1.asEpoch)(data, 'updated_at'),
    };
}
function toReferralAttributionDto(id, data) {
    return {
        id: (0, merchant_records_js_1.asString)(data, 'id') ?? id,
        merchant_id: (0, merchant_records_js_1.asString)(data, 'merchant_id') ?? '',
        affiliate_id: (0, merchant_records_js_1.asString)(data, 'affiliate_id') ?? '',
        affiliate_code_id: (0, merchant_records_js_1.asString)(data, 'affiliate_code_id'),
        customer_id: (0, merchant_records_js_1.asString)(data, 'customer_id'),
        first_sale_id: (0, merchant_records_js_1.asString)(data, 'first_sale_id'),
        status: ((0, merchant_records_js_1.asString)(data, 'status') ?? '').toUpperCase(),
        rejection_reason: (0, merchant_records_js_1.asString)(data, 'rejection_reason'),
        attributed_at: (0, merchant_records_js_1.asEpoch)(data, 'attributed_at'),
        created_at: (0, merchant_records_js_1.asEpoch)(data, 'created_at'),
        updated_at: (0, merchant_records_js_1.asEpoch)(data, 'updated_at'),
    };
}
function toAffiliateRewardDto(id, data) {
    return {
        id: (0, merchant_records_js_1.asString)(data, 'id') ?? id,
        merchant_id: (0, merchant_records_js_1.asString)(data, 'merchant_id') ?? '',
        affiliate_id: (0, merchant_records_js_1.asString)(data, 'affiliate_id') ?? '',
        attribution_id: (0, merchant_records_js_1.asString)(data, 'attribution_id'),
        type: ((0, merchant_records_js_1.asString)(data, 'type') ?? '').toUpperCase(),
        value: (0, merchant_records_js_1.asNumber)(data, 'value') ?? 0,
        value_type: ((0, merchant_records_js_1.asString)(data, 'value_type') ?? 'POINTS').toUpperCase(),
        status: readRewardStatus(data),
        trigger_sale_id: (0, merchant_records_js_1.asString)(data, 'trigger_sale_id'),
        approved_by: (0, merchant_records_js_1.asString)(data, 'approved_by'),
        approved_at: (0, merchant_records_js_1.asEpoch)(data, 'approved_at'),
        paid_at: (0, merchant_records_js_1.asEpoch)(data, 'paid_at'),
        cancelled_at: (0, merchant_records_js_1.asEpoch)(data, 'cancelled_at'),
        created_at: (0, merchant_records_js_1.asEpoch)(data, 'created_at'),
        updated_at: (0, merchant_records_js_1.asEpoch)(data, 'updated_at'),
    };
}
function readAffiliateStatus(data) {
    const value = ((0, merchant_records_js_1.asString)(data, 'status') ?? '').trim().toUpperCase();
    return affiliate_contracts_js_1.AFFILIATE_STATUS.includes(value)
        ? value
        : 'INACTIVE';
}
function readCodeStatus(data) {
    const value = ((0, merchant_records_js_1.asString)(data, 'status') ?? '').trim().toUpperCase();
    return affiliate_contracts_js_1.AFFILIATE_CODE_STATUS.includes(value)
        ? value
        : 'DISABLED';
}
/**
 * An unreadable status reads as `CANCELLED`, not as `PENDING`.
 *
 * A corrupt row that defaulted to pending would appear in the approvals queue
 * and could be approved into points nobody earned. Defaulting to a terminal
 * state fails closed.
 */
function readRewardStatus(data) {
    const value = ((0, merchant_records_js_1.asString)(data, 'status') ?? '').trim().toUpperCase();
    return affiliate_contracts_js_1.REWARD_STATUS.includes(value)
        ? value
        : 'CANCELLED';
}
