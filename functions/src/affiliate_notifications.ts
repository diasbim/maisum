import type { RewardStatus } from './affiliate_contracts.js';

/**
 * What the affiliate and the customer are told, and how it leaves the building.
 *
 * Two halves, kept apart on purpose. Composing a message is pure and is tested
 * here; delivering one goes through an adapter the product does not have yet —
 * no WhatsApp provider is configured, no credentials, no webhook, no opt-in
 * policy.
 *
 * That gap is handled by refusing rather than pretending. `deliverAffiliateMessage`
 * with no adapter returns `not_configured` and the outbox row stays queued
 * without burning a retry, so the day a provider is chosen the backlog sends. A
 * stub that returned success would mark every message delivered and quietly
 * lose them all.
 *
 * `affiliate_outbox.ts` owns the queue around this: claiming, backoff, terminal
 * states and logging. Nothing in either file is allowed to affect a sale — the
 * rows are written inside the sale transaction and read by a worker afterwards,
 * so a provider outage is a backlog rather than a rolled-back sale.
 */

export const AFFILIATE_TEMPLATE = [
  'customer_referral_thanks',
  'affiliate_new_customer',
  'affiliate_customer_returned',
] as const;
export type AffiliateTemplate = (typeof AFFILIATE_TEMPLATE)[number];

/** True for a template this build knows how to render. */
export function isAffiliateTemplate(value: unknown): value is AffiliateTemplate {
  return (
    typeof value === 'string' &&
    (AFFILIATE_TEMPLATE as readonly string[]).includes(value)
  );
}

/**
 * Editable template strings with braced variables, as the spec asks.
 *
 * Kept as data rather than built by string concatenation in three places, so
 * changing what a merchant's customers read is one edit in one file.
 */
export const AFFILIATE_TEMPLATES: Record<AffiliateTemplate, string> = {
  customer_referral_thanks: [
    'Obrigado pela visita 🙌',
    'Usou o código de indicação e recebeu o seu benefício.',
    'Também ganhou {points} pontos no MaisUm. Volte para ganhar mais!',
  ].join('\n'),

  affiliate_new_customer: [
    'Boa! 🎉 A sua indicação trouxe um novo cliente para {merchantName}.',
    'Tem {points} pontos de recompensa {statusText}.',
  ].join('\n'),

  affiliate_customer_returned: [
    'O cliente que indicou voltou a {merchantName} 🎉',
    'Tem uma nova recompensa de {points} pontos {statusText}.',
  ].join('\n'),
};

/**
 * How a reward is described to the person who earned it.
 *
 * A `PENDING` reward must never be described as approved: the affiliate would
 * count on points a merchant has not agreed to, and the correction is worse
 * than the wait. Anything that is not approved reads as waiting.
 */
export function rewardStatusText(status: RewardStatus | string): string {
  return String(status).trim().toUpperCase() === 'APPROVED'
    ? 'aprovados'
    : 'a aguardar aprovação';
}

export type TemplateVariables = {
  points?: number;
  merchantName?: string;
  statusText?: string;
};

/**
 * Fills a template.
 *
 * An unknown placeholder is left as it stands rather than blanked. A message
 * reading "Tem {points} pontos" is obviously broken and gets reported; one
 * reading "Tem  pontos" looks like a rounding bug and does not.
 */
export function renderAffiliateMessage(
  template: AffiliateTemplate,
  variables: TemplateVariables,
): string {
  const values: Record<string, string> = {};
  if (variables.points !== undefined) {
    values.points = Math.max(0, Math.floor(variables.points)).toLocaleString('pt-PT');
  }
  if (variables.merchantName !== undefined && variables.merchantName.trim() !== '') {
    values.merchantName = variables.merchantName.trim();
  }
  if (variables.statusText !== undefined) values.statusText = variables.statusText;

  return AFFILIATE_TEMPLATES[template].replace(
    /\{(\w+)\}/g,
    (whole, key: string) => values[key] ?? whole,
  );
}

/* --------------------------------------------------------------- delivery */

export type OutboxMessage = {
  /** Derived from what the message is about, so a retry cannot double-send. */
  idempotencyKey: string;
  merchantId: string;
  template: AffiliateTemplate;
  /** Already normalised to E.164. Masked before it reaches any log. */
  toPhoneE164: string;
  body: string;
};

export type DeliveryOutcome =
  | { status: 'sent'; providerMessageId: string }
  | { status: 'not_configured' }
  | { status: 'skipped'; reason: DeliverySkipReason }
  | { status: 'failed'; retryable: boolean; error: string };

/**
 * Why a message is not going out, and is not going to.
 *
 * Every one of these is a decision, not a fault: the merchant switched
 * notifications off, nobody has a number, the customer never consented, the
 * affiliate is no longer active. Retrying any of them would send a message the
 * product was told not to send, so they are terminal.
 */
export const DELIVERY_SKIP_REASON = [
  'notifications_disabled',
  'no_phone',
  'consent_missing',
  'affiliate_inactive',
] as const;
export type DeliverySkipReason = (typeof DELIVERY_SKIP_REASON)[number];

export type WhatsAppAdapter = {
  send(message: OutboxMessage): Promise<{ providerMessageId: string }>;
};

/**
 * Sends one message, or says plainly why it did not.
 *
 * `not_configured` is deliberately distinct from `failed`: the first is the
 * expected state today and must not consume a retry or count as an error rate,
 * the second is a provider that exists and misbehaved.
 */
export async function deliverAffiliateMessage(
  message: OutboxMessage,
  options: {
    adapter: WhatsAppAdapter | null;
    notificationsEnabled: boolean;
  },
): Promise<DeliveryOutcome> {
  if (!options.notificationsEnabled) {
    return { status: 'skipped', reason: 'notifications_disabled' };
  }
  if (message.toPhoneE164.trim() === '') {
    return { status: 'skipped', reason: 'no_phone' };
  }
  if (options.adapter === null) return { status: 'not_configured' };

  try {
    const { providerMessageId } = await options.adapter.send(message);
    return { status: 'sent', providerMessageId };
  } catch (error) {
    return {
      status: 'failed',
      // Without a provider there is no error taxonomy yet, so everything is
      // treated as worth retrying. A permanent failure retried a few times is
      // cheap; a transient one dropped is a message the affiliate never gets.
      retryable: true,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/* ---------------------------------------------------------------- backoff */

/** Attempts before a message is parked for a person to look at. */
export const MAX_DELIVERY_ATTEMPTS = 5;

/**
 * When to try again.
 *
 * Exponential from thirty seconds, capped at an hour. The cap matters more
 * than the curve: an uncapped doubling puts the fifth retry days out, by which
 * point congratulating someone on a sale is strange rather than late.
 */
export function nextAttemptDelayMs(attempt: number): number {
  const base = 30_000 * Math.pow(2, Math.max(0, attempt - 1));
  return Math.min(base, 3_600_000);
}

export function isTerminalDelivery(
  outcome: DeliveryOutcome,
  attempt: number,
): boolean {
  if (outcome.status === 'sent' || outcome.status === 'skipped') return true;
  // Not configured is not terminal: the backlog is meant to send once a
  // provider exists.
  if (outcome.status === 'not_configured') return false;
  if (!outcome.retryable) return true;
  return attempt >= MAX_DELIVERY_ATTEMPTS;
}

/**
 * A phone number as it may appear in a log.
 *
 * Enough to tell two recipients apart while supporting someone reading a trace;
 * never enough to contact anybody.
 */
export function maskPhone(phoneE164: string): string {
  const digits = phoneE164.replace(/\D/g, '');
  if (digits.length < 4) return '***';
  return `***${digits.slice(-4)}`;
}
