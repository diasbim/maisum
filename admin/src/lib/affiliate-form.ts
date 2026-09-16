/**
 * What the affiliate screens need before there is a network, a session or a
 * React tree.
 *
 * Two jobs live here, and they are the two that fail quietly everywhere else.
 *
 * The first is reading a form. Every field an owner types is checked against
 * the same rule the API applies in `affiliate_api_contracts.ts`, so a bad
 * percentage is refused beside the input that produced it instead of coming
 * back as a 400 with the whole form blanked. The client check is a courtesy,
 * never the authority: the server re-reads every one of these values and the
 * portal shows what it says.
 *
 * The second is the arithmetic a screen would otherwise do inline — a masked
 * phone, a conversion rate over zero attempts, the last thing that happened to
 * an affiliate, the WhatsApp link a code is shared with. None of it needs the
 * framework, and all of it is the kind of thing that is wrong for months
 * before anybody notices.
 *
 * `merchant-api.ts` imports `server-only`, so nothing there can be run by
 * `node --test`. This file is the part that can be, in the same arrangement
 * `merchant-list.ts` already uses.
 */

export const DAY_MS = 24 * 60 * 60 * 1000;

/** The plan's default, and the same one the API applies when asked for none. */
export const DEFAULT_CODE_VALIDITY_DAYS = 30;

/** Mirrors the choices the app offers, so the two surfaces agree. */
export const CODE_VALIDITY_DAY_OPTIONS = [30, 60, 90, 180] as const;

export const BENEFIT_TYPES = ['FIXED_AMOUNT', 'PERCENTAGE', 'POINTS'] as const;
export type BenefitTypeValue = (typeof BENEFIT_TYPES)[number];

/** `PERCENTAGE_RANGE` in `affiliate_contracts.ts`. */
export const PERCENTAGE_RANGE = { min: 1, max: 50 } as const;

const MAX_FIXED_AMOUNT = 1_000_000;
const MAX_POINTS = 100_000;
const MAX_USAGE_LIMIT = 100_000;
const MAX_VALIDITY_DAYS = 730;

/* --------------------------------------------------------------- outcomes */

export type Parsed<T> =
  | { ok: true; value: T }
  | { ok: false; field: string; message: string };

function bad(field: string, message: string): Parsed<never> {
  return { ok: false, field, message };
}

function good<T>(value: T): Parsed<T> {
  return { ok: true, value };
}

/** What a form field carries once the browser has sent it. */
export type RawField = string | null | undefined;

function text(raw: RawField): string {
  return typeof raw === 'string' ? raw.trim() : '';
}

/* ----------------------------------------------------------------- people */

/** `NAME_PATTERN` in `affiliate_api_contracts.ts`, character for character. */
const NAME_PATTERN = /^[\p{L}][\p{L}\p{M}'\-. ]{1,59}$/u;

export function parseAffiliateName(raw: RawField): Parsed<string> {
  const collapsed = text(raw).replace(/\s+/g, ' ');
  if (collapsed === '') {
    return bad('name', 'Indique o nome do afiliado.');
  }
  if (!NAME_PATTERN.test(collapsed)) {
    return bad('name', 'Use apenas letras, entre 2 e 60 caracteres.');
  }
  // The code is minted from the first word, so a first word with no letter in
  // it would produce `AFI--XXXX`. The API refuses it; saying so here is the
  // only place that can still point at the field.
  if (collapsed.split(' ')[0].replace(/[^\p{L}]/gu, '') === '') {
    return bad('name', 'O primeiro nome tem de ter letras.');
  }
  return good(collapsed);
}

const PHONE_PREFIXES = new Set(['82', '83', '84', '85', '86', '87']);

/**
 * `normalizeMozambiquePhoneToE164` in `functions/src/index.ts`.
 *
 * Duplicated rather than imported, like `admin-claims.ts`: Next's bundler will
 * not resolve a runtime import from outside the app root. The test beside this
 * file reads the Functions source and fails if the prefixes drift apart.
 */
export function normalizeMozambiquePhone(raw: RawField): string | null {
  const clean = text(raw).replace(/[\s-]/g, '');
  let local: string | null = null;

  if (clean.startsWith('+258')) local = clean.substring(4);
  else if (clean.startsWith('258') && clean.length === 12) local = clean.substring(3);
  else if (clean.length === 9) local = clean;

  if (
    local !== null &&
    /^[0-9]{9}$/.test(local) &&
    PHONE_PREFIXES.has(local.substring(0, 2))
  ) {
    return `+258${local}`;
  }
  return null;
}

export function parseAffiliatePhone(raw: RawField): Parsed<string> {
  const normalized = normalizeMozambiquePhone(raw);
  if (normalized === null) {
    return bad('phone', 'Use um número de Moçambique válido (8X XXX XXXX).');
  }
  return good(normalized);
}

/**
 * A phone as a list may show it.
 *
 * The same shape `maskPhone` writes in `affiliate_notifications.ts`, so a
 * number read off a screen and a number read out of a log look alike. The
 * merchant API sends the real number because the owner has to reach the
 * person; a table of them is not where that belongs.
 */
export function maskAffiliatePhone(
  phone: string | null,
  last4: string | null = null,
): string {
  const digits = (phone ?? '').replace(/\D/g, '');
  if (digits.length >= 4) return `***${digits.slice(-4)}`;
  const tail = (last4 ?? '').replace(/\D/g, '');
  return tail.length >= 4 ? `***${tail.slice(-4)}` : '***';
}

/* ---------------------------------------------------------------- benefit */

export function isBenefitType(raw: string): raw is BenefitTypeValue {
  return (BENEFIT_TYPES as readonly string[]).includes(raw);
}

export type ParsedBenefit = { type: BenefitTypeValue; value: number };

/**
 * What a code takes off a sale.
 *
 * Every branch has a floor and a ceiling, exactly as `parseBenefit` does on
 * the server: an unbounded fixed amount is a typo that pays out a million
 * meticais, and an unbounded points value is the same typo against the loyalty
 * ledger.
 */
export function parseBenefit(rawType: RawField, rawValue: RawField): Parsed<ParsedBenefit> {
  const type = text(rawType).toUpperCase();
  if (!isBenefitType(type)) {
    return bad('benefit_type', 'Escolha um benefício.');
  }

  const raw = text(rawValue).replace(',', '.');
  if (raw === '') {
    return bad('benefit_value', 'Indique o valor do benefício.');
  }
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    return bad('benefit_value', 'O valor do benefício tem de ser maior que zero.');
  }

  if (type === 'PERCENTAGE') {
    if (value < PERCENTAGE_RANGE.min || value > PERCENTAGE_RANGE.max) {
      return bad(
        'benefit_value',
        `A percentagem deve estar entre ${PERCENTAGE_RANGE.min}% e ${PERCENTAGE_RANGE.max}%.`,
      );
    }
    if (!hasAtMostTwoDecimals(value)) {
      return bad('benefit_value', 'Use no máximo duas casas decimais.');
    }
    return good({ type, value });
  }

  if (type === 'FIXED_AMOUNT') {
    if (value > MAX_FIXED_AMOUNT) {
      return bad('benefit_value', 'O desconto é demasiado alto.');
    }
    if (!hasAtMostTwoDecimals(value)) {
      return bad('benefit_value', 'Use no máximo duas casas decimais.');
    }
    return good({ type, value });
  }

  if (!Number.isInteger(value)) {
    return bad('benefit_value', 'Os pontos têm de ser um número inteiro.');
  }
  if (value > MAX_POINTS) {
    return bad('benefit_value', 'São pontos a mais para um só código.');
  }
  return good({ type, value });
}

function hasAtMostTwoDecimals(value: number): boolean {
  return Math.round(value * 100) === Number((value * 100).toFixed(6));
}

/**
 * How many times a code may still be used. Blank is unlimited, which is what
 * the API stores as `null` — and is not the same as zero, which it refuses.
 */
export function parseUsageLimit(raw: RawField): Parsed<number | null> {
  const value = text(raw);
  if (value === '') return good(null);
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_USAGE_LIMIT) {
    return bad(
      'usage_limit',
      'O limite tem de ser um número inteiro entre 1 e 100000, ou ficar vazio.',
    );
  }
  return good(parsed);
}

/**
 * The validity window, in days from today.
 *
 * Blank means different things on the two forms, and the difference matters:
 * creating a code with no answer takes the plan's 30 days, while editing one
 * with no answer leaves the dates exactly as they are. `optional` is which of
 * those this call is.
 */
export function parseValidityDays(
  raw: RawField,
  options: { optional?: boolean } = {},
): Parsed<number | null> {
  const value = text(raw);
  if (value === '') {
    return good(options.optional === true ? null : DEFAULT_CODE_VALIDITY_DAYS);
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_VALIDITY_DAYS) {
    return bad('validity_days', 'A validade tem de ser entre 1 e 730 dias.');
  }
  return good(parsed);
}

/** The epoch the API stores, from the number of days a form asked for. */
export function expiresAtFrom(days: number, now: number): number {
  return now + days * DAY_MS;
}

/* ------------------------------------------------------- what the API said */

/**
 * The field an API refusal belongs to.
 *
 * The affiliate routes answer with a stable `code` from `AFFILIATE_API_MESSAGE`
 * beside the Portuguese sentence. Routing it to the input it is about is the
 * difference between "reveja os campos" and a message under the percentage
 * that was out of range. Anything unrecognised belongs to the form as a whole.
 */
const FIELD_BY_API_CODE: Record<string, string> = {
  invalid_name: 'name',
  invalid_phone: 'phone',
  invalid_benefit_type: 'benefit_type',
  invalid_benefit_value: 'benefit_value',
  invalid_percentage: 'benefit_value',
  invalid_usage_limit: 'usage_limit',
  invalid_dates: 'validity_days',
  invalid_first_visit_only: 'first_visit_only',
  invalid_code: 'code',
  invalid_status: 'status',
  merchant_not_found: 'merchant_id',
};

export function affiliateFieldFor(code: string | null | undefined): string | null {
  if (typeof code !== 'string') return null;
  return FIELD_BY_API_CODE[code.trim()] ?? null;
}

/* ------------------------------------------------------- reading a record */

/** Just enough of a code for the rules below; the DTO satisfies it. */
export type CodeShape = {
  code: string;
  status: string;
  benefit_type: string;
  benefit_value: number;
  starts_at: number | null;
  expires_at: number | null;
  usage_limit: number | null;
  usage_count: number;
  updated_at: number | null;
};

export type AffiliateShape = {
  status: string;
  link_status: string;
  linked_at: number | null;
  created_at: number | null;
  updated_at: number | null;
  code: CodeShape | null;
};

/**
 * An affiliate's standing here, which is not the same as their standing on the
 * platform.
 *
 * A suspended affiliate is suspended everywhere; an unlinked one is inactive
 * only for this business. Collapsing the two would hide a platform decision
 * from the owner who has to explain it to the person. Same rule as
 * `affiliateStatusLabel` in the app's `affiliate_repository.dart`.
 */
export function affiliateStanding(
  affiliate: Pick<AffiliateShape, 'status' | 'link_status'>,
): 'ACTIVE' | 'INACTIVE' | 'SUSPENDED' {
  const status = affiliate.status.trim().toUpperCase();
  if (status === 'SUSPENDED') return 'SUSPENDED';
  if (affiliate.link_status.trim().toUpperCase() !== 'ACTIVE') return 'INACTIVE';
  if (status === 'INACTIVE') return 'INACTIVE';
  return 'ACTIVE';
}

/**
 * Whether there is a code worth handing to somebody.
 *
 * A suspended or unlinked affiliate still has a code row, and sharing it would
 * be a promise the business cannot keep: the till refuses it. The share
 * control is absent in that case rather than merely failing later.
 */
export type AffiliateCodeAvailability =
  | 'ACTIVE'
  | 'DISABLED'
  | 'NOT_STARTED'
  | 'EXPIRED'
  | 'EXHAUSTED';

export function affiliateCodeAvailability(
  code: CodeShape,
  now = Date.now(),
): AffiliateCodeAvailability {
  if (code.status.trim().toUpperCase() !== 'ACTIVE') return 'DISABLED';
  if (code.starts_at !== null && now < code.starts_at) return 'NOT_STARTED';
  if (code.expires_at !== null && now >= code.expires_at) return 'EXPIRED';
  if (code.usage_limit !== null && code.usage_count >= code.usage_limit) {
    return 'EXHAUSTED';
  }
  return 'ACTIVE';
}

export function affiliateCodeAvailabilityLabel(
  availability: AffiliateCodeAvailability,
): string {
  switch (availability) {
    case 'ACTIVE':
      return 'Ativo';
    case 'DISABLED':
      return 'Desativado';
    case 'NOT_STARTED':
      return 'Ainda não começou';
    case 'EXPIRED':
      return 'Expirado';
    case 'EXHAUSTED':
      return 'Limite atingido';
  }
}

export function affiliateCodeAvailabilityTone(
  availability: AffiliateCodeAvailability,
): string {
  switch (availability) {
    case 'ACTIVE':
      return 'ACTIVE';
    case 'NOT_STARTED':
      return 'PENDING';
    case 'DISABLED':
    case 'EXPIRED':
    case 'EXHAUSTED':
      return 'CANCELLED';
  }
}

export function canShareAffiliateCode(
  affiliate: AffiliateShape,
  now = Date.now(),
): boolean {
  if (affiliate.code === null) return false;
  if (affiliateCodeAvailability(affiliate.code, now) !== 'ACTIVE') return false;
  return affiliateStanding(affiliate) === 'ACTIVE';
}

/** The most recent thing that happened, over every date a record carries. */
export function lastAffiliateActivityAt(affiliate: AffiliateShape): number | null {
  const candidates = [
    affiliate.updated_at,
    affiliate.code?.updated_at ?? null,
    affiliate.linked_at,
  ].filter((value): value is number => typeof value === 'number');
  if (candidates.length === 0) return affiliate.created_at;
  return Math.max(...candidates);
}

/* ---------------------------------------------------------------- sharing */

/** "50" reads as money; "50.0" reads as a bug. */
export function formatBenefitNumber(value: number): string {
  if (Number.isInteger(value)) return String(value);
  return value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

/** The benefit in words, or null when there is nothing safe to promise. */
export function describeBenefit(
  type: string | null,
  value: number | null,
): string | null {
  if (type === null || value === null || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  const amount = formatBenefitNumber(value);
  switch (type.trim().toUpperCase()) {
    case 'PERCENTAGE':
      return `${amount}% de desconto`;
    case 'FIXED_AMOUNT':
      return `${amount} MT de desconto`;
    case 'POINTS':
      return `${amount} pontos`;
    default:
      return null;
  }
}

/**
 * The invitation an affiliate forwards.
 *
 * Word for word the message the app composes in
 * `affiliate_share_message.dart`: the same code arrives by two routes and two
 * wordings would read as two different offers.
 */
export function buildAffiliateShareMessage(input: {
  code: string;
  businessName: string;
  benefitType?: string | null;
  benefitValue?: number | null;
}): string {
  const business =
    input.businessName.trim() === '' ? 'o nosso negócio' : input.businessName.trim();
  const benefit = describeBenefit(
    input.benefitType ?? null,
    input.benefitValue ?? null,
  );
  const lines = [
    `Olá! Use o código ${input.code.trim().toUpperCase()} em ${business}.`,
    ...(benefit === null ? [] : [`Na primeira compra recebe ${benefit}.`]),
    'Basta dizer o código no balcão.',
  ];
  return lines.join('\n');
}

/**
 * A `wa.me` link with the message already in it.
 *
 * Nothing is sent: the link opens WhatsApp — the app on a phone, the web
 * client on a desktop — with the text ready, and the owner picks who gets it.
 * Without a number it opens the contact picker, which is the right behaviour
 * when the API withheld one.
 */
export function buildWhatsAppShareUrl(input: {
  message: string;
  phone?: string | null;
}): string {
  const digits = (input.phone ?? '').replace(/\D/g, '');
  const encoded = encodeURIComponent(input.message);
  if (digits === '') return `https://wa.me/?text=${encoded}`;
  const number = digits.startsWith('258') ? digits : `258${digits}`;
  return `https://wa.me/${number}?text=${encoded}`;
}

/* ---------------------------------------------------------------- metrics */

export type MetricsShape = {
  unique_validation_attempts: number;
  confirmed_attributions: number;
  conversion_rate: number;
};

/**
 * The conversion rate as a screen may print it.
 *
 * A business with no validations yet has no rate — not zero. Printing "0%"
 * would read as "nobody converts" on the very screen an owner opens to find
 * out whether anyone has tried, and the division that produced it is the one
 * every dashboard gets wrong first. The server's own rate is preferred when it
 * is a usable number; the recomputation is the guard against an envelope that
 * carried `NaN` or nothing at all.
 */
export function conversionRateText(metrics: MetricsShape): string {
  const attempts = metrics.unique_validation_attempts;
  if (!Number.isFinite(attempts) || attempts <= 0) return '—';

  const rate = Number.isFinite(metrics.conversion_rate)
    ? metrics.conversion_rate
    : metrics.confirmed_attributions / attempts;
  if (!Number.isFinite(rate) || rate < 0) return '—';

  return `${Math.round(Math.min(rate, 1) * 100)}%`;
}
