import * as admin from 'firebase-admin';
import express from 'express';
import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { Pool } from 'pg';

admin.initializeApp();

const pool = new Pool({
  connectionString: process.env.PG_CONNECTION_STRING,
  ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
  max: 10,
  idleTimeoutMillis: 30000,
});

type EntityConfig = {
  table: string;
  orderField: string;
  idField: string;
  selectSql: string;
};

type AuthedRequest = express.Request & {
  merchantId: string;
  auth?: admin.auth.DecodedIdToken;
};

const ENTITY_CONFIG: Record<string, EntityConfig> = {
  subscription_state: {
    table: 'subscription_state',
    orderField: 'updated_at',
    idField: 'merchant_id',
    selectSql: 'merchant_id as id, *',
  },
  entitlement: {
    table: 'entitlements',
    orderField: 'updated_at',
    idField: 'id',
    selectSql: '*',
  },
  feature_flag: {
    table: 'feature_flags',
    orderField: 'updated_at',
    idField: 'id',
    selectSql: '*',
  },
  remote_config: {
    table: 'remote_config',
    orderField: 'updated_at',
    idField: 'id',
    selectSql: '*',
  },
  usage_balance: {
    table: 'usage_balances',
    orderField: 'updated_at',
    idField: 'id',
    selectSql: '*',
  },
};

const app = express();
app.use(express.json({ limit: '1mb' }));

app.use(async (req, res, next) => {
  const allowDev = process.env.ALLOW_DEV_AUTH === 'true';
  const authHeader = req.headers.authorization;

  if ((!authHeader || !authHeader.startsWith('Bearer ')) && allowDev) {
    const merchantHeader = req.headers['x-merchant-id'];
    if (isNonEmptyString(merchantHeader)) {
      (req as AuthedRequest).merchantId = merchantHeader.trim();
      return next();
    }
  }

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const token = authHeader.replace('Bearer ', '').trim();
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const merchantId = resolveMerchantId(decoded);
    if (!merchantId) {
      return res
        .status(403)
        .json({ success: false, message: 'Missing merchant scope' });
    }
    const authedReq = req as AuthedRequest;
    authedReq.merchantId = merchantId;
    authedReq.auth = decoded;
    return next();
  } catch (error) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
});

const adminRouter = express.Router();
adminRouter.use((req, res, next) => {
  if (!isAdminRequest(req as AuthedRequest)) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }
  return next();
});

adminRouter.post('/plans', async (req, res) => {
  const payload = req.body ?? {};
  const planCode = pickString(payload, 'plan_code') ?? pickString(payload, 'planCode');
  const version = pickNumber(payload, 'version');
  const name = pickString(payload, 'name');
  const isActive = pickBoolean(payload, 'is_active') ?? true;

  if (!planCode || version == null || !name) {
    return res
      .status(400)
      .json({ success: false, message: 'Missing plan data' });
  }

  const now = Date.now();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (isActive) {
      await client.query(
        'UPDATE plans SET is_active = false, updated_at = $2 WHERE plan_code = $1',
        [planCode, now],
      );
    }

    const sql = `
      INSERT INTO plans (
        plan_code,
        version,
        name,
        is_active,
        created_at,
        updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6)
      ON CONFLICT (plan_code, version) DO UPDATE SET
        name = EXCLUDED.name,
        is_active = EXCLUDED.is_active,
        updated_at = EXCLUDED.updated_at
    `;

    await client.query(sql, [planCode, version, name, isActive, now, now]);
    await client.query('COMMIT');
    return res.json({ success: true });
  } catch (error) {
    await client.query('ROLLBACK');
    return res.status(500).json({ success: false, message: 'Server error' });
  } finally {
    client.release();
  }
});

adminRouter.post('/prices', async (req, res) => {
  const payload = req.body ?? {};
  const planCode = pickString(payload, 'plan_code') ?? pickString(payload, 'planCode');
  const pricingVersion =
    pickNumber(payload, 'pricing_version') ?? pickNumber(payload, 'pricingVersion');
  const currency = pickString(payload, 'currency');
  const amount = pickNumber(payload, 'amount');
  const billingPeriod = pickString(payload, 'billing_period') ?? 'monthly';
  const isActive = pickBoolean(payload, 'is_active') ?? true;

  if (!planCode || pricingVersion == null || !currency || amount == null) {
    return res
      .status(400)
      .json({ success: false, message: 'Missing pricing data' });
  }

  const now = Date.now();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (isActive) {
      await client.query(
        'UPDATE plan_prices SET is_active = false, updated_at = $3 WHERE plan_code = $1 AND currency = $2',
        [planCode, currency, now],
      );
    }

    const sql = `
      INSERT INTO plan_prices (
        plan_code,
        pricing_version,
        currency,
        amount,
        billing_period,
        is_active,
        created_at,
        updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
      ON CONFLICT (plan_code, pricing_version, currency) DO UPDATE SET
        amount = EXCLUDED.amount,
        billing_period = EXCLUDED.billing_period,
        is_active = EXCLUDED.is_active,
        updated_at = EXCLUDED.updated_at
    `;

    await client.query(sql, [
      planCode,
      pricingVersion,
      currency,
      amount,
      billingPeriod,
      isActive,
      now,
      now,
    ]);

    await client.query('COMMIT');
    return res.json({ success: true });
  } catch (error) {
    await client.query('ROLLBACK');
    return res.status(500).json({ success: false, message: 'Server error' });
  } finally {
    client.release();
  }
});

app.use('/admin', adminRouter);

app.get('/sync/:entityType', async (req, res) => {
  const { entityType } = req.params;
  const config = ENTITY_CONFIG[entityType];
  if (!config) {
    return res.status(404).json({ success: false, message: 'Unknown entity' });
  }

  const merchantId = (req as AuthedRequest).merchantId;
  const sql = `
    SELECT ${config.selectSql}
    FROM ${config.table}
    WHERE merchant_id = $1
    ORDER BY ${config.orderField} ASC, ${config.idField} ASC
  `;

  try {
    const result = await pool.query(sql, [merchantId]);
    return res.json({ success: true, data: result.rows });
  } catch (error) {
    return res.status(500).json({ success: false, message: 'Server error' });
  }
});

app.get('/sync/:entityType/changes', async (req, res) => {
  const { entityType } = req.params;
  const config = ENTITY_CONFIG[entityType];
  if (!config) {
    return res.status(404).json({ success: false, message: 'Unknown entity' });
  }

  const merchantId = (req as AuthedRequest).merchantId;
  const lastValue = parseNumber(req.query.last_value);
  const lastDocId =
    typeof req.query.last_doc_id === 'string' ? req.query.last_doc_id : null;
  const limit = clampLimit(req.query.limit, 200, 500);

  const params: Array<string | number> = [merchantId];
  let sql = `
    SELECT ${config.selectSql}
    FROM ${config.table}
    WHERE merchant_id = $1
  `;

  if (lastValue != null && lastDocId) {
    params.push(lastValue, lastDocId);
    sql += ` AND (${config.orderField}, ${config.idField}) > ($2, $3)`;
  }

  params.push(limit);
  sql += ` ORDER BY ${config.orderField} ASC, ${config.idField} ASC LIMIT $${params.length}`;

  try {
    const result = await pool.query(sql, params);
    return res.json({ success: true, data: result.rows });
  } catch (error) {
    return res.status(500).json({ success: false, message: 'Server error' });
  }
});

app.post('/sync/:entityType/:entityId', async (req, res) => {
  const { entityType, entityId } = req.params;
  const payload = req.body?.payload ?? null;
  const operation = req.body?.operation;

  if (!payload || typeof payload !== 'object') {
    return res.status(400).json({ success: false, message: 'Invalid payload' });
  }
  if (typeof operation !== 'string') {
    return res.status(400).json({ success: false, message: 'Invalid operation' });
  }

  const merchantId = (req as AuthedRequest).merchantId;
  const payloadMerchantId =
    pickString(payload, 'merchant_id') ?? pickString(payload, 'merchantId');
  if (payloadMerchantId && payloadMerchantId !== merchantId) {
    return res.status(403).json({ success: false, message: 'Tenant mismatch' });
  }

  const payloadId = pickString(payload, 'id');
  if (payloadId && payloadId !== entityId) {
    return res.status(400).json({ success: false, message: 'ID mismatch' });
  }

  try {
    switch (entityType) {
      case 'subscription_state':
        await upsertSubscriptionState(merchantId, payload);
        return res.json({ success: true });
      case 'entitlement':
        if (operation === 'delete') {
          await deleteById('entitlements', entityId, merchantId);
        } else {
          await upsertEntitlement(merchantId, payload, entityId);
        }
        return res.json({ success: true });
      case 'feature_flag':
        if (operation === 'delete') {
          await deleteById('feature_flags', entityId, merchantId);
        } else {
          await upsertFeatureFlag(merchantId, payload, entityId);
        }
        return res.json({ success: true });
      case 'remote_config':
        if (operation === 'delete') {
          await deleteById('remote_config', entityId, merchantId);
        } else {
          await upsertRemoteConfig(merchantId, payload, entityId);
        }
        return res.json({ success: true });
      case 'usage_event':
        if (operation !== 'create') {
          return res
            .status(400)
            .json({ success: false, message: 'usage_event is create-only' });
        }
        await insertUsageEvent(merchantId, payload, entityId);
        return res.json({ success: true });
      default:
        return res.status(404).json({ success: false, message: 'Unknown entity' });
    }
  } catch (error) {
    return res.status(500).json({ success: false, message: 'Server error' });
  }
});

export const api = onRequest({ cors: true }, app);

function resolveMerchantId(decoded: admin.auth.DecodedIdToken): string | null {
  const claims = decoded as Record<string, unknown>;
  const fromClaims =
    typeof claims.merchant_id === 'string'
      ? claims.merchant_id
      : typeof claims.merchantId === 'string'
        ? claims.merchantId
        : null;
  return fromClaims ?? decoded.uid ?? null;
}

function isAdminRequest(req: AuthedRequest): boolean {
  const adminKey = process.env.ADMIN_API_KEY;
  const headerKey = pickHeaderString(req.headers['x-admin-key']);
  if (adminKey && headerKey && adminKey === headerKey) {
    return true;
  }

  const claims = req.auth as Record<string, unknown> | undefined;
  if (!claims) return false;
  if (claims.admin === true) return true;
  if (claims.is_admin === true) return true;
  if (claims.role === 'admin') return true;
  return false;
}

function parseNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (isNonEmptyString(value)) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function clampLimit(value: unknown, fallback: number, max: number): number {
  const parsed = parseNumber(value);
  if (parsed == null || parsed <= 0) return fallback;
  return Math.min(Math.floor(parsed), max);
}

function pickString(payload: Record<string, unknown>, key: string): string | null {
  const value = payload[key];
  if (isNonEmptyString(value)) {
    return value.trim();
  }
  return null;
}

function pickBoolean(payload: Record<string, unknown>, key: string): boolean | null {
  const value = payload[key];
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true') return true;
    if (normalized === 'false') return false;
    if (normalized === '1') return true;
    if (normalized === '0') return false;
  }
  return null;
}

function pickHeaderString(value: string | string[] | undefined): string | null {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }
  if (Array.isArray(value) && value.length > 0) {
    const first = value[0];
    return typeof first === 'string' && first.trim().length > 0
      ? first.trim()
      : null;
  }
  return null;
}

function pickNumber(payload: Record<string, unknown>, key: string): number | null {
  const value = payload[key];
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (isNonEmptyString(value)) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

async function upsertSubscriptionState(
  merchantId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const planCode =
    pickString(payload, 'plan_code') ?? pickString(payload, 'planCode');
  const planNameInput =
    pickString(payload, 'plan_name') ?? pickString(payload, 'planName');
  const status =
    pickString(payload, 'status') ??
    pickString(payload, 'subscription_status') ??
    'TRIAL';

  if (!planCode) {
    throw new Error('Missing plan data');
  }

  const planVersionInput =
    pickNumber(payload, 'plan_version') ??
    pickNumber(payload, 'planVersion') ??
    null;
  const pricingVersionInput =
    pickNumber(payload, 'pricing_version') ??
    pickNumber(payload, 'pricingVersion') ??
    null;
  const trialEndsAt =
    pickNumber(payload, 'trial_ends_at') ?? pickNumber(payload, 'trialEndsAt');
  const graceEndsAt =
    pickNumber(payload, 'grace_ends_at') ?? pickNumber(payload, 'graceEndsAt');
  const periodStart =
    pickNumber(payload, 'period_start') ?? pickNumber(payload, 'periodStart');
  const periodEnd =
    pickNumber(payload, 'period_end') ?? pickNumber(payload, 'periodEnd');
  const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();

  const resolved = await resolvePlanAndPricing(
    merchantId,
    planCode,
    planNameInput,
    planVersionInput,
    pricingVersionInput,
  );

  const sql = `
    INSERT INTO subscription_state (
      merchant_id,
      plan_code,
      plan_name,
      plan_version,
      pricing_version,
      status,
      trial_ends_at,
      grace_ends_at,
      period_start,
      period_end,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (merchant_id) DO UPDATE SET
      plan_code = EXCLUDED.plan_code,
      plan_name = EXCLUDED.plan_name,
      plan_version = EXCLUDED.plan_version,
      pricing_version = EXCLUDED.pricing_version,
      status = EXCLUDED.status,
      trial_ends_at = EXCLUDED.trial_ends_at,
      grace_ends_at = EXCLUDED.grace_ends_at,
      period_start = EXCLUDED.period_start,
      period_end = EXCLUDED.period_end,
      updated_at = EXCLUDED.updated_at
  `;

  await pool.query(sql, [
    merchantId,
    planCode,
    resolved.planName,
    resolved.planVersion,
    resolved.pricingVersion,
    status,
    trialEndsAt,
    graceEndsAt,
    periodStart,
    periodEnd,
    updatedAt,
  ]);
}

type SubscriptionStateRow = {
  plan_code: string;
  plan_name: string;
  plan_version: number;
  pricing_version: number;
};

async function resolvePlanAndPricing(
  merchantId: string,
  planCode: string,
  planNameInput: string | null,
  planVersionInput: number | null,
  pricingVersionInput: number | null,
): Promise<{ planName: string; planVersion: number; pricingVersion: number }> {
  const existing = await fetchSubscriptionState(merchantId);
  const samePlan = existing?.plan_code === planCode;

  const activePlan = await fetchActivePlan(planCode);
  const activePricingVersion = await fetchActivePricingVersion(planCode);

  const planVersion =
    planVersionInput ??
    (samePlan ? existing?.plan_version ?? null : null) ??
    activePlan?.version ??
    1;

  const pricingVersion =
    pricingVersionInput ??
    (samePlan ? existing?.pricing_version ?? null : null) ??
    activePricingVersion ??
    1;

  const planName =
    planNameInput ??
    (samePlan ? existing?.plan_name ?? null : null) ??
    activePlan?.name ??
    planCode;

  return { planName, planVersion, pricingVersion };
}

async function fetchSubscriptionState(
  merchantId: string,
): Promise<SubscriptionStateRow | null> {
  const sql = `
    SELECT plan_code, plan_name, plan_version, pricing_version
    FROM subscription_state
    WHERE merchant_id = $1
    LIMIT 1
  `;
  const result = await pool.query(sql, [merchantId]);
  return result.rows[0] ?? null;
}

async function fetchActivePlan(
  planCode: string,
): Promise<{ version: number; name: string } | null> {
  const sql = `
    SELECT version, name
    FROM plans
    WHERE plan_code = $1 AND is_active = true
    ORDER BY version DESC
    LIMIT 1
  `;
  const result = await pool.query(sql, [planCode]);
  return result.rows[0] ?? null;
}

async function fetchActivePricingVersion(
  planCode: string,
): Promise<number | null> {
  const sql = `
    SELECT pricing_version
    FROM plan_prices
    WHERE plan_code = $1 AND is_active = true
    ORDER BY pricing_version DESC
    LIMIT 1
  `;
  const result = await pool.query(sql, [planCode]);
  if (!result.rows[0]) return null;
  return Number(result.rows[0].pricing_version) || null;
}

async function upsertEntitlement(
  merchantId: string,
  payload: Record<string, unknown>,
  entityId: string,
): Promise<void> {
  const featureKey =
    pickString(payload, 'feature_key') ?? pickString(payload, 'featureKey');
  if (!featureKey) {
    throw new Error('Missing feature key');
  }

  const id = pickString(payload, 'id') ?? entityId;
  const isEnabled =
    pickBoolean(payload, 'is_enabled') ??
    pickBoolean(payload, 'isEnabled') ??
    true;
  const limitValue =
    pickNumber(payload, 'limit_value') ?? pickNumber(payload, 'limitValue');
  const unit = pickString(payload, 'unit');
  const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();

  const sql = `
    INSERT INTO entitlements (
      id,
      merchant_id,
      feature_key,
      is_enabled,
      limit_value,
      unit,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT (merchant_id, feature_key) DO UPDATE SET
      id = EXCLUDED.id,
      is_enabled = EXCLUDED.is_enabled,
      limit_value = EXCLUDED.limit_value,
      unit = EXCLUDED.unit,
      updated_at = EXCLUDED.updated_at
  `;

  await pool.query(sql, [
    id,
    merchantId,
    featureKey,
    isEnabled,
    limitValue,
    unit,
    updatedAt,
  ]);
}

async function upsertFeatureFlag(
  merchantId: string,
  payload: Record<string, unknown>,
  entityId: string,
): Promise<void> {
  const flagKey =
    pickString(payload, 'flag_key') ?? pickString(payload, 'flagKey');
  if (!flagKey) {
    throw new Error('Missing flag key');
  }

  const id = pickString(payload, 'id') ?? entityId;
  const isEnabled =
    pickBoolean(payload, 'is_enabled') ??
    pickBoolean(payload, 'isEnabled') ??
    true;
  const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
  const payloadValue =
    payload['payload'] && typeof payload['payload'] === 'object'
      ? payload['payload']
      : null;

  const sql = `
    INSERT INTO feature_flags (
      id,
      merchant_id,
      flag_key,
      is_enabled,
      payload,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6)
    ON CONFLICT (merchant_id, flag_key) DO UPDATE SET
      id = EXCLUDED.id,
      is_enabled = EXCLUDED.is_enabled,
      payload = EXCLUDED.payload,
      updated_at = EXCLUDED.updated_at
  `;

  await pool.query(sql, [
    id,
    merchantId,
    flagKey,
    isEnabled,
    payloadValue,
    updatedAt,
  ]);
}

async function upsertRemoteConfig(
  merchantId: string,
  payload: Record<string, unknown>,
  entityId: string,
): Promise<void> {
  const configKey =
    pickString(payload, 'config_key') ?? pickString(payload, 'configKey');
  if (!configKey) {
    throw new Error('Missing config key');
  }

  const id = pickString(payload, 'id') ?? entityId;
  const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
  const payloadValue =
    payload['payload'] && typeof payload['payload'] === 'object'
      ? payload['payload']
      : null;

  const sql = `
    INSERT INTO remote_config (
      id,
      merchant_id,
      config_key,
      payload,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5)
    ON CONFLICT (merchant_id, config_key) DO UPDATE SET
      id = EXCLUDED.id,
      payload = EXCLUDED.payload,
      updated_at = EXCLUDED.updated_at
  `;

  await pool.query(sql, [id, merchantId, configKey, payloadValue, updatedAt]);
}

async function insertUsageEvent(
  merchantId: string,
  payload: Record<string, unknown>,
  entityId: string,
): Promise<void> {
  const metricKey =
    pickString(payload, 'metric_key') ?? pickString(payload, 'metricKey');
  if (!metricKey) {
    throw new Error('Missing metric key');
  }

  const quantity = pickNumber(payload, 'quantity') ?? 1;
  const occurredAt =
    pickNumber(payload, 'occurred_at') ?? pickNumber(payload, 'occurredAt') ??
    Date.now();
  const source = pickString(payload, 'source');
  const metadata =
    payload['metadata'] && typeof payload['metadata'] === 'object'
      ? payload['metadata']
      : null;

  const window = monthlyWindow(occurredAt);
  const balanceId = `${merchantId}_${metricKey}_${window.start}`;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const insertEventSql = `
      INSERT INTO usage_events (
        id,
        merchant_id,
        metric_key,
        quantity,
        occurred_at,
        source,
        metadata,
        created_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
      ON CONFLICT (id) DO NOTHING
      RETURNING id
    `;

    const insertEventResult = await client.query(insertEventSql, [
      entityId,
      merchantId,
      metricKey,
      quantity,
      occurredAt,
      source,
      metadata,
      Date.now(),
    ]);

    if (insertEventResult.rowCount === 0) {
      await client.query('ROLLBACK');
      return;
    }

    const upsertBalanceSql = `
      INSERT INTO usage_balances (
        id,
        merchant_id,
        metric_key,
        window_start,
        window_end,
        used,
        limit_value,
        soft_limit,
        updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      ON CONFLICT (merchant_id, metric_key, window_start, window_end)
      DO UPDATE SET
        used = usage_balances.used + EXCLUDED.used,
        limit_value = COALESCE(EXCLUDED.limit_value, usage_balances.limit_value),
        soft_limit = COALESCE(EXCLUDED.soft_limit, usage_balances.soft_limit),
        updated_at = EXCLUDED.updated_at
    `;

    await client.query(upsertBalanceSql, [
      balanceId,
      merchantId,
      metricKey,
      window.start,
      window.end,
      quantity,
      null,
      true,
      Date.now(),
    ]);

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function deleteById(
  table: string,
  entityId: string,
  merchantId: string,
): Promise<void> {
  const sql = `DELETE FROM ${table} WHERE id = $1 AND merchant_id = $2`;
  await pool.query(sql, [entityId, merchantId]);
}

function monthlyWindow(occurredAtMs: number): { start: number; end: number } {
  const date = new Date(occurredAtMs);
  const start = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1, 0, 0, 0);
  const next = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1, 0, 0, 0);
  const end = next - 1;
  return { start, end };
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export const usageBackfillDaily = onSchedule(
  { schedule: 'every day 02:30', timeZone: 'UTC' },
  async () => {
    const lookbackDays = parseInt(process.env.AGGREGATION_LOOKBACK_DAYS ?? '7', 10);
    const metrics = parseMetrics(process.env.AGGREGATION_METRICS);
    await aggregateUsageEvents(Date.now(), lookbackDays, metrics);
  },
);

export const usageReconcileWeekly = onSchedule(
  { schedule: 'every monday 03:15', timeZone: 'UTC' },
  async () => {
    const monthsBack = parseInt(process.env.RECONCILE_MONTHS_BACK ?? '2', 10);
    const metrics = parseMetrics(process.env.AGGREGATION_METRICS);
    await reconcileUsageBalances(Date.now(), monthsBack, metrics);
  },
);

function parseMetrics(raw: string | undefined): string[] {
  if (!raw || !raw.trim()) return ['whatsapp_messages'];
  return raw
    .split(',')
    .map((metric) => metric.trim())
    .filter((metric) => metric.length > 0);
}

async function aggregateUsageEvents(
  nowMs: number,
  lookbackDays: number,
  metrics: string[],
): Promise<void> {
  const cutoffMs = nowMs - Math.max(1, lookbackDays) * 24 * 60 * 60 * 1000;
  const sql = `
    WITH buckets AS (
      SELECT
        merchant_id,
        metric_key,
        (EXTRACT(EPOCH FROM date_trunc('month', to_timestamp(occurred_at / 1000))) * 1000)::bigint AS window_start,
        (EXTRACT(EPOCH FROM (date_trunc('month', to_timestamp(occurred_at / 1000)) + interval '1 month')) * 1000 - 1)::bigint AS window_end,
        SUM(quantity)::int AS used
      FROM usage_events
      WHERE occurred_at >= $1
        AND metric_key = ANY($2)
      GROUP BY merchant_id, metric_key, window_start, window_end
    )
    INSERT INTO usage_balances (
      id,
      merchant_id,
      metric_key,
      window_start,
      window_end,
      used,
      limit_value,
      soft_limit,
      updated_at
    )
    SELECT
      merchant_id || '_' || metric_key || '_' || window_start AS id,
      merchant_id,
      metric_key,
      window_start,
      window_end,
      used,
      NULL,
      true,
      $3
    FROM buckets
    ON CONFLICT (merchant_id, metric_key, window_start, window_end)
    DO UPDATE SET
      used = EXCLUDED.used,
      limit_value = COALESCE(usage_balances.limit_value, EXCLUDED.limit_value),
      soft_limit = COALESCE(usage_balances.soft_limit, EXCLUDED.soft_limit),
      updated_at = EXCLUDED.updated_at
  `;

  await pool.query(sql, [cutoffMs, metrics, nowMs]);
}

async function reconcileUsageBalances(
  nowMs: number,
  monthsBack: number,
  metrics: string[],
): Promise<void> {
  const lookbackMonths = Math.max(1, monthsBack);
  const startDate = new Date(nowMs);
  startDate.setUTCDate(1);
  startDate.setUTCMonth(startDate.getUTCMonth() - lookbackMonths);
  const cutoffMs = startDate.getTime();

  const sql = `
    WITH buckets AS (
      SELECT
        merchant_id,
        metric_key,
        (EXTRACT(EPOCH FROM date_trunc('month', to_timestamp(occurred_at / 1000))) * 1000)::bigint AS window_start,
        (EXTRACT(EPOCH FROM (date_trunc('month', to_timestamp(occurred_at / 1000)) + interval '1 month')) * 1000 - 1)::bigint AS window_end,
        SUM(quantity)::int AS used
      FROM usage_events
      WHERE occurred_at >= $1
        AND metric_key = ANY($2)
      GROUP BY merchant_id, metric_key, window_start, window_end
    )
    INSERT INTO usage_balances (
      id,
      merchant_id,
      metric_key,
      window_start,
      window_end,
      used,
      limit_value,
      soft_limit,
      updated_at
    )
    SELECT
      merchant_id || '_' || metric_key || '_' || window_start AS id,
      merchant_id,
      metric_key,
      window_start,
      window_end,
      used,
      NULL,
      true,
      $3
    FROM buckets
    ON CONFLICT (merchant_id, metric_key, window_start, window_end)
    DO UPDATE SET
      used = EXCLUDED.used,
      limit_value = COALESCE(usage_balances.limit_value, EXCLUDED.limit_value),
      soft_limit = COALESCE(usage_balances.soft_limit, EXCLUDED.soft_limit),
      updated_at = EXCLUDED.updated_at
  `;

  await pool.query(sql, [cutoffMs, metrics, nowMs]);
}
