"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const retention_engine_js_1 = require("./retention_engine.js");
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
/**
 * A tiny in-memory stand-in for the four Postgres tables retention_engine.ts
 * touches. Enforces the same uniqueness rules as the real schema (one active
 * bonus per customer, one bonus per sale, one execution per source event) so
 * tests exercise the same races the real unique indexes protect against.
 */
class FakeRetentionDb {
    constructor() {
        this.entitlements = new Map(); // key: merchantId
        this.rules = new Map(); // key: merchantId:ruleKey
        this.configs = new Map(); // key: merchantId
        this.bonuses = [];
        this.executions = new Set(); // key: merchantId:customerId:ruleKey:sourceId
    }
    async query(sql, values) {
        const s = sql.replace(/\s+/g, ' ').trim();
        if (s.startsWith('SELECT is_enabled FROM entitlements')) {
            const [merchantId] = values;
            const enabled = this.entitlements.get(merchantId);
            return { rows: enabled === undefined ? [] : [{ is_enabled: enabled }] };
        }
        if (s.startsWith('INSERT INTO retention_rules')) {
            const [, merchantId, ruleKey, , , , priority, cooldownHours] = values;
            const key = `${merchantId}:${ruleKey}`;
            if (!this.rules.has(key)) {
                this.rules.set(key, { enabled: true, cooldownHours });
            }
            return { rows: [] };
        }
        if (s.startsWith('SELECT enabled, cooldown_hours FROM retention_rules')) {
            const [merchantId, ruleKey] = values;
            const rule = this.rules.get(`${merchantId}:${ruleKey}`);
            if (!rule)
                return { rows: [] };
            return { rows: [{ enabled: rule.enabled, cooldown_hours: rule.cooldownHours }] };
        }
        if (s.startsWith('SELECT enabled, type, value, validity_hours, minimum_purchase_amount')) {
            const [merchantId] = values;
            const config = this.configs.get(merchantId);
            return { rows: config ? [config] : [] };
        }
        if (s.startsWith('INSERT INTO return_bonus_configs')) {
            const [, merchantId, enabled, type, value, validityHours, minimumPurchaseAmount] = values;
            this.configs.set(merchantId, {
                enabled,
                type,
                value,
                validity_hours: validityHours,
                minimum_purchase_amount: minimumPurchaseAmount,
            });
            return { rows: [] };
        }
        if (s.startsWith("SELECT 1 FROM return_bonuses WHERE merchant_id = $1 AND customer_id = $2 AND UPPER(status) = 'ACTIVE'")) {
            const [merchantId, customerId] = values;
            const hasActive = this.bonuses.some((b) => b.merchant_id === merchantId && b.customer_id === customerId && b.status === 'ACTIVE');
            return { rows: hasActive ? [{ found: 1 }] : [] };
        }
        if (s.startsWith('INSERT INTO return_bonuses')) {
            const [id, merchantId, customerId, type, value, now, expiresAt, sourceSaleId] = values;
            const duplicateSale = this.bonuses.some((b) => b.merchant_id === merchantId && b.source_sale_id === sourceSaleId);
            if (duplicateSale)
                return { rows: [] }; // ON CONFLICT (merchant_id, source_sale_id) DO NOTHING
            const hasActive = this.bonuses.some((b) => b.merchant_id === merchantId && b.customer_id === customerId && b.status === 'ACTIVE');
            if (hasActive) {
                const error = new Error('duplicate key value violates unique constraint "idx_return_bonuses_one_active_customer"');
                error.code = '23505';
                throw error;
            }
            const bonus = {
                id,
                merchant_id: merchantId,
                customer_id: customerId,
                type,
                value,
                status: 'ACTIVE',
                issued_at: now,
                expires_at: expiresAt,
                source_sale_id: sourceSaleId,
                redeemed_at: null,
                redemption_sale_id: null,
                created_at: now,
                updated_at: now,
            };
            this.bonuses.push(bonus);
            return { rows: [bonus] };
        }
        if (s.startsWith('SELECT * FROM return_bonuses WHERE id = $1 AND merchant_id = $2')) {
            const [id, merchantId] = values;
            const bonus = this.bonuses.find((b) => b.id === id && b.merchant_id === merchantId);
            return { rows: bonus ? [bonus] : [] };
        }
        if (s.startsWith("UPDATE return_bonuses SET status = 'EXPIRED'")) {
            const [id, now] = values;
            const bonus = this.bonuses.find((b) => b.id === id && b.status === 'ACTIVE');
            if (bonus) {
                bonus.status = 'EXPIRED';
                bonus.updated_at = now;
            }
            return { rows: [] };
        }
        if (s.startsWith("UPDATE return_bonuses SET status = 'REDEEMED'")) {
            const [id, now, redemptionSaleId, merchantId] = values;
            const bonus = this.bonuses.find((b) => b.id === id && b.merchant_id === merchantId && b.status === 'ACTIVE');
            if (!bonus)
                return { rows: [] };
            bonus.status = 'REDEEMED';
            bonus.redeemed_at = now;
            bonus.redemption_sale_id = redemptionSaleId;
            bonus.updated_at = now;
            return { rows: [bonus] };
        }
        if (s.startsWith('INSERT INTO retention_rule_executions')) {
            const [, merchantId, customerId, ruleKey, , , , sourceId] = values;
            const key = `${merchantId}:${customerId}:${ruleKey}:${sourceId}`;
            const fresh = !this.executions.has(key);
            this.executions.add(key);
            // Only the event-driven insert asks; the bonus path ignores the answer.
            if (s.includes('RETURNING id')) {
                return { rows: fresh ? [{ id: key }] : [] };
            }
            return { rows: [] };
        }
        throw new Error(`FakeRetentionDb: unhandled query: ${s}`);
    }
}
(0, node_test_1.default)('seeds every MVP rule for a new merchant, enabled by default', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    strict_1.default.equal(db.rules.size, retention_engine_js_1.DEFAULT_RETENTION_RULES.length);
    strict_1.default.equal(db.rules.get('merchant-1:RETURN_BONUS_AFTER_SALE')?.enabled, true);
});
(0, node_test_1.default)('seeding twice does not overwrite an existing rule row', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    db.rules.set('merchant-1:RETURN_BONUS_AFTER_SALE', { enabled: false, cooldownHours: 999 });
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 2000);
    strict_1.default.equal(db.rules.get('merchant-1:RETURN_BONUS_AFTER_SALE')?.enabled, false);
});
(0, node_test_1.default)('missing entitlement row defaults retention_core to enabled', async () => {
    const db = new FakeRetentionDb();
    strict_1.default.equal(await (0, retention_engine_js_1.isRetentionCoreEnabled)(db, 'merchant-1'), true);
});
(0, node_test_1.default)('explicit is_enabled=false entitlement disables retention_core', async () => {
    const db = new FakeRetentionDb();
    db.entitlements.set('merchant-1', false);
    strict_1.default.equal(await (0, retention_engine_js_1.isRetentionCoreEnabled)(db, 'merchant-1'), false);
});
(0, node_test_1.default)('issues a return bonus with the configured default (20 MT / 72h) on first sale', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const result = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1',
        customerId: 'customer-1',
        saleId: 'sale-1',
        saleAmount: 100,
        now: 1000000,
    });
    strict_1.default.equal(result.issued, true);
    if (result.issued) {
        strict_1.default.equal(result.bonus.type, retention_engine_js_1.DEFAULT_RETURN_BONUS_CONFIG.type);
        strict_1.default.equal(result.bonus.value, retention_engine_js_1.DEFAULT_RETURN_BONUS_CONFIG.value);
        strict_1.default.equal(result.bonus.expires_at, 1000000 + retention_engine_js_1.DEFAULT_RETURN_BONUS_CONFIG.validityHours * 60 * 60 * 1000);
    }
    strict_1.default.equal(db.executions.has('merchant-1:customer-1:RETURN_BONUS_AFTER_SALE:sale-1'), true);
});
(0, node_test_1.default)('does not issue a second bonus while one is already active', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    const second = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-2', saleAmount: 100, now: 2000,
    });
    strict_1.default.equal(second.issued, false);
    if (!second.issued)
        strict_1.default.equal(second.reason, 'already_has_active_bonus');
    strict_1.default.equal(db.bonuses.filter((b) => b.customer_id === 'customer-1').length, 1);
});
(0, node_test_1.default)('replaying the same sale (duplicate sync) never issues a duplicate bonus', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const first = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    const replay = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    strict_1.default.equal(first.issued, true);
    strict_1.default.equal(replay.issued, false);
    strict_1.default.equal(db.bonuses.length, 1);
});
(0, node_test_1.default)('disabled rule skips issuing a bonus', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    db.rules.set('merchant-1:RETURN_BONUS_AFTER_SALE', { enabled: false, cooldownHours: 0 });
    const result = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    strict_1.default.equal(result.issued, false);
    if (!result.issued)
        strict_1.default.equal(result.reason, 'rule_disabled');
});
(0, node_test_1.default)('disabled retention_core entitlement skips issuing a bonus', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    db.entitlements.set('merchant-1', false);
    const result = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    strict_1.default.equal(result.issued, false);
    if (!result.issued)
        strict_1.default.equal(result.reason, 'feature_disabled');
});
(0, node_test_1.default)('sale below the configured minimum purchase amount is skipped', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    await (0, retention_engine_js_1.upsertReturnBonusConfig)(db, 'merchant-1', { minimumPurchaseAmount: 200 }, 1000);
    const result = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    strict_1.default.equal(result.issued, false);
    if (!result.issued)
        strict_1.default.equal(result.reason, 'below_minimum_purchase');
});
(0, node_test_1.default)('redeems an active bonus and stamps the redemption sale', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const issued = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    strict_1.default.equal(issued.issued, true);
    if (!issued.issued)
        return;
    const redeemed = await (0, retention_engine_js_1.redeemReturnBonus)(db, {
        merchantId: 'merchant-1',
        customerId: 'customer-1',
        bonusId: issued.bonus.id,
        redemptionSaleId: 'sale-2',
        now: 5000,
    });
    strict_1.default.equal(redeemed.status, 'REDEEMED');
    strict_1.default.equal(redeemed.redemption_sale_id, 'sale-2');
    strict_1.default.equal(redeemed.redeemed_at, 5000);
});
(0, node_test_1.default)('redeeming twice rejects the second attempt', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const issued = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    if (!issued.issued)
        throw new Error('expected bonus to be issued');
    await (0, retention_engine_js_1.redeemReturnBonus)(db, {
        merchantId: 'merchant-1', bonusId: issued.bonus.id, redemptionSaleId: 'sale-2', now: 5000,
    });
    await strict_1.default.rejects(() => (0, retention_engine_js_1.redeemReturnBonus)(db, {
        merchantId: 'merchant-1', bonusId: issued.bonus.id, redemptionSaleId: 'sale-3', now: 6000,
    }), (error) => error instanceof retention_engine_js_1.RetentionEngineError && error.code === 'return_bonus_not_redeemable');
});
(0, node_test_1.default)('redeeming an expired bonus is rejected and flips status to EXPIRED', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const issued = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    if (!issued.issued)
        throw new Error('expected bonus to be issued');
    const farFuture = issued.bonus.expires_at + 1;
    await strict_1.default.rejects(() => (0, retention_engine_js_1.redeemReturnBonus)(db, {
        merchantId: 'merchant-1', bonusId: issued.bonus.id, now: farFuture,
    }), (error) => error instanceof retention_engine_js_1.RetentionEngineError && error.code === 'return_bonus_expired');
    strict_1.default.equal(db.bonuses[0]?.status, 'EXPIRED');
});
(0, node_test_1.default)('redeeming with the wrong customer id is rejected', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const issued = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    if (!issued.issued)
        throw new Error('expected bonus to be issued');
    await strict_1.default.rejects(() => (0, retention_engine_js_1.redeemReturnBonus)(db, {
        merchantId: 'merchant-1', customerId: 'someone-else', bonusId: issued.bonus.id, now: 2000,
    }), (error) => error instanceof retention_engine_js_1.RetentionEngineError && error.code === 'return_bonus_customer_mismatch');
});
(0, node_test_1.default)('redeeming an unknown bonus id is rejected', async () => {
    const db = new FakeRetentionDb();
    await strict_1.default.rejects(() => (0, retention_engine_js_1.redeemReturnBonus)(db, { merchantId: 'merchant-1', bonusId: 'missing', now: 1000 }), (error) => error instanceof retention_engine_js_1.RetentionEngineError && error.code === 'return_bonus_not_found');
});
(0, node_test_1.default)('redeeming a bonus from a different merchant is rejected as not found', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const issued = await (0, retention_engine_js_1.evaluateSaleCompletedRetentionRules)(db, {
        merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
    });
    if (!issued.issued)
        throw new Error('expected bonus to be issued');
    await strict_1.default.rejects(() => (0, retention_engine_js_1.redeemReturnBonus)(db, { merchantId: 'merchant-2', bonusId: issued.bonus.id, now: 2000 }), (error) => error instanceof retention_engine_js_1.RetentionEngineError && error.code === 'return_bonus_not_found');
});
/* ------------------------------------------------------ referral wiring */
/**
 * The referral feature extends this catalog rather than starting a second
 * engine, so the tests it needs are the ones that keep it inside: the event
 * names are the stored ones, the rules live in the same table, and "already
 * ran for this fact" is answered by the same execution log.
 */
(0, node_test_1.default)('the referral events are spelled exactly as the contracts store them', () => {
    for (const event of retention_engine_js_1.AFFILIATE_RETENTION_EVENTS) {
        strict_1.default.ok(affiliate_contracts_js_1.AFFILIATE_EVENT.includes(event), `${event} is not an affiliate event name`);
    }
    // Exactly the events the plan says may only be published after commit.
    strict_1.default.deepEqual([...retention_engine_js_1.AFFILIATE_RETENTION_EVENTS].sort(), [...affiliate_contracts_js_1.POST_COMMIT_EVENTS].sort());
});
(0, node_test_1.default)('every referral event has a rule that listens for it', () => {
    for (const event of retention_engine_js_1.AFFILIATE_RETENTION_EVENTS) {
        strict_1.default.ok((0, retention_engine_js_1.retentionRulesForEvent)(event).length > 0, `${event} would be published into nothing`);
    }
});
(0, node_test_1.default)('the referral rules use the actions the spec names', () => {
    const actionFor = (event) => (0, retention_engine_js_1.retentionRulesForEvent)(event).map((rule) => (0, retention_engine_js_1.canonicalRetentionAction)(rule.action));
    strict_1.default.deepEqual(actionFor('REFERRAL_ATTRIBUTED'), ['SEND_WHATSAPP']);
    strict_1.default.deepEqual(actionFor('AFFILIATE_REWARD_CREATED'), ['SEND_WHATSAPP']);
    strict_1.default.deepEqual(actionFor('REFERRED_CUSTOMER_RETURNED'), ['CREATE_AFFILIATE_REWARD']);
});
(0, node_test_1.default)('the stored bonus action is the spec\'s ISSUE_RETURN_BONUS under its old name', () => {
    // Renaming the stored value would rewrite every merchant's catalog for no
    // behavioural gain, so the two names are mapped instead of migrated.
    strict_1.default.equal((0, retention_engine_js_1.canonicalRetentionAction)('ISSUE_BONUS'), 'ISSUE_RETURN_BONUS');
    strict_1.default.equal((0, retention_engine_js_1.canonicalRetentionAction)('issue_bonus'), 'ISSUE_RETURN_BONUS');
    strict_1.default.equal((0, retention_engine_js_1.canonicalRetentionAction)('SEND_WHATSAPP'), 'SEND_WHATSAPP');
    const bonusRule = retention_engine_js_1.DEFAULT_RETENTION_RULES.find((rule) => rule.ruleKey === 'RETURN_BONUS_AFTER_SALE');
    strict_1.default.ok(bonusRule);
    strict_1.default.equal((0, retention_engine_js_1.canonicalRetentionAction)(bonusRule.action), 'ISSUE_RETURN_BONUS');
});
(0, node_test_1.default)('only the referral event names are accepted as referral events', () => {
    strict_1.default.equal((0, retention_engine_js_1.isAffiliateRetentionEvent)('REFERRAL_ATTRIBUTED'), true);
    strict_1.default.equal((0, retention_engine_js_1.isAffiliateRetentionEvent)('REFERRAL_REJECTED'), false);
    strict_1.default.equal((0, retention_engine_js_1.isAffiliateRetentionEvent)('referral_attributed'), false);
    strict_1.default.equal((0, retention_engine_js_1.isAffiliateRetentionEvent)(undefined), false);
});
(0, node_test_1.default)('a published referral event runs its rules once', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const dispatched = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, {
        merchantId: 'merchant-1',
        event: 'REFERRAL_ATTRIBUTED',
        sourceId: 'ae_1',
        subjectId: 'customer-1',
        now: 2000,
    });
    strict_1.default.deepEqual(dispatched, [
        {
            ruleKey: 'REFERRAL_ATTRIBUTED_NOTICE',
            action: 'SEND_WHATSAPP',
            status: 'executed',
        },
    ]);
    strict_1.default.equal(db.executions.has('merchant-1:customer-1:REFERRAL_ATTRIBUTED_NOTICE:ae_1'), true);
});
(0, node_test_1.default)('the same event delivered twice runs its rules once', async () => {
    // Firestore triggers are at-least-once, and the event id is deterministic,
    // so the second delivery must be recognised rather than acted on.
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const input = {
        merchantId: 'merchant-1',
        event: 'AFFILIATE_REWARD_CREATED',
        sourceId: 'ae_reward_1',
        subjectId: 'customer-1',
        now: 2000,
    };
    const first = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, input);
    const second = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, { ...input, now: 9999 });
    strict_1.default.equal(first[0].status, 'executed');
    strict_1.default.equal(second[0].status, 'duplicate');
    strict_1.default.equal(db.executions.size, 1);
});
(0, node_test_1.default)('two different facts of the same kind both run', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    const one = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, {
        merchantId: 'merchant-1',
        event: 'REFERRED_CUSTOMER_RETURNED',
        sourceId: 'ae_return_1',
        subjectId: 'customer-1',
        now: 2000,
    });
    const two = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, {
        merchantId: 'merchant-1',
        event: 'REFERRED_CUSTOMER_RETURNED',
        sourceId: 'ae_return_2',
        subjectId: 'customer-1',
        now: 2000 + 60000,
    });
    strict_1.default.equal(one[0].status, 'executed');
    strict_1.default.equal(one[0].action, 'CREATE_AFFILIATE_REWARD');
    strict_1.default.equal(two[0].status, 'executed', 'a second genuine return was silenced');
});
(0, node_test_1.default)('a rule the merchant turned off does not run and is not recorded', async () => {
    const db = new FakeRetentionDb();
    await (0, retention_engine_js_1.seedDefaultRetentionRules)(db, 'merchant-1', 1000);
    db.rules.set('merchant-1:REFERRAL_ATTRIBUTED_NOTICE', {
        enabled: false,
        cooldownHours: 0,
    });
    (0, node_test_1.default)('referral bridge rules are not exposed as merchant toggles', () => {
        strict_1.default.equal((0, retention_engine_js_1.isMerchantEditableRetentionRuleKey)('NEAR_REWARD'), true);
        strict_1.default.equal((0, retention_engine_js_1.isMerchantEditableRetentionRuleKey)('REFERRAL_ATTRIBUTED_NOTICE'), false);
        strict_1.default.equal((0, retention_engine_js_1.isMerchantEditableRetentionRuleKey)('REFERRAL_RETURN_REWARD'), false);
        strict_1.default.equal((0, retention_engine_js_1.isMerchantEditableRetentionRuleKey)('REFERRAL_REWARD_NOTICE'), false);
    });
    const dispatched = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, {
        merchantId: 'merchant-1',
        event: 'REFERRAL_ATTRIBUTED',
        sourceId: 'ae_1',
        subjectId: 'customer-1',
        now: 2000,
    });
    strict_1.default.equal(dispatched[0].status, 'rule_disabled');
    strict_1.default.equal(db.executions.size, 0);
});
(0, node_test_1.default)('an event with no customer is still recorded against its affiliate', async () => {
    const db = new FakeRetentionDb();
    const dispatched = await (0, retention_engine_js_1.dispatchAffiliateRetentionEvent)(db, {
        merchantId: 'merchant-1',
        event: 'AFFILIATE_REWARD_CREATED',
        sourceId: 'ae_2',
        subjectId: '   ',
        now: 2000,
    });
    strict_1.default.equal(dispatched[0].status, 'executed');
    strict_1.default.equal(db.executions.has('merchant-1:unknown:REFERRAL_REWARD_NOTICE:ae_2'), true);
});
