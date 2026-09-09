"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_RETURN_BONUS_CONFIG = exports.RetentionEngineError = exports.DEFAULT_RETENTION_RULES = void 0;
exports.seedDefaultRetentionRules = seedDefaultRetentionRules;
exports.isRetentionCoreEnabled = isRetentionCoreEnabled;
exports.listRetentionRules = listRetentionRules;
exports.setRetentionRuleEnabled = setRetentionRuleEnabled;
exports.isRetentionRuleKey = isRetentionRuleKey;
exports.getReturnBonusConfig = getReturnBonusConfig;
exports.upsertReturnBonusConfig = upsertReturnBonusConfig;
exports.evaluateSaleCompletedRetentionRules = evaluateSaleCompletedRetentionRules;
exports.redeemReturnBonus = redeemReturnBonus;
const crypto_1 = require("crypto");
/** Rules (MVP) from the Retention Engine spec, in priority order. */
exports.DEFAULT_RETENTION_RULES = [
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
class RetentionEngineError extends Error {
    constructor(status, code, message) {
        super(message);
        this.name = 'RetentionEngineError';
        this.status = status;
        this.code = code;
    }
}
exports.RetentionEngineError = RetentionEngineError;
exports.DEFAULT_RETURN_BONUS_CONFIG = {
    enabled: true,
    type: 'DISCOUNT',
    value: 20,
    validityHours: 72,
    minimumPurchaseAmount: 0,
};
/**
 * Idempotently ensures every MVP rule has a config row for the merchant.
 * Safe to call on every bootstrap/sync cycle; existing rows are untouched so
 * a merchant's own enable/disable/priority edits are never overwritten.
 */
async function seedDefaultRetentionRules(db, merchantId, now) {
    for (const rule of exports.DEFAULT_RETENTION_RULES) {
        await db.query(`
        INSERT INTO retention_rules (
          id, merchant_id, rule_key, name, event, action,
          conditions, priority, enabled, cooldown_hours, created_at, updated_at
        ) VALUES ($1,$2,$3,$4,$5,$6,'{}'::jsonb,$7,true,$8,$9,$9)
        ON CONFLICT (merchant_id, rule_key) DO NOTHING
      `, [
            (0, crypto_1.randomUUID)(),
            merchantId,
            rule.ruleKey,
            rule.name,
            rule.event,
            rule.action,
            rule.priority,
            rule.cooldownHours,
            now,
        ]);
    }
}
/**
 * Retention Engine features (Bónus de Regresso, Near Reward, Re-engagement,
 * Win-back) are free on every plan (see FeatureKeys.retentionCore). Missing
 * entitlement rows (merchants that predate this feature key) default to
 * enabled; only an explicit `is_enabled = false` row turns it off.
 */
async function isRetentionCoreEnabled(db, merchantId) {
    const result = await db.query(`SELECT is_enabled FROM entitlements WHERE merchant_id = $1 AND feature_key = 'retention_core' LIMIT 1`, [merchantId]);
    const row = result.rows[0];
    if (!row)
        return true;
    return row.is_enabled !== false;
}
/** For the merchant "toggles only" UI (spec section 9): lists every seeded rule. */
async function listRetentionRules(db, merchantId) {
    const result = await db.query(`
      SELECT rule_key, name, event, action, priority, enabled, cooldown_hours
      FROM retention_rules WHERE merchant_id = $1 ORDER BY priority ASC, rule_key ASC
    `, [merchantId]);
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
async function setRetentionRuleEnabled(db, merchantId, ruleKey, enabled, now) {
    await db.query(`UPDATE retention_rules SET enabled = $1, updated_at = $2 WHERE merchant_id = $3 AND rule_key = $4`, [enabled, now, merchantId, ruleKey]);
}
function isRetentionRuleKey(value) {
    return exports.DEFAULT_RETENTION_RULES.some((rule) => rule.ruleKey === value);
}
async function getRuleIfEnabled(db, merchantId, ruleKey) {
    const result = await db.query(`SELECT enabled, cooldown_hours FROM retention_rules WHERE merchant_id = $1 AND rule_key = $2 LIMIT 1`, [merchantId, ruleKey]);
    const row = result.rows[0];
    // No seeded row yet defaults to enabled (matches the spec's "ON by
    // default" MVP toggles) rather than silently doing nothing until the next
    // bootstrap/sync seeds the catalog.
    if (!row)
        return { cooldownHours: 0 };
    if (row.enabled === false)
        return null;
    return { cooldownHours: Number(row.cooldown_hours ?? 0) };
}
async function hasRecentExecution(db, merchantId, customerId, ruleKey, cooldownHours, now) {
    if (cooldownHours <= 0)
        return false;
    const since = now - cooldownHours * 60 * 60 * 1000;
    const result = await db.query(`
      SELECT 1 FROM retention_rule_executions
      WHERE merchant_id = $1 AND customer_id = $2 AND rule_key = $3 AND executed_at >= $4
      LIMIT 1
    `, [merchantId, customerId, ruleKey, since]);
    return result.rows.length > 0;
}
async function logExecution(db, input) {
    await db.query(`
      INSERT INTO retention_rule_executions (
        id, merchant_id, customer_id, rule_key, action,
        message_priority, source_type, source_id, executed_at, created_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)
      ON CONFLICT (merchant_id, customer_id, rule_key, source_id) DO NOTHING
    `, [
        (0, crypto_1.randomUUID)(),
        input.merchantId,
        input.customerId,
        input.ruleKey,
        input.action,
        input.messagePriority,
        input.sourceType,
        input.sourceId,
        input.now,
    ]);
}
async function getReturnBonusConfig(db, merchantId) {
    const result = await db.query(`
      SELECT enabled, type, value, validity_hours, minimum_purchase_amount
      FROM return_bonus_configs WHERE merchant_id = $1 LIMIT 1
    `, [merchantId]);
    const row = result.rows[0];
    if (!row)
        return exports.DEFAULT_RETURN_BONUS_CONFIG;
    return {
        enabled: row.enabled !== false,
        type: String(row.type ?? exports.DEFAULT_RETURN_BONUS_CONFIG.type),
        value: Number(row.value ?? exports.DEFAULT_RETURN_BONUS_CONFIG.value),
        validityHours: Number(row.validity_hours ?? exports.DEFAULT_RETURN_BONUS_CONFIG.validityHours),
        minimumPurchaseAmount: Number(row.minimum_purchase_amount ?? exports.DEFAULT_RETURN_BONUS_CONFIG.minimumPurchaseAmount),
    };
}
async function upsertReturnBonusConfig(db, merchantId, patch, now) {
    const current = await getReturnBonusConfig(db, merchantId);
    const next = { ...current, ...patch };
    await db.query(`
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
    `, [
        (0, crypto_1.randomUUID)(),
        merchantId,
        next.enabled,
        next.type,
        next.value,
        next.validityHours,
        next.minimumPurchaseAmount,
        now,
    ]);
    return next;
}
/**
 * Entry point for the `SALE_COMPLETED` event. Only F1 (Bónus de Regresso) is
 * wired to a concrete action today; other MVP rules are evaluated against
 * the seeded catalog but have no dispatcher yet, so they are no-ops here.
 */
async function evaluateSaleCompletedRetentionRules(db, input) {
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
    const activeResult = await db.query(`SELECT 1 FROM return_bonuses WHERE merchant_id = $1 AND customer_id = $2 AND UPPER(status) = 'ACTIVE' LIMIT 1`, [merchantId, customerId]);
    if (activeResult.rows.length > 0) {
        return { issued: false, reason: 'already_has_active_bonus' };
    }
    const id = (0, crypto_1.randomUUID)();
    const expiresAt = now + config.validityHours * 60 * 60 * 1000;
    // Only one ON CONFLICT arbiter is allowed per INSERT, so this targets the
    // per-sale uniqueness (the common duplicate-sync case). The max-1-active
    // index still protects against the rarer concurrent-sale race: a violation
    // there surfaces as Postgres error 23505, caught below and treated as a
    // normal "already has an active bonus" outcome rather than a 500.
    let insertResult;
    try {
        insertResult = await db.query(`
        INSERT INTO return_bonuses (
          id, merchant_id, customer_id, type, value, status,
          issued_at, expires_at, source_sale_id, created_at, updated_at
        ) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8,$6,$6)
        ON CONFLICT (merchant_id, source_sale_id) WHERE source_sale_id IS NOT NULL DO NOTHING
        RETURNING *
      `, [id, merchantId, customerId, config.type, config.value, now, expiresAt, saleId]);
    }
    catch (error) {
        const code = error?.code;
        if (code === '23505') {
            return { issued: false, reason: 'already_has_active_bonus' };
        }
        throw error;
    }
    const bonus = insertResult.rows[0];
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
async function redeemReturnBonus(db, input) {
    const { merchantId, customerId, bonusId, redemptionSaleId, now } = input;
    const existingResult = await db.query(`SELECT * FROM return_bonuses WHERE id = $1 AND merchant_id = $2 LIMIT 1`, [bonusId, merchantId]);
    const existing = existingResult.rows[0];
    if (!existing) {
        throw new RetentionEngineError(404, 'return_bonus_not_found', 'Return bonus not found.');
    }
    if (customerId && existing.customer_id !== customerId) {
        throw new RetentionEngineError(403, 'return_bonus_customer_mismatch', 'This bonus does not belong to that customer.');
    }
    if (existing.status !== 'ACTIVE') {
        throw new RetentionEngineError(409, 'return_bonus_not_redeemable', `Bonus is ${existing.status.toLowerCase()}, not active.`);
    }
    if (existing.expires_at <= now) {
        // Lazily flip to EXPIRED rather than relying solely on a cron job.
        await db.query(`UPDATE return_bonuses SET status = 'EXPIRED', updated_at = $2 WHERE id = $1 AND UPPER(status) = 'ACTIVE'`, [bonusId, now]);
        throw new RetentionEngineError(409, 'return_bonus_expired', 'Bonus has expired.');
    }
    const updateResult = await db.query(`
      UPDATE return_bonuses
      SET status = 'REDEEMED', redeemed_at = $2, redemption_sale_id = $3, updated_at = $2
      WHERE id = $1 AND merchant_id = $4 AND UPPER(status) = 'ACTIVE'
      RETURNING *
    `, [bonusId, now, redemptionSaleId ?? null, merchantId]);
    const redeemed = updateResult.rows[0];
    if (!redeemed) {
        throw new RetentionEngineError(409, 'return_bonus_already_redeemed', 'Bonus was already redeemed or expired concurrently.');
    }
    return redeemed;
}
