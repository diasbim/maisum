import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AFFILIATE_RETENTION_EVENTS,
  canonicalRetentionAction,
  DEFAULT_RETENTION_RULES,
  DEFAULT_RETURN_BONUS_CONFIG,
  dispatchAffiliateRetentionEvent,
  evaluateSaleCompletedRetentionRules,
  isAffiliateRetentionEvent,
  isMerchantEditableRetentionRuleKey,
  isRetentionCoreEnabled,
  redeemReturnBonus,
  retentionRulesForEvent,
  RetentionEngineError,
  seedDefaultRetentionRules,
  upsertReturnBonusConfig,
  type Queryable,
  type ReturnBonus,
} from './retention_engine.js';
import { AFFILIATE_EVENT, POST_COMMIT_EVENTS } from './affiliate_contracts.js';

/**
 * A tiny in-memory stand-in for the four Postgres tables retention_engine.ts
 * touches. Enforces the same uniqueness rules as the real schema (one active
 * bonus per customer, one bonus per sale, one execution per source event) so
 * tests exercise the same races the real unique indexes protect against.
 */
class FakeRetentionDb implements Queryable {
  entitlements = new Map<string, boolean>(); // key: merchantId
  rules = new Map<string, { enabled: boolean; cooldownHours: number }>(); // key: merchantId:ruleKey
  configs = new Map<string, Record<string, unknown>>(); // key: merchantId
  bonuses: ReturnBonus[] = [];
  executions = new Set<string>(); // key: merchantId:customerId:ruleKey:sourceId

  async query(sql: string, values: unknown[]) {
    const s = sql.replace(/\s+/g, ' ').trim();

    if (s.startsWith('SELECT is_enabled FROM entitlements')) {
      const [merchantId] = values as [string];
      const enabled = this.entitlements.get(merchantId);
      return { rows: enabled === undefined ? [] : [{ is_enabled: enabled }] };
    }

    if (s.startsWith('INSERT INTO retention_rules')) {
      const [, merchantId, ruleKey, , , , priority, cooldownHours] = values as [
        string, string, string, string, string, string, number, number, number,
      ];
      const key = `${merchantId}:${ruleKey}`;
      if (!this.rules.has(key)) {
        this.rules.set(key, { enabled: true, cooldownHours });
      }
      return { rows: [] };
    }

    if (s.startsWith('SELECT enabled, cooldown_hours FROM retention_rules')) {
      const [merchantId, ruleKey] = values as [string, string];
      const rule = this.rules.get(`${merchantId}:${ruleKey}`);
      if (!rule) return { rows: [] };
      return { rows: [{ enabled: rule.enabled, cooldown_hours: rule.cooldownHours }] };
    }

    if (s.startsWith('SELECT enabled, type, value, validity_hours, minimum_purchase_amount')) {
      const [merchantId] = values as [string];
      const config = this.configs.get(merchantId);
      return { rows: config ? [config] : [] };
    }

    if (s.startsWith('INSERT INTO return_bonus_configs')) {
      const [, merchantId, enabled, type, value, validityHours, minimumPurchaseAmount] =
        values as [string, string, boolean, string, number, number, number, number];
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
      const [merchantId, customerId] = values as [string, string];
      const hasActive = this.bonuses.some(
        (b) => b.merchant_id === merchantId && b.customer_id === customerId && b.status === 'ACTIVE',
      );
      return { rows: hasActive ? [{ found: 1 }] : [] };
    }

    if (s.startsWith('INSERT INTO return_bonuses')) {
      const [id, merchantId, customerId, type, value, now, expiresAt, sourceSaleId] = values as [
        string, string, string, string, number, number, number, string,
      ];
      const duplicateSale = this.bonuses.some(
        (b) => b.merchant_id === merchantId && b.source_sale_id === sourceSaleId,
      );
      if (duplicateSale) return { rows: [] }; // ON CONFLICT (merchant_id, source_sale_id) DO NOTHING

      const hasActive = this.bonuses.some(
        (b) => b.merchant_id === merchantId && b.customer_id === customerId && b.status === 'ACTIVE',
      );
      if (hasActive) {
        const error = new Error('duplicate key value violates unique constraint "idx_return_bonuses_one_active_customer"');
        (error as unknown as { code: string }).code = '23505';
        throw error;
      }

      const bonus: ReturnBonus = {
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
      const [id, merchantId] = values as [string, string];
      const bonus = this.bonuses.find((b) => b.id === id && b.merchant_id === merchantId);
      return { rows: bonus ? [bonus] : [] };
    }

    if (s.startsWith("UPDATE return_bonuses SET status = 'EXPIRED'")) {
      const [id, now] = values as [string, number];
      const bonus = this.bonuses.find((b) => b.id === id && b.status === 'ACTIVE');
      if (bonus) {
        bonus.status = 'EXPIRED';
        bonus.updated_at = now;
      }
      return { rows: [] };
    }

    if (s.startsWith("UPDATE return_bonuses SET status = 'REDEEMED'")) {
      const [id, now, redemptionSaleId, merchantId] = values as [string, number, string | null, string];
      const bonus = this.bonuses.find(
        (b) => b.id === id && b.merchant_id === merchantId && b.status === 'ACTIVE',
      );
      if (!bonus) return { rows: [] };
      bonus.status = 'REDEEMED';
      bonus.redeemed_at = now;
      bonus.redemption_sale_id = redemptionSaleId;
      bonus.updated_at = now;
      return { rows: [bonus] };
    }

    if (s.startsWith('INSERT INTO retention_rule_executions')) {
      const [, merchantId, customerId, ruleKey, , , , sourceId] = values as [
        string, string, string, string, string, number | null, string | null, string | null, number,
      ];
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

test('seeds every MVP rule for a new merchant, enabled by default', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  assert.equal(db.rules.size, DEFAULT_RETENTION_RULES.length);
  assert.equal(db.rules.get('merchant-1:RETURN_BONUS_AFTER_SALE')?.enabled, true);
});

test('seeding twice does not overwrite an existing rule row', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  db.rules.set('merchant-1:RETURN_BONUS_AFTER_SALE', { enabled: false, cooldownHours: 999 });
  await seedDefaultRetentionRules(db, 'merchant-1', 2000);
  assert.equal(db.rules.get('merchant-1:RETURN_BONUS_AFTER_SALE')?.enabled, false);
});

test('missing entitlement row defaults retention_core to enabled', async () => {
  const db = new FakeRetentionDb();
  assert.equal(await isRetentionCoreEnabled(db, 'merchant-1'), true);
});

test('explicit is_enabled=false entitlement disables retention_core', async () => {
  const db = new FakeRetentionDb();
  db.entitlements.set('merchant-1', false);
  assert.equal(await isRetentionCoreEnabled(db, 'merchant-1'), false);
});

test('issues a return bonus with the configured default (20 MT / 72h) on first sale', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);

  const result = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1',
    customerId: 'customer-1',
    saleId: 'sale-1',
    saleAmount: 100,
    now: 1_000_000,
  });

  assert.equal(result.issued, true);
  if (result.issued) {
    assert.equal(result.bonus.type, DEFAULT_RETURN_BONUS_CONFIG.type);
    assert.equal(result.bonus.value, DEFAULT_RETURN_BONUS_CONFIG.value);
    assert.equal(result.bonus.expires_at, 1_000_000 + DEFAULT_RETURN_BONUS_CONFIG.validityHours * 60 * 60 * 1000);
  }
  assert.equal(db.executions.has('merchant-1:customer-1:RETURN_BONUS_AFTER_SALE:sale-1'), true);
});

test('does not issue a second bonus while one is already active', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });

  const second = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-2', saleAmount: 100, now: 2000,
  });

  assert.equal(second.issued, false);
  if (!second.issued) assert.equal(second.reason, 'already_has_active_bonus');
  assert.equal(db.bonuses.filter((b) => b.customer_id === 'customer-1').length, 1);
});

test('replaying the same sale (duplicate sync) never issues a duplicate bonus', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  const first = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });
  const replay = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });

  assert.equal(first.issued, true);
  assert.equal(replay.issued, false);
  assert.equal(db.bonuses.length, 1);
});

test('disabled rule skips issuing a bonus', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  db.rules.set('merchant-1:RETURN_BONUS_AFTER_SALE', { enabled: false, cooldownHours: 0 });

  const result = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });

  assert.equal(result.issued, false);
  if (!result.issued) assert.equal(result.reason, 'rule_disabled');
});

test('disabled retention_core entitlement skips issuing a bonus', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  db.entitlements.set('merchant-1', false);

  const result = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });

  assert.equal(result.issued, false);
  if (!result.issued) assert.equal(result.reason, 'feature_disabled');
});

test('sale below the configured minimum purchase amount is skipped', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  await upsertReturnBonusConfig(db, 'merchant-1', { minimumPurchaseAmount: 200 }, 1000);

  const result = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });

  assert.equal(result.issued, false);
  if (!result.issued) assert.equal(result.reason, 'below_minimum_purchase');
});

test('redeems an active bonus and stamps the redemption sale', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  const issued = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });
  assert.equal(issued.issued, true);
  if (!issued.issued) return;

  const redeemed = await redeemReturnBonus(db, {
    merchantId: 'merchant-1',
    customerId: 'customer-1',
    bonusId: issued.bonus.id,
    redemptionSaleId: 'sale-2',
    now: 5000,
  });

  assert.equal(redeemed.status, 'REDEEMED');
  assert.equal(redeemed.redemption_sale_id, 'sale-2');
  assert.equal(redeemed.redeemed_at, 5000);
});

test('redeeming twice rejects the second attempt', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  const issued = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });
  if (!issued.issued) throw new Error('expected bonus to be issued');

  await redeemReturnBonus(db, {
    merchantId: 'merchant-1', bonusId: issued.bonus.id, redemptionSaleId: 'sale-2', now: 5000,
  });

  await assert.rejects(
    () => redeemReturnBonus(db, {
      merchantId: 'merchant-1', bonusId: issued.bonus.id, redemptionSaleId: 'sale-3', now: 6000,
    }),
    (error: unknown) => error instanceof RetentionEngineError && error.code === 'return_bonus_not_redeemable',
  );
});

test('redeeming an expired bonus is rejected and flips status to EXPIRED', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  const issued = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });
  if (!issued.issued) throw new Error('expected bonus to be issued');

  const farFuture = issued.bonus.expires_at + 1;
  await assert.rejects(
    () => redeemReturnBonus(db, {
      merchantId: 'merchant-1', bonusId: issued.bonus.id, now: farFuture,
    }),
    (error: unknown) => error instanceof RetentionEngineError && error.code === 'return_bonus_expired',
  );
  assert.equal(db.bonuses[0]?.status, 'EXPIRED');
});

test('redeeming with the wrong customer id is rejected', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  const issued = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });
  if (!issued.issued) throw new Error('expected bonus to be issued');

  await assert.rejects(
    () => redeemReturnBonus(db, {
      merchantId: 'merchant-1', customerId: 'someone-else', bonusId: issued.bonus.id, now: 2000,
    }),
    (error: unknown) => error instanceof RetentionEngineError && error.code === 'return_bonus_customer_mismatch',
  );
});

test('redeeming an unknown bonus id is rejected', async () => {
  const db = new FakeRetentionDb();
  await assert.rejects(
    () => redeemReturnBonus(db, { merchantId: 'merchant-1', bonusId: 'missing', now: 1000 }),
    (error: unknown) => error instanceof RetentionEngineError && error.code === 'return_bonus_not_found',
  );
});

test('redeeming a bonus from a different merchant is rejected as not found', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  const issued = await evaluateSaleCompletedRetentionRules(db, {
    merchantId: 'merchant-1', customerId: 'customer-1', saleId: 'sale-1', saleAmount: 100, now: 1000,
  });
  if (!issued.issued) throw new Error('expected bonus to be issued');

  await assert.rejects(
    () => redeemReturnBonus(db, { merchantId: 'merchant-2', bonusId: issued.bonus.id, now: 2000 }),
    (error: unknown) => error instanceof RetentionEngineError && error.code === 'return_bonus_not_found',
  );
});

/* ------------------------------------------------------ referral wiring */

/**
 * The referral feature extends this catalog rather than starting a second
 * engine, so the tests it needs are the ones that keep it inside: the event
 * names are the stored ones, the rules live in the same table, and "already
 * ran for this fact" is answered by the same execution log.
 */

test('the referral events are spelled exactly as the contracts store them', () => {
  for (const event of AFFILIATE_RETENTION_EVENTS) {
    assert.ok(
      (AFFILIATE_EVENT as readonly string[]).includes(event),
      `${event} is not an affiliate event name`,
    );
  }
  // Exactly the events the plan says may only be published after commit.
  assert.deepEqual([...AFFILIATE_RETENTION_EVENTS].sort(), [...POST_COMMIT_EVENTS].sort());
});

test('every referral event has a rule that listens for it', () => {
  for (const event of AFFILIATE_RETENTION_EVENTS) {
    assert.ok(
      retentionRulesForEvent(event).length > 0,
      `${event} would be published into nothing`,
    );
  }
});

test('the referral rules use the actions the spec names', () => {
  const actionFor = (event: (typeof AFFILIATE_RETENTION_EVENTS)[number]) =>
    retentionRulesForEvent(event).map((rule) => canonicalRetentionAction(rule.action));

  assert.deepEqual(actionFor('REFERRAL_ATTRIBUTED'), ['SEND_WHATSAPP']);
  assert.deepEqual(actionFor('AFFILIATE_REWARD_CREATED'), ['SEND_WHATSAPP']);
  assert.deepEqual(actionFor('REFERRED_CUSTOMER_RETURNED'), ['CREATE_AFFILIATE_REWARD']);
});

test('the stored bonus action is the spec\'s ISSUE_RETURN_BONUS under its old name', () => {
  // Renaming the stored value would rewrite every merchant's catalog for no
  // behavioural gain, so the two names are mapped instead of migrated.
  assert.equal(canonicalRetentionAction('ISSUE_BONUS'), 'ISSUE_RETURN_BONUS');
  assert.equal(canonicalRetentionAction('issue_bonus'), 'ISSUE_RETURN_BONUS');
  assert.equal(canonicalRetentionAction('SEND_WHATSAPP'), 'SEND_WHATSAPP');

  const bonusRule = DEFAULT_RETENTION_RULES.find(
    (rule) => rule.ruleKey === 'RETURN_BONUS_AFTER_SALE',
  );
  assert.ok(bonusRule);
  assert.equal(canonicalRetentionAction(bonusRule.action), 'ISSUE_RETURN_BONUS');
});

test('only the referral event names are accepted as referral events', () => {
  assert.equal(isAffiliateRetentionEvent('REFERRAL_ATTRIBUTED'), true);
  assert.equal(isAffiliateRetentionEvent('REFERRAL_REJECTED'), false);
  assert.equal(isAffiliateRetentionEvent('referral_attributed'), false);
  assert.equal(isAffiliateRetentionEvent(undefined), false);
});

test('a published referral event runs its rules once', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);

  const dispatched = await dispatchAffiliateRetentionEvent(db, {
    merchantId: 'merchant-1',
    event: 'REFERRAL_ATTRIBUTED',
    sourceId: 'ae_1',
    subjectId: 'customer-1',
    now: 2000,
  });

  assert.deepEqual(dispatched, [
    {
      ruleKey: 'REFERRAL_ATTRIBUTED_NOTICE',
      action: 'SEND_WHATSAPP',
      status: 'executed',
    },
  ]);
  assert.equal(
    db.executions.has('merchant-1:customer-1:REFERRAL_ATTRIBUTED_NOTICE:ae_1'),
    true,
  );
});

test('the same event delivered twice runs its rules once', async () => {
  // Firestore triggers are at-least-once, and the event id is deterministic,
  // so the second delivery must be recognised rather than acted on.
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);

  const input = {
    merchantId: 'merchant-1',
    event: 'AFFILIATE_REWARD_CREATED' as const,
    sourceId: 'ae_reward_1',
    subjectId: 'customer-1',
    now: 2000,
  };

  const first = await dispatchAffiliateRetentionEvent(db, input);
  const second = await dispatchAffiliateRetentionEvent(db, { ...input, now: 9999 });

  assert.equal(first[0].status, 'executed');
  assert.equal(second[0].status, 'duplicate');
  assert.equal(db.executions.size, 1);
});

test('two different facts of the same kind both run', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);

  const one = await dispatchAffiliateRetentionEvent(db, {
    merchantId: 'merchant-1',
    event: 'REFERRED_CUSTOMER_RETURNED',
    sourceId: 'ae_return_1',
    subjectId: 'customer-1',
    now: 2000,
  });
  const two = await dispatchAffiliateRetentionEvent(db, {
    merchantId: 'merchant-1',
    event: 'REFERRED_CUSTOMER_RETURNED',
    sourceId: 'ae_return_2',
    subjectId: 'customer-1',
    now: 2000 + 60_000,
  });

  assert.equal(one[0].status, 'executed');
  assert.equal(one[0].action, 'CREATE_AFFILIATE_REWARD');
  assert.equal(two[0].status, 'executed', 'a second genuine return was silenced');
});

test('a rule the merchant turned off does not run and is not recorded', async () => {
  const db = new FakeRetentionDb();
  await seedDefaultRetentionRules(db, 'merchant-1', 1000);
  db.rules.set('merchant-1:REFERRAL_ATTRIBUTED_NOTICE', {
    enabled: false,
    cooldownHours: 0,
  });

  test('referral bridge rules are not exposed as merchant toggles', () => {
    assert.equal(isMerchantEditableRetentionRuleKey('NEAR_REWARD'), true);
    assert.equal(
      isMerchantEditableRetentionRuleKey('REFERRAL_ATTRIBUTED_NOTICE'),
      false,
    );
    assert.equal(
      isMerchantEditableRetentionRuleKey('REFERRAL_RETURN_REWARD'),
      false,
    );
    assert.equal(
      isMerchantEditableRetentionRuleKey('REFERRAL_REWARD_NOTICE'),
      false,
    );
  });

  const dispatched = await dispatchAffiliateRetentionEvent(db, {
    merchantId: 'merchant-1',
    event: 'REFERRAL_ATTRIBUTED',
    sourceId: 'ae_1',
    subjectId: 'customer-1',
    now: 2000,
  });

  assert.equal(dispatched[0].status, 'rule_disabled');
  assert.equal(db.executions.size, 0);
});

test('an event with no customer is still recorded against its affiliate', async () => {
  const db = new FakeRetentionDb();
  const dispatched = await dispatchAffiliateRetentionEvent(db, {
    merchantId: 'merchant-1',
    event: 'AFFILIATE_REWARD_CREATED',
    sourceId: 'ae_2',
    subjectId: '   ',
    now: 2000,
  });

  assert.equal(dispatched[0].status, 'executed');
  assert.equal(db.executions.has('merchant-1:unknown:REFERRAL_REWARD_NOTICE:ae_2'), true);
});
