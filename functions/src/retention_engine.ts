import { randomUUID } from 'crypto';

import type { AffiliateEventType } from './affiliate_contracts.js';

/**
 * Generalizes the ad hoc RED-risk/near-reward automation that used to live
 * inline in index.ts (`upsertCustomerRiskScore`) into a small rule catalog +
 * cooldown log, per the Retention Engine spec: EVENT -> STATE -> RULE ->
 * ACTION. This module intentionally implements only the RETURN_BONUS_AFTER_SALE
 * action end to end; the remaining MVP rules are seeded as metadata so the
 * catalog/cooldown plumbing already supports them when their actions land.
 *
 * The referral feature extends this catalog rather than starting a second
 * engine: its three post-commit events are rows in the same `retention_rules`
 * table, evaluated by the same enable/cooldown checks and recorded in the same
 * `retention_rule_executions` log, so "this rule already ran for this fact" has
 * one definition for every automation in the product.
 */

export type RetentionRuleKey =
  | 'RETURN_BONUS_AFTER_SALE'
  | 'NEAR_REWARD'
  | 'CUSTOMER_DUE'
  | 'WIN_BACK'
  | 'STREAK_MILESTONE'
  | 'BIRTHDAY'
  | 'REFERRAL'
  | 'REFERRAL_ATTRIBUTED_NOTICE'
  | 'REFERRAL_RETURN_REWARD'
  | 'REFERRAL_REWARD_NOTICE';

/**
 * What a rule does.
 *
 * `ISSUE_BONUS` and `ISSUE_RETURN_BONUS` are the same action under two names:
 * the first is what is already stored in every seeded row, the second is the
 * name the referral spec uses. Rewriting the stored value would rename data in
 * every merchant's catalog for no behavioural gain, so the stored spelling
 * stays and `canonicalRetentionAction` maps it to the spec's one wherever the
 * engine reasons about actions rather than persists them.
 */
export type RetentionRuleAction =
  | 'ISSUE_BONUS'
  | 'ISSUE_RETURN_BONUS'
  | 'SEND_WHATSAPP'
  | 'ADD_POINTS'
  | 'CREATE_AFFILIATE_REWARD';

export type RetentionRuleEvent =
  | 'SALE_COMPLETED'
  | 'REWARD_NEAR'
  | 'CUSTOMER_DUE'
  | 'CUSTOMER_INACTIVE'
  | 'STREAK_REACHED'
  | 'BIRTHDAY_APPROACHING'
  | 'REFERRAL_COMPLETED'
  | 'REFERRAL_ATTRIBUTED'
  | 'REFERRED_CUSTOMER_RETURNED'
  | 'AFFILIATE_REWARD_CREATED';

/**
 * The referral events this engine reacts to, spelled exactly as
 * `affiliate_contracts.ts` stores them.
 *
 * `satisfies` is the point of the declaration: renaming an event there without
 * renaming it here stops compiling, instead of leaving a rule that silently
 * never matches anything.
 */
export const AFFILIATE_RETENTION_EVENTS = [
  'REFERRAL_ATTRIBUTED',
  'REFERRED_CUSTOMER_RETURNED',
  'AFFILIATE_REWARD_CREATED',
] as const satisfies readonly AffiliateEventType[];

export type AffiliateRetentionEvent = (typeof AFFILIATE_RETENTION_EVENTS)[number];

export function isAffiliateRetentionEvent(
  value: unknown,
): value is AffiliateRetentionEvent {
  return (
    typeof value === 'string' &&
    (AFFILIATE_RETENTION_EVENTS as readonly string[]).includes(value)
  );
}

/** The spec's name for an action, given whatever spelling is stored. */
export function canonicalRetentionAction(action: string): RetentionRuleAction {
  const normalized = action.trim().toUpperCase();
  if (normalized === 'ISSUE_BONUS') return 'ISSUE_RETURN_BONUS';
  return normalized as RetentionRuleAction;
}

export type DefaultRetentionRule = {
  ruleKey: RetentionRuleKey;
  name: string;
  event: RetentionRuleEvent;
  action: RetentionRuleAction;
  priority: number;
  cooldownHours: number;
};

/** Rules (MVP) from the Retention Engine spec, in priority order. */
export const DEFAULT_RETENTION_RULES: DefaultRetentionRule[] = [
  {
    ruleKey: 'RETURN_BONUS_AFTER_SALE',
    name: 'Bónus de Regresso',
    event: 'SALE_COMPLETED',
    action: 'ISSUE_BONUS',
    priority: 1,
    cooldownHours: 0,
  },
  {
    ruleKey: 'NEAR_REWARD',
    name: 'Near Reward',
    event: 'REWARD_NEAR',
    action: 'SEND_WHATSAPP',
    priority: 2,
    cooldownHours: 24,
  },
  {
    ruleKey: 'CUSTOMER_DUE',
    name: 'Re-engagement',
    event: 'CUSTOMER_DUE',
    action: 'SEND_WHATSAPP',
    priority: 3,
    cooldownHours: 24 * 7,
  },
  {
    ruleKey: 'WIN_BACK',
    name: 'Win-back',
    event: 'CUSTOMER_INACTIVE',
    action: 'ISSUE_BONUS',
    priority: 3,
    cooldownHours: 24 * 30,
  },
  {
    ruleKey: 'STREAK_MILESTONE',
    name: 'Streak Milestone',
    event: 'STREAK_REACHED',
    action: 'ADD_POINTS',
    priority: 4,
    cooldownHours: 0,
  },
  {
    ruleKey: 'BIRTHDAY',
    name: 'Birthday',
    event: 'BIRTHDAY_APPROACHING',
    action: 'ISSUE_BONUS',
    priority: 4,
    cooldownHours: 24 * 300,
  },
  {
    ruleKey: 'REFERRAL',
    name: 'Referral',
    event: 'REFERRAL_COMPLETED',
    action: 'ADD_POINTS',
    priority: 4,
    cooldownHours: 0,
  },
  /**
   * The referral rules, in the order the facts happen.
   *
   * All three have no cooldown on purpose: every one of them is keyed to a
   * single fact — one acquisition, one return, one reward — and a cooldown
   * would drop the second genuine referral a customer brings in the same day.
   * Duplicate suppression comes from the execution log's source id instead,
   * which is the only kind that cannot silence real events.
   */
  {
    ruleKey: 'REFERRAL_ATTRIBUTED_NOTICE',
    name: 'Indicação confirmada',
    event: 'REFERRAL_ATTRIBUTED',
    action: 'SEND_WHATSAPP',
    priority: 2,
    cooldownHours: 0,
  },
  {
    ruleKey: 'REFERRAL_RETURN_REWARD',
    name: 'Cliente indicado voltou',
    event: 'REFERRED_CUSTOMER_RETURNED',
    action: 'CREATE_AFFILIATE_REWARD',
    priority: 3,
    cooldownHours: 0,
  },
  {
    ruleKey: 'REFERRAL_REWARD_NOTICE',
    name: 'Recompensa de indicação',
    event: 'AFFILIATE_REWARD_CREATED',
    action: 'SEND_WHATSAPP',
    priority: 3,
    cooldownHours: 0,
  },
];

/** Every rule that listens for an event, most important first. */
export function retentionRulesForEvent(
  event: RetentionRuleEvent,
): DefaultRetentionRule[] {
  return DEFAULT_RETENTION_RULES.filter((rule) => rule.event === event).sort(
    (left, right) => left.priority - right.priority,
  );
}

export type Queryable = {
  query(sql: string, values: unknown[]): Promise<{ rows: Record<string, unknown>[]; rowCount?: number | null }>;
};

export class RetentionEngineError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = 'RetentionEngineError';
    this.status = status;
    this.code = code;
  }
}

export type ReturnBonusConfig = {
  enabled: boolean;
  type: string;
  value: number;
  validityHours: number;
  minimumPurchaseAmount: number;
};

export const DEFAULT_RETURN_BONUS_CONFIG: ReturnBonusConfig = {
  enabled: true,
  type: 'DISCOUNT',
  value: 20,
  validityHours: 72,
  minimumPurchaseAmount: 0,
};

export type ReturnBonus = {
  id: string;
  merchant_id: string;
  customer_id: string;
  type: string;
  value: number;
  status: 'ACTIVE' | 'REDEEMED' | 'EXPIRED' | 'CANCELLED';
  issued_at: number;
  expires_at: number;
  source_sale_id: string | null;
  redeemed_at: number | null;
  redemption_sale_id: string | null;
  created_at: number;
  updated_at: number;
};

/**
 * Idempotently ensures every MVP rule has a config row for the merchant.
 * Safe to call on every bootstrap/sync cycle; existing rows are untouched so
 * a merchant's own enable/disable/priority edits are never overwritten.
 */
export async function seedDefaultRetentionRules(
  db: Queryable,
  merchantId: string,
  now: number,
): Promise<void> {
  for (const rule of DEFAULT_RETENTION_RULES) {
    await db.query(
      `
        INSERT INTO retention_rules (
          id, merchant_id, rule_key, name, event, action,
          conditions, priority, enabled, cooldown_hours, created_at, updated_at
        ) VALUES ($1,$2,$3,$4,$5,$6,'{}'::jsonb,$7,true,$8,$9,$9)
        ON CONFLICT (merchant_id, rule_key) DO NOTHING
      `,
      [
        randomUUID(),
        merchantId,
        rule.ruleKey,
        rule.name,
        rule.event,
        rule.action,
        rule.priority,
        rule.cooldownHours,
        now,
      ],
    );
  }
}

/**
 * Retention Engine features (Bónus de Regresso, Near Reward, Re-engagement,
 * Win-back) are free on every plan (see FeatureKeys.retentionCore). Missing
 * entitlement rows (merchants that predate this feature key) default to
 * enabled; only an explicit `is_enabled = false` row turns it off.
 */
export async function isRetentionCoreEnabled(
  db: Queryable,
  merchantId: string,
): Promise<boolean> {
  const result = await db.query(
    `SELECT is_enabled FROM entitlements WHERE merchant_id = $1 AND feature_key = 'retention_core' LIMIT 1`,
    [merchantId],
  );
  const row = result.rows[0];
  if (!row) return true;
  return row.is_enabled !== false;
}

export type RetentionRuleSummary = {
  ruleKey: string;
  name: string;
  event: string;
  action: string;
  priority: number;
  enabled: boolean;
  cooldownHours: number;
};

/** For the merchant "toggles only" UI (spec section 9): lists every seeded rule. */
export async function listRetentionRules(
  db: Queryable,
  merchantId: string,
): Promise<RetentionRuleSummary[]> {
  const result = await db.query(
    `
      SELECT rule_key, name, event, action, priority, enabled, cooldown_hours
      FROM retention_rules WHERE merchant_id = $1 ORDER BY priority ASC, rule_key ASC
    `,
    [merchantId],
  );
  return result.rows
    .map((row) => ({
      ruleKey: String(row.rule_key),
      name: String(row.name),
      event: String(row.event),
      action: String(row.action),
      priority: Number(row.priority),
      enabled: row.enabled !== false,
      cooldownHours: Number(row.cooldown_hours ?? 0),
    }))
    .filter((rule) => isMerchantEditableRetentionRuleKey(rule.ruleKey));
}

export async function setRetentionRuleEnabled(
  db: Queryable,
  merchantId: string,
  ruleKey: RetentionRuleKey,
  enabled: boolean,
  now: number,
): Promise<void> {
  await db.query(
    `UPDATE retention_rules SET enabled = $1, updated_at = $2 WHERE merchant_id = $3 AND rule_key = $4`,
    [enabled, now, merchantId, ruleKey],
  );
}

export function isRetentionRuleKey(value: string): value is RetentionRuleKey {
  return DEFAULT_RETENTION_RULES.some((rule) => rule.ruleKey === value);
}

const AFFILIATE_INTERNAL_RULE_KEYS = new Set<RetentionRuleKey>([
  'REFERRAL_ATTRIBUTED_NOTICE',
  'REFERRAL_RETURN_REWARD',
  'REFERRAL_REWARD_NOTICE',
]);

/**
 * Referral effects are configured through `affiliate_config`: notification
 * delivery and return rewards already have dedicated merchant settings.
 * Exposing a second toggle here would create two controls for one behaviour.
 */
export function isMerchantEditableRetentionRuleKey(
  value: string,
): value is RetentionRuleKey {
  return (
    isRetentionRuleKey(value) &&
    !AFFILIATE_INTERNAL_RULE_KEYS.has(value)
  );
}

async function getRuleIfEnabled(
  db: Queryable,
  merchantId: string,
  ruleKey: RetentionRuleKey,
): Promise<{ cooldownHours: number } | null> {
  const result = await db.query(
    `SELECT enabled, cooldown_hours FROM retention_rules WHERE merchant_id = $1 AND rule_key = $2 LIMIT 1`,
    [merchantId, ruleKey],
  );
  const row = result.rows[0];
  // No seeded row yet defaults to enabled (matches the spec's "ON by
  // default" MVP toggles) rather than silently doing nothing until the next
  // bootstrap/sync seeds the catalog.
  if (!row) return { cooldownHours: 0 };
  if (row.enabled === false) return null;
  return { cooldownHours: Number(row.cooldown_hours ?? 0) };
}

async function hasRecentExecution(
  db: Queryable,
  merchantId: string,
  customerId: string,
  ruleKey: RetentionRuleKey,
  cooldownHours: number,
  now: number,
): Promise<boolean> {
  if (cooldownHours <= 0) return false;
  const since = now - cooldownHours * 60 * 60 * 1000;
  const result = await db.query(
    `
      SELECT 1 FROM retention_rule_executions
      WHERE merchant_id = $1 AND customer_id = $2 AND rule_key = $3 AND executed_at >= $4
      LIMIT 1
    `,
    [merchantId, customerId, ruleKey, since],
  );
  return result.rows.length > 0;
}

async function logExecution(
  db: Queryable,
  input: {
    merchantId: string;
    customerId: string;
    ruleKey: RetentionRuleKey;
    action: RetentionRuleAction;
    messagePriority: number | null;
    sourceType: string | null;
    sourceId: string | null;
    now: number;
  },
): Promise<void> {
  await db.query(
    `
      INSERT INTO retention_rule_executions (
        id, merchant_id, customer_id, rule_key, action,
        message_priority, source_type, source_id, executed_at, created_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)
      ON CONFLICT (merchant_id, customer_id, rule_key, source_id) DO NOTHING
    `,
    [
      randomUUID(),
      input.merchantId,
      input.customerId,
      input.ruleKey,
      input.action,
      input.messagePriority,
      input.sourceType,
      input.sourceId,
      input.now,
    ],
  );
}

/**
 * Records an execution and says whether it is the first one.
 *
 * `logExecution` swallows the duplicate, which is right for the bonus path —
 * the bonus insert has already decided. An event-driven rule needs the answer:
 * a Firestore trigger fires more than once for the same write, and "did this
 * rule already run for this fact?" is what stops the second firing from acting
 * again. The unique index on (merchant, customer, rule, source) is what makes
 * the answer race-free; `RETURNING id` is how it is read.
 */
export async function recordRuleExecutionOnce(
  db: Queryable,
  input: {
    merchantId: string;
    customerId: string;
    ruleKey: RetentionRuleKey;
    action: RetentionRuleAction;
    messagePriority?: number | null;
    sourceType: string;
    sourceId: string;
    now: number;
  },
): Promise<boolean> {
  const result = await db.query(
    `
      INSERT INTO retention_rule_executions (
        id, merchant_id, customer_id, rule_key, action,
        message_priority, source_type, source_id, executed_at, created_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)
      ON CONFLICT (merchant_id, customer_id, rule_key, source_id) DO NOTHING
      RETURNING id
    `,
    [
      randomUUID(),
      input.merchantId,
      input.customerId,
      input.ruleKey,
      input.action,
      input.messagePriority ?? null,
      input.sourceType,
      input.sourceId,
      input.now,
    ],
  );
  return result.rows.length > 0;
}

export type AffiliateRetentionEventInput = {
  merchantId: string;
  event: AffiliateRetentionEvent;
  /**
   * The `affiliate_events` document id.
   *
   * Deterministic by construction, so two firings of the same trigger carry
   * the same source id and collapse into one execution.
   */
  sourceId: string;
  /** The customer the fact is about, or the affiliate when there is none. */
  subjectId: string;
  now: number;
};

export type AffiliateRetentionDispatch = {
  ruleKey: RetentionRuleKey;
  /** Always the spec's name, whatever the catalog row spells. */
  action: RetentionRuleAction;
  status: 'executed' | 'duplicate' | 'rule_disabled';
};

/**
 * Runs the referral rules for one published event.
 *
 * What a dispatch does *not* do is send anything. The messages a referral
 * produces are rows written inside the sale transaction (`affiliate_outbox`)
 * and delivered by the outbox worker, which claims each row transactionally;
 * having this path send as well would be a second sender for the same fact and
 * the one way to get two messages out of one referral. So `SEND_WHATSAPP` here
 * means "the rule fired, and the queued message is the delivery" — the value
 * of recording it is the common execution/audit trail. Merchant-facing
 * referral switches live in `affiliate_config`, so these internal bridge
 * rules are deliberately hidden from the generic retention toggle surface.
 */
export async function dispatchAffiliateRetentionEvent(
  db: Queryable,
  input: AffiliateRetentionEventInput,
): Promise<AffiliateRetentionDispatch[]> {
  const subjectId = input.subjectId.trim() === '' ? 'unknown' : input.subjectId.trim();
  const dispatched: AffiliateRetentionDispatch[] = [];

  for (const rule of retentionRulesForEvent(input.event)) {
    const action = canonicalRetentionAction(rule.action);
    if ((await getRuleIfEnabled(db, input.merchantId, rule.ruleKey)) === null) {
      dispatched.push({ ruleKey: rule.ruleKey, action, status: 'rule_disabled' });
      continue;
    }

    const first = await recordRuleExecutionOnce(db, {
      merchantId: input.merchantId,
      customerId: subjectId,
      ruleKey: rule.ruleKey,
      action: rule.action,
      sourceType: 'affiliate_event',
      sourceId: input.sourceId,
      now: input.now,
    });

    dispatched.push({
      ruleKey: rule.ruleKey,
      action,
      status: first ? 'executed' : 'duplicate',
    });
  }

  return dispatched;
}

export async function getReturnBonusConfig(
  db: Queryable,
  merchantId: string,
): Promise<ReturnBonusConfig> {
  const result = await db.query(
    `
      SELECT enabled, type, value, validity_hours, minimum_purchase_amount
      FROM return_bonus_configs WHERE merchant_id = $1 LIMIT 1
    `,
    [merchantId],
  );
  const row = result.rows[0];
  if (!row) return DEFAULT_RETURN_BONUS_CONFIG;
  return {
    enabled: row.enabled !== false,
    type: String(row.type ?? DEFAULT_RETURN_BONUS_CONFIG.type),
    value: Number(row.value ?? DEFAULT_RETURN_BONUS_CONFIG.value),
    validityHours: Number(row.validity_hours ?? DEFAULT_RETURN_BONUS_CONFIG.validityHours),
    minimumPurchaseAmount: Number(
      row.minimum_purchase_amount ?? DEFAULT_RETURN_BONUS_CONFIG.minimumPurchaseAmount,
    ),
  };
}

export async function upsertReturnBonusConfig(
  db: Queryable,
  merchantId: string,
  patch: Partial<ReturnBonusConfig>,
  now: number,
): Promise<ReturnBonusConfig> {
  const current = await getReturnBonusConfig(db, merchantId);
  const next: ReturnBonusConfig = { ...current, ...patch };
  await db.query(
    `
      INSERT INTO return_bonus_configs (
        id, merchant_id, enabled, type, value, validity_hours,
        minimum_purchase_amount, created_at, updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$8)
      ON CONFLICT (merchant_id) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        type = EXCLUDED.type,
        value = EXCLUDED.value,
        validity_hours = EXCLUDED.validity_hours,
        minimum_purchase_amount = EXCLUDED.minimum_purchase_amount,
        updated_at = EXCLUDED.updated_at
    `,
    [
      randomUUID(),
      merchantId,
      next.enabled,
      next.type,
      next.value,
      next.validityHours,
      next.minimumPurchaseAmount,
      now,
    ],
  );
  return next;
}

export type SaleCompletedRetentionInput = {
  merchantId: string;
  customerId: string;
  saleId: string;
  saleAmount: number;
  now: number;
};

export type SaleCompletedRetentionResult =
  | { issued: true; bonus: ReturnBonus; config: ReturnBonusConfig }
  | { issued: false; reason: string };

/**
 * Entry point for the `SALE_COMPLETED` event. Only F1 (Bónus de Regresso) is
 * wired to a concrete action today; other MVP rules are evaluated against
 * the seeded catalog but have no dispatcher yet, so they are no-ops here.
 */
export async function evaluateSaleCompletedRetentionRules(
  db: Queryable,
  input: SaleCompletedRetentionInput,
): Promise<SaleCompletedRetentionResult> {
  const { merchantId, customerId, saleId, saleAmount, now } = input;

  if (!(await isRetentionCoreEnabled(db, merchantId))) {
    return { issued: false, reason: 'feature_disabled' };
  }

  const rule = await getRuleIfEnabled(db, merchantId, 'RETURN_BONUS_AFTER_SALE');
  if (!rule) {
    return { issued: false, reason: 'rule_disabled' };
  }

  const config = await getReturnBonusConfig(db, merchantId);
  if (!config.enabled) {
    return { issued: false, reason: 'bonus_disabled' };
  }
  if (saleAmount < config.minimumPurchaseAmount) {
    return { issued: false, reason: 'below_minimum_purchase' };
  }

  const activeResult = await db.query(
    `SELECT 1 FROM return_bonuses WHERE merchant_id = $1 AND customer_id = $2 AND UPPER(status) = 'ACTIVE' LIMIT 1`,
    [merchantId, customerId],
  );
  if (activeResult.rows.length > 0) {
    return { issued: false, reason: 'already_has_active_bonus' };
  }

  const id = randomUUID();
  const expiresAt = now + config.validityHours * 60 * 60 * 1000;
  // Only one ON CONFLICT arbiter is allowed per INSERT, so this targets the
  // per-sale uniqueness (the common duplicate-sync case). The max-1-active
  // index still protects against the rarer concurrent-sale race: a violation
  // there surfaces as Postgres error 23505, caught below and treated as a
  // normal "already has an active bonus" outcome rather than a 500.
  let insertResult;
  try {
    insertResult = await db.query(
      `
        INSERT INTO return_bonuses (
          id, merchant_id, customer_id, type, value, status,
          issued_at, expires_at, source_sale_id, created_at, updated_at
        ) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8,$6,$6)
        ON CONFLICT (merchant_id, source_sale_id) WHERE source_sale_id IS NOT NULL DO NOTHING
        RETURNING *
      `,
      [id, merchantId, customerId, config.type, config.value, now, expiresAt, saleId],
    );
  } catch (error) {
    const code = (error as { code?: string } | null)?.code;
    if (code === '23505') {
      return { issued: false, reason: 'already_has_active_bonus' };
    }
    throw error;
  }

  const bonus = insertResult.rows[0] as ReturnBonus | undefined;
  if (!bonus) {
    return { issued: false, reason: 'duplicate_sale' };
  }

  await logExecution(db, {
    merchantId,
    customerId,
    ruleKey: 'RETURN_BONUS_AFTER_SALE',
    action: 'ISSUE_BONUS',
    messagePriority: 3,
    sourceType: 'sale',
    sourceId: saleId,
    now,
  });

  return { issued: true, bonus, config };
}

export type RedeemReturnBonusInput = {
  merchantId: string;
  customerId?: string | null;
  bonusId: string;
  redemptionSaleId?: string | null;
  now: number;
};

export async function redeemReturnBonus(
  db: Queryable,
  input: RedeemReturnBonusInput,
): Promise<ReturnBonus> {
  const { merchantId, customerId, bonusId, redemptionSaleId, now } = input;

  const existingResult = await db.query(
    `SELECT * FROM return_bonuses WHERE id = $1 AND merchant_id = $2 LIMIT 1`,
    [bonusId, merchantId],
  );
  const existing = existingResult.rows[0] as ReturnBonus | undefined;
  if (!existing) {
    throw new RetentionEngineError(404, 'return_bonus_not_found', 'Return bonus not found.');
  }
  if (customerId && existing.customer_id !== customerId) {
    throw new RetentionEngineError(
      403,
      'return_bonus_customer_mismatch',
      'This bonus does not belong to that customer.',
    );
  }
  if (existing.status !== 'ACTIVE') {
    throw new RetentionEngineError(
      409,
      'return_bonus_not_redeemable',
      `Bonus is ${existing.status.toLowerCase()}, not active.`,
    );
  }
  if (existing.expires_at <= now) {
    // Lazily flip to EXPIRED rather than relying solely on a cron job.
    await db.query(
      `UPDATE return_bonuses SET status = 'EXPIRED', updated_at = $2 WHERE id = $1 AND UPPER(status) = 'ACTIVE'`,
      [bonusId, now],
    );
    throw new RetentionEngineError(409, 'return_bonus_expired', 'Bonus has expired.');
  }

  const updateResult = await db.query(
    `
      UPDATE return_bonuses
      SET status = 'REDEEMED', redeemed_at = $2, redemption_sale_id = $3, updated_at = $2
      WHERE id = $1 AND merchant_id = $4 AND UPPER(status) = 'ACTIVE'
      RETURNING *
    `,
    [bonusId, now, redemptionSaleId ?? null, merchantId],
  );
  const redeemed = updateResult.rows[0] as ReturnBonus | undefined;
  if (!redeemed) {
    throw new RetentionEngineError(
      409,
      'return_bonus_already_redeemed',
      'Bonus was already redeemed or expired concurrently.',
    );
  }
  return redeemed;
}
