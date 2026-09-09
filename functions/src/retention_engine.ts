import { randomUUID } from 'crypto';

/**
 * Generalizes the ad hoc RED-risk/near-reward automation that used to live
 * inline in index.ts (`upsertCustomerRiskScore`) into a small rule catalog +
 * cooldown log, per the Retention Engine spec: EVENT -> STATE -> RULE ->
 * ACTION. This module intentionally implements only the RETURN_BONUS_AFTER_SALE
 * action end to end; the remaining MVP rules are seeded as metadata so the
 * catalog/cooldown plumbing already supports them when their actions land.
 */

export type RetentionRuleKey =
  | 'RETURN_BONUS_AFTER_SALE'
  | 'NEAR_REWARD'
  | 'CUSTOMER_DUE'
  | 'WIN_BACK'
  | 'STREAK_MILESTONE'
  | 'BIRTHDAY'
  | 'REFERRAL';

export type RetentionRuleAction = 'ISSUE_BONUS' | 'SEND_WHATSAPP' | 'ADD_POINTS';

export type RetentionRuleEvent =
  | 'SALE_COMPLETED'
  | 'REWARD_NEAR'
  | 'CUSTOMER_DUE'
  | 'CUSTOMER_INACTIVE'
  | 'STREAK_REACHED'
  | 'BIRTHDAY_APPROACHING'
  | 'REFERRAL_COMPLETED';

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
];

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
  return result.rows.map((row) => ({
    ruleKey: String(row.rule_key),
    name: String(row.name),
    event: String(row.event),
    action: String(row.action),
    priority: Number(row.priority),
    enabled: row.enabled !== false,
    cooldownHours: Number(row.cooldown_hours ?? 0),
  }));
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
