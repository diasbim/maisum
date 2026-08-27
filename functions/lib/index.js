"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.usageReconcileWeekly = exports.usageBackfillDaily = exports.retentionInactivityScanDaily = exports.retentionDomainEventPostgresProjection = exports.loyaltyLedgerSaleOnSaleWrite = exports.customerCoreCanonicalLinkOnCustomerWrite = exports.api = void 0;
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const express_1 = __importDefault(require("express"));
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const pg_1 = require("pg");
const customer_account_binding_js_1 = require("./customer_account_binding.js");
const customer_feature_flags_js_1 = require("./customer_feature_flags.js");
const customer_push_tokens_js_1 = require("./customer_push_tokens.js");
const customer_qr_js_1 = require("./customer_qr.js");
const customer_request_auth_js_1 = require("./customer_request_auth.js");
const recovery_task_creation_js_1 = require("./recovery_task_creation.js");
admin.initializeApp();
const pool = new pg_1.Pool({
    connectionString: process.env.PG_CONNECTION_STRING,
    ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
    max: 10,
    idleTimeoutMillis: 30000,
});
const ENTITY_CONFIG = {
    customer: {
        table: 'customers',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    merchant_item: {
        table: 'merchant_items',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    sale: {
        table: 'sales',
        orderField: 'created_at',
        idField: 'id',
        selectSql: '*',
    },
    sale_item: {
        table: 'sale_items',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    reward: {
        table: 'rewards',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    redemption: {
        table: 'redemptions',
        orderField: 'redeemed_at',
        idField: 'id',
        selectSql: '*',
    },
    appointment: {
        table: 'appointments',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    retention_metric: {
        table: 'retention_metrics',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    customer_risk_score: {
        table: 'customer_risk_scores',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    recovery_task: {
        table: 'recovery_tasks',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    recovery_action: {
        table: 'recovery_actions',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    visit_report: {
        table: 'visit_reports',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    survey: {
        table: 'surveys',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    survey_question: {
        table: 'survey_questions',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    survey_response: {
        table: 'survey_responses',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
    survey_response_answer: {
        table: 'survey_response_answers',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
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
    app_user: {
        table: 'app_users',
        orderField: 'updated_at',
        idField: 'id',
        selectSql: '*',
    },
};
const OWNER_ONLY_SYNC_ENTITIES = new Set([
    'subscription_state',
    'entitlement',
    'feature_flag',
    'remote_config',
    'app_user',
]);
const CUSTOMER_IDENTITY_COLLECTION = 'customer_identities';
const CUSTOMER_ACCOUNT_COLLECTION = 'customer_accounts';
const CUSTOMER_IDENTITY_ACCOUNT_LINK_COLLECTION = 'customer_identity_account_links';
const CUSTOMER_ANALYTICS_EVENT_COLLECTION = 'customer_analytics_events';
const CUSTOMER_PUSH_TOKEN_COLLECTION = 'customer_push_tokens';
const BUSINESS_CUSTOMER_LINK_COLLECTION = 'business_customer_identity_links';
const CANONICAL_IDENTITY_BUSINESS_LINK_COLLECTION = 'canonical_identity_business_links';
const LOYALTY_LEDGER_COLLECTION = 'loyalty_ledger';
const DOMAIN_EVENT_COLLECTION = 'domain_events';
const RETENTION_POLICY_COLLECTION = 'retention_policies';
const CUSTOMER_TRANSITION_COLLECTION = 'customer_transitions';
const CUSTOMER_RECOMMENDATION_COLLECTION = 'customer_recommendations';
const RETENTION_POLICY_SCHEMA_VERSION = 1;
const CLASSIFICATION_SCHEMA_VERSION = 1;
const DOMAIN_EVENT_SCHEMA_VERSION = 1;
const DEFAULT_RETENTION_SCAN_LIMIT = 100;
const MAX_LEDGER_ENTRIES_PER_CUSTOMER = 5000;
const LOYALTY_PROJECTION_VERSION = 2;
const DEFAULT_LOYALTY_POINTS_PER_MZN = 100;
const DEFAULT_LOYALTY_CONFIG_VERSION = 1;
const CUSTOMER_CORE_SECRET_ENV = 'CUSTOMER_IDENTITY_HMAC_SECRET';
const customerIdentityHmacSecret = (0, params_1.defineSecret)(CUSTOMER_CORE_SECRET_ENV);
const CUSTOMER_QR_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_CUSTOMER_ACTIVITY_ENTRIES = 100;
const MOZAMBIQUE_PHONE_PREFIXES = new Set(['82', '83', '84', '85', '86', '87']);
const CUSTOMER_SERVER_OWNED_FIELDS = [
    'canonical_customer_id',
    'canonical_lookup_key',
    'canonical_phone_e164',
    'canonical_phone_last4',
    'canonical_linked_at',
    'canonical_identity_version',
    'canonical_link_status',
    'canonical_link_error_code',
    'canonical_link_error_message',
    'canonical_link_error_at',
    'account_state',
    'relationship_status',
    'lifecycle_stage',
    'retention_status',
    'first_visit_at',
    'last_visit_at',
    'total_visits',
    'total_spent',
    'average_spend',
    'average_visit_interval_days',
    'schema_version',
    'confirmed_points',
    'loyalty_projection_version',
    'loyalty_projection_status',
    'loyalty_backfill_required',
    'loyalty_last_reconciled_at',
    'loyalty_last_ledger_entry_at',
    'classification_schema_version',
    'classification_policy_version',
    'classification_explanation',
    'lifecycle_reasons',
    'retention_reasons',
    'classification_updated_at',
    'classification_last_activity_at',
    'pre_return_active_relationship',
];
const SALE_SERVER_OWNED_FIELDS = [
    'confirmation_status',
    'confirmed_points',
    'confirmed_at',
    'confirmation_error_code',
    'loyalty_policy_version',
    'confirmed_points_awarded',
    'loyalty_ledger_entry_id',
    'loyalty_points_per_mzn',
    'loyalty_config_version',
    'loyalty_status',
    'loyalty_error_code',
    'loyalty_error_message',
    'loyalty_error_at',
    'loyalty_processed_at',
];
const app = (0, express_1.default)();
app.use(express_1.default.json({ limit: '1mb' }));
app.use(async (req, res, next) => {
    const allowDev = process.env.ALLOW_DEV_AUTH === 'true';
    const authHeader = req.headers.authorization;
    if ((!authHeader || !authHeader.startsWith('Bearer ')) &&
        isAdminPath(req) &&
        hasValidAdminApiKey(req)) {
        const authedReq = req;
        authedReq.merchantId = '';
        authedReq.appUserId = 'admin-key';
        authedReq.appUserRole = 'ADMIN';
        return next();
    }
    if ((!authHeader || !authHeader.startsWith('Bearer ')) && allowDev) {
        const merchantHeader = req.headers['x-merchant-id'];
        if (isNonEmptyString(merchantHeader)) {
            const authedReq = req;
            authedReq.merchantId = merchantHeader.trim();
            authedReq.appUserId = 'dev-user';
            authedReq.appUserRole = 'OWNER';
            return next();
        }
    }
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
    }
    const token = authHeader.replace('Bearer ', '').trim();
    try {
        const decoded = await admin.auth().verifyIdToken(token);
        const adminAccess = isAdminPath(req) && hasAdminClaims(decoded);
        const requestScope = (0, customer_request_auth_js_1.resolveAuthenticatedRequestScope)({
            path: req.path,
            resolvedMerchantId: resolveMerchantId(decoded),
            hasAdminAccess: adminAccess,
            supportsBodyMerchantScope: supportsBodyMerchantScope(req),
        });
        if (!requestScope.hasRequiredScope) {
            return res
                .status(403)
                .json({ success: false, message: 'Missing merchant scope' });
        }
        const authedReq = req;
        authedReq.merchantId = requestScope.merchantId;
        authedReq.appUserId = resolveAppUserId(decoded);
        authedReq.appUserRole = requestScope.actor === 'CUSTOMER'
            ? 'CUSTOMER'
            : resolveAppUserRole(decoded);
        authedReq.auth = decoded;
        return next();
    }
    catch (error) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
    }
});
const adminRouter = express_1.default.Router();
adminRouter.use((req, res, next) => {
    if (!isAdminRequest(req)) {
        return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    return next();
});
adminRouter.get('/merchants', async (req, res) => {
    const limit = clampLimit(req.query.limit, 50, 100);
    const offset = Math.max(0, Math.floor(parseNumber(req.query.offset) ?? 0));
    const search = typeof req.query.search === 'string'
        ? req.query.search.trim()
        : '';
    const params = [];
    const where = [];
    if (search.length > 0) {
        params.push(`%${search}%`);
        where.push(`(
      m.id ILIKE $${params.length}
      OR m.name ILIKE $${params.length}
      OR m.phone ILIKE $${params.length}
    )`);
    }
    const whereSql = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
    params.push(limit);
    const limitParam = params.length;
    params.push(offset);
    const offsetParam = params.length;
    const sql = `
    SELECT
      m.id,
      m.name,
      m.phone,
      m.created_at,
      m.updated_at,
      ss.plan_code,
      ss.plan_name,
      ss.status AS subscription_status,
      COUNT(DISTINCT au.id)::int AS staff_count,
      COUNT(DISTINCT au.id) FILTER (WHERE au.status = 'ACTIVE')::int AS active_staff_count,
      COUNT(DISTINCT ub.id)::int AS usage_balance_count,
      MAX(GREATEST(
        m.updated_at,
        COALESCE(ss.updated_at, 0),
        COALESCE(au.updated_at, 0),
        COALESCE(ub.updated_at, 0)
      )) AS last_operational_update_at
    FROM merchants m
    LEFT JOIN subscription_state ss ON ss.merchant_id = m.id
    LEFT JOIN app_users au ON au.merchant_id = m.id
    LEFT JOIN usage_balances ub ON ub.merchant_id = m.id
    ${whereSql}
    GROUP BY
      m.id,
      m.name,
      m.phone,
      m.created_at,
      m.updated_at,
      ss.plan_code,
      ss.plan_name,
      ss.status
    ORDER BY m.updated_at DESC, m.id ASC
    LIMIT $${limitParam} OFFSET $${offsetParam}
  `;
    try {
        const result = await pool.query(sql, params);
        return res.json({
            success: true,
            data: result.rows,
            paging: {
                limit,
                offset,
                has_more: result.rows.length === limit,
            },
        });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
adminRouter.get('/audit-events', async (req, res) => {
    const limit = clampLimit(req.query.limit, 50, 100);
    const offset = Math.max(0, Math.floor(parseNumber(req.query.offset) ?? 0));
    const targetType = pickQueryString(req.query.target_type) ??
        pickQueryString(req.query.targetType);
    const targetId = pickQueryString(req.query.target_id) ??
        pickQueryString(req.query.targetId);
    const merchantId = pickQueryString(req.query.merchant_id) ??
        pickQueryString(req.query.merchantId);
    const params = [];
    const where = [];
    if (targetType) {
        params.push(targetType);
        where.push(`target_type = $${params.length}`);
    }
    if (targetId) {
        params.push(targetId);
        where.push(`target_id = $${params.length}`);
    }
    if (merchantId) {
        params.push(merchantId);
        where.push(`merchant_id = $${params.length}`);
    }
    const whereSql = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
    params.push(limit);
    const limitParam = params.length;
    params.push(offset);
    const offsetParam = params.length;
    const sql = `
    SELECT
      id,
      actor_app_user_id,
      actor_firebase_uid,
      actor_role,
      action,
      target_type,
      target_id,
      merchant_id,
      details,
      created_at
    FROM admin_audit_events
    ${whereSql}
    ORDER BY created_at DESC, id DESC
    LIMIT $${limitParam} OFFSET $${offsetParam}
  `;
    try {
        const result = await pool.query(sql, params);
        return res.json({
            success: true,
            data: result.rows,
            paging: {
                limit,
                offset,
                has_more: result.rows.length === limit,
            },
        });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
adminRouter.get('/operations/summary', async (_req, res) => {
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const sql = `
    SELECT
      (SELECT COUNT(*)::int FROM merchants) AS merchant_count,
      (SELECT COUNT(*)::int FROM subscription_state WHERE status = 'ACTIVE') AS active_subscription_count,
      (SELECT COUNT(*)::int FROM subscription_state WHERE status = 'TRIAL') AS trial_subscription_count,
      (SELECT COUNT(*)::int FROM subscription_state WHERE status IN ('PAST_DUE', 'CANCELLED', 'CANCELED')) AS attention_subscription_count,
      (SELECT COUNT(*)::int FROM app_users WHERE status = 'ACTIVE') AS active_staff_count,
      (SELECT COUNT(*)::int FROM usage_events WHERE created_at >= $1) AS usage_events_24h,
      (SELECT COUNT(*)::int FROM recovery_tasks WHERE LOWER(status) NOT IN ('done', 'completed', 'cancelled', 'canceled', 'superseded')) AS open_recovery_task_count,
      (SELECT COUNT(*)::int FROM visit_reports WHERE created_at >= $1) AS visit_reports_24h,
      (SELECT COUNT(*)::int FROM survey_responses WHERE created_at >= $1) AS survey_responses_24h,
      (SELECT COUNT(*)::int FROM admin_audit_events WHERE created_at >= $1) AS admin_audit_events_24h,
      (SELECT MAX(created_at) FROM admin_audit_events) AS last_admin_audit_at,
      (SELECT MAX(created_at) FROM usage_events) AS last_usage_event_at
  `;
    try {
        const result = await pool.query(sql, [dayAgo]);
        return res.json({ success: true, data: result.rows[0] ?? {} });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
adminRouter.get('/merchants/:merchantId', async (req, res) => {
    const merchantId = isNonEmptyString(req.params.merchantId)
        ? req.params.merchantId.trim()
        : null;
    if (!merchantId) {
        return res
            .status(400)
            .json({ success: false, message: 'Missing merchant id' });
    }
    const sql = `
    SELECT
      m.id,
      m.name,
      m.phone,
      m.created_at,
      m.updated_at,
      ss.plan_code,
      ss.plan_name,
      ss.plan_version,
      ss.pricing_version,
      ss.status AS subscription_status,
      ss.trial_ends_at,
      ss.grace_ends_at,
      ss.period_start,
      ss.period_end,
      ss.updated_at AS subscription_updated_at,
      (SELECT COUNT(*)::int FROM app_users au WHERE au.merchant_id = m.id) AS staff_count,
      (SELECT COUNT(*)::int FROM app_users au WHERE au.merchant_id = m.id AND au.status = 'ACTIVE') AS active_staff_count,
      (SELECT MAX(au.last_login_at) FROM app_users au WHERE au.merchant_id = m.id) AS last_staff_login_at,
      (SELECT COUNT(*)::int FROM usage_balances ub WHERE ub.merchant_id = m.id) AS usage_balance_count,
      (SELECT COALESCE(SUM(ub.used), 0)::int FROM usage_balances ub WHERE ub.merchant_id = m.id) AS usage_used_total,
      (SELECT MAX(ub.updated_at) FROM usage_balances ub WHERE ub.merchant_id = m.id) AS usage_updated_at,
      (SELECT COUNT(*)::int FROM usage_events ue WHERE ue.merchant_id = m.id) AS usage_event_count,
      (SELECT MAX(ue.created_at) FROM usage_events ue WHERE ue.merchant_id = m.id) AS last_usage_event_at,
      (SELECT COUNT(*)::int FROM entitlements e WHERE e.merchant_id = m.id) AS entitlement_count,
      (SELECT COUNT(*)::int FROM feature_flags ff WHERE ff.merchant_id = m.id) AS feature_flag_count,
      (SELECT COUNT(*)::int FROM remote_config rc WHERE rc.merchant_id = m.id) AS remote_config_count,
      GREATEST(
        m.updated_at,
        COALESCE(ss.updated_at, 0),
        COALESCE((SELECT MAX(au.updated_at) FROM app_users au WHERE au.merchant_id = m.id), 0),
        COALESCE((SELECT MAX(ub.updated_at) FROM usage_balances ub WHERE ub.merchant_id = m.id), 0)
      ) AS last_operational_update_at
    FROM merchants m
    LEFT JOIN subscription_state ss ON ss.merchant_id = m.id
    WHERE m.id = $1
  `;
    try {
        const result = await pool.query(sql, [merchantId]);
        if (result.rowCount === 0) {
            return res
                .status(404)
                .json({ success: false, message: 'Merchant not found' });
        }
        return res.json({ success: true, data: result.rows[0] });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
adminRouter.get('/plans', async (_req, res) => {
    const sql = `
    SELECT
      p.plan_code,
      p.version,
      p.name,
      p.is_active,
      p.created_at,
      p.updated_at,
      COALESCE(
        jsonb_agg(
          DISTINCT jsonb_build_object(
            'pricing_version', pp.pricing_version,
            'currency', pp.currency,
            'amount', pp.amount,
            'billing_period', pp.billing_period,
            'is_active', pp.is_active,
            'created_at', pp.created_at,
            'updated_at', pp.updated_at
          )
        ) FILTER (WHERE pp.plan_code IS NOT NULL),
        '[]'::jsonb
      ) AS prices,
      COALESCE(
        jsonb_agg(
          DISTINCT jsonb_build_object(
            'feature_key', pf.feature_key,
            'is_enabled', pf.is_enabled,
            'limit_value', pf.limit_value,
            'unit', pf.unit,
            'updated_at', pf.updated_at
          )
        ) FILTER (WHERE pf.plan_code IS NOT NULL),
        '[]'::jsonb
      ) AS features
    FROM plans p
    LEFT JOIN plan_prices pp ON pp.plan_code = p.plan_code
    LEFT JOIN plan_features pf
      ON pf.plan_code = p.plan_code AND pf.plan_version = p.version
    GROUP BY
      p.plan_code,
      p.version,
      p.name,
      p.is_active,
      p.created_at,
      p.updated_at
    ORDER BY p.is_active DESC, p.plan_code ASC, p.version DESC
  `;
    try {
        const result = await pool.query(sql);
        return res.json({ success: true, data: result.rows });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
adminRouter.post('/merchants/:merchantId/entitlements', async (req, res) => {
    const merchantId = isNonEmptyString(req.params.merchantId)
        ? req.params.merchantId.trim()
        : null;
    const payload = req.body ?? {};
    const featureKey = pickString(payload, 'feature_key') ?? pickString(payload, 'featureKey');
    const isEnabled = pickBoolean(payload, 'is_enabled') ?? pickBoolean(payload, 'isEnabled');
    const limitValue = pickNumber(payload, 'limit_value') ?? pickNumber(payload, 'limitValue');
    const unit = pickString(payload, 'unit');
    if (!merchantId) {
        return res
            .status(400)
            .json({ success: false, message: 'Missing merchant id' });
    }
    if (!featureKey || isEnabled == null) {
        return res
            .status(400)
            .json({ success: false, message: 'Missing entitlement override data' });
    }
    const client = await pool.connect();
    const now = Date.now();
    const entitlementId = `${merchantId}_${featureKey}`;
    try {
        await client.query('BEGIN');
        const merchantResult = await client.query('SELECT id FROM merchants WHERE id = $1', [merchantId]);
        if (merchantResult.rowCount === 0) {
            await client.query('ROLLBACK');
            return res
                .status(404)
                .json({ success: false, message: 'Merchant not found' });
        }
        const beforeResult = await client.query(`
        SELECT id, feature_key, is_enabled, limit_value, unit, updated_at
        FROM entitlements
        WHERE merchant_id = $1 AND feature_key = $2
      `, [merchantId, featureKey]);
        const before = beforeResult.rows[0] ?? null;
        const upsertSql = `
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
      RETURNING id, feature_key, is_enabled, limit_value, unit, updated_at
    `;
        const upsertResult = await client.query(upsertSql, [
            entitlementId,
            merchantId,
            featureKey,
            isEnabled,
            limitValue,
            unit,
            now,
        ]);
        const after = upsertResult.rows[0] ?? null;
        await recordAdminAuditEvent(client, req, {
            action: 'entitlement.override',
            targetType: 'entitlement',
            targetId: entitlementId,
            merchantId,
            details: {
                feature_key: featureKey,
                before,
                after,
            },
        });
        await client.query('COMMIT');
        return res.json({ success: true, data: after });
    }
    catch (error) {
        await client.query('ROLLBACK');
        return res.status(500).json({ success: false, message: 'Server error' });
    }
    finally {
        client.release();
    }
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
            await client.query('UPDATE plans SET is_active = false, updated_at = $2 WHERE plan_code = $1', [planCode, now]);
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
        await recordAdminAuditEvent(client, req, {
            action: 'plan.upsert',
            targetType: 'plan',
            targetId: `${planCode}@${version}`,
            details: {
                plan_code: planCode,
                version,
                name,
                is_active: isActive,
            },
        });
        await client.query('COMMIT');
        return res.json({ success: true });
    }
    catch (error) {
        await client.query('ROLLBACK');
        return res.status(500).json({ success: false, message: 'Server error' });
    }
    finally {
        client.release();
    }
});
adminRouter.post('/prices', async (req, res) => {
    const payload = req.body ?? {};
    const planCode = pickString(payload, 'plan_code') ?? pickString(payload, 'planCode');
    const pricingVersion = pickNumber(payload, 'pricing_version') ?? pickNumber(payload, 'pricingVersion');
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
            await client.query('UPDATE plan_prices SET is_active = false, updated_at = $3 WHERE plan_code = $1 AND currency = $2', [planCode, currency, now]);
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
        await recordAdminAuditEvent(client, req, {
            action: 'price.upsert',
            targetType: 'plan_price',
            targetId: `${planCode}@${pricingVersion}:${currency}`,
            details: {
                plan_code: planCode,
                pricing_version: pricingVersion,
                currency,
                amount,
                billing_period: billingPeriod,
                is_active: isActive,
            },
        });
        await client.query('COMMIT');
        return res.json({ success: true });
    }
    catch (error) {
        await client.query('ROLLBACK');
        return res.status(500).json({ success: false, message: 'Server error' });
    }
    finally {
        client.release();
    }
});
adminRouter.post('/plans/:planCode/features', async (req, res) => {
    const planCode = isNonEmptyString(req.params.planCode)
        ? req.params.planCode.trim()
        : null;
    const payload = req.body ?? {};
    const planVersion = pickNumber(payload, 'plan_version') ?? pickNumber(payload, 'planVersion');
    const featureKey = pickString(payload, 'feature_key') ?? pickString(payload, 'featureKey');
    const isEnabled = pickBoolean(payload, 'is_enabled') ?? pickBoolean(payload, 'isEnabled');
    const limitValue = pickNumber(payload, 'limit_value') ?? pickNumber(payload, 'limitValue');
    const unit = pickString(payload, 'unit');
    if (!planCode || planVersion == null || !featureKey || isEnabled == null) {
        return res
            .status(400)
            .json({ success: false, message: 'Missing plan feature data' });
    }
    const now = Date.now();
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const planResult = await client.query('SELECT plan_code, version FROM plans WHERE plan_code = $1 AND version = $2', [planCode, planVersion]);
        if (planResult.rowCount === 0) {
            await client.query('ROLLBACK');
            return res
                .status(404)
                .json({ success: false, message: 'Plan version not found' });
        }
        const sql = `
      INSERT INTO plan_features (
        plan_code,
        plan_version,
        feature_key,
        is_enabled,
        limit_value,
        unit,
        updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT (plan_code, plan_version, feature_key) DO UPDATE SET
        is_enabled = EXCLUDED.is_enabled,
        limit_value = EXCLUDED.limit_value,
        unit = EXCLUDED.unit,
        updated_at = EXCLUDED.updated_at
      RETURNING feature_key, is_enabled, limit_value, unit, updated_at
    `;
        const result = await client.query(sql, [
            planCode,
            planVersion,
            featureKey,
            isEnabled,
            limitValue,
            unit,
            now,
        ]);
        await recordAdminAuditEvent(client, req, {
            action: 'plan_feature.upsert',
            targetType: 'plan_feature',
            targetId: `${planCode}@${planVersion}:${featureKey}`,
            details: {
                plan_code: planCode,
                plan_version: planVersion,
                feature_key: featureKey,
                is_enabled: isEnabled,
                limit_value: limitValue,
                unit,
            },
        });
        await client.query('COMMIT');
        return res.json({ success: true, data: result.rows[0] });
    }
    catch (error) {
        await client.query('ROLLBACK');
        return res.status(500).json({ success: false, message: 'Server error' });
    }
    finally {
        client.release();
    }
});
adminRouter.post('/customer-core/business-customers/backfill', async (req, res) => {
    try {
        const result = await handleCustomerCoreBackfillRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
adminRouter.post('/loyalty/ledger/backfill', async (req, res) => {
    try {
        const result = await handleLoyaltyLedgerBackfillRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
adminRouter.post('/loyalty/ledger/reconcile', async (req, res) => {
    try {
        const result = await handleLoyaltyLedgerReconcileRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
adminRouter.post('/retention/policies', async (req, res) => {
    try {
        const result = await handleRetentionPolicyUpsertRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
adminRouter.post('/retention/classifications/scan', async (req, res) => {
    try {
        const result = await handleRetentionClassificationScanRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.use('/admin', adminRouter);
app.get('/customer/session', async (req, res) => {
    try {
        const result = await handleCustomerSessionRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/home', async (req, res) => {
    try {
        const result = await handleCustomerHomeRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/businesses', async (req, res) => {
    try {
        const result = await handleCustomerBusinessesRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/businesses/:businessId', async (req, res) => {
    try {
        const result = await handleCustomerBusinessDetailRequest(req, req.params.businessId);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/rewards', async (req, res) => {
    try {
        const result = await handleCustomerRewardsRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/activity', async (req, res) => {
    try {
        const result = await handleCustomerActivityRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/profile', async (req, res) => {
    try {
        const result = await handleCustomerProfileRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.patch('/customer/preferences', async (req, res) => {
    try {
        const result = await handleCustomerPreferencesRequest(req, requireBodyObject(req.body));
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/notifications', async (req, res) => {
    try {
        const result = await handleCustomerNotificationsRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/deep-links', async (req, res) => {
    try {
        const result = await handleCustomerDeepLinksRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer/push-tokens', async (req, res) => {
    try {
        const result = await handleCustomerPushTokenRegistration(req, requireBodyObject(req.body));
        return res.status(201).json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer/push-tokens/remove', async (req, res) => {
    try {
        const result = await handleCustomerPushTokenRemoval(req, requireBodyObject(req.body));
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer/events', async (req, res) => {
    try {
        const result = await handleCustomerAnalyticsEventRequest(req, requireBodyObject(req.body));
        return res.status(202).json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/customer/qr', async (req, res) => {
    try {
        const result = await handleCustomerQrRequest(req);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer/redemptions', async (req, res) => {
    try {
        const result = await handleCustomerRedemptionRequest(req, requireBodyObject(req.body));
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/merchant/customer-qr/resolve', async (req, res) => {
    try {
        const result = await handleMerchantCustomerQrResolveRequest(req, requireBodyObject(req.body));
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer-core/identities/lookup', async (req, res) => {
    try {
        const payload = requireBodyObject(req.body);
        const merchantId = await resolveCustomerCoreMerchantId(req, payload);
        const rawPhone = requirePayloadString(payload, 'phone');
        const phoneE164 = normalizeMozambiquePhoneToE164(rawPhone);
        const identity = await findCanonicalCustomerIdentity(phoneE164);
        return res.json({
            success: true,
            found: identity != null,
            data: identity
                ? serializeCanonicalCustomerIdentity(identity)
                : {
                    merchant_id: merchantId,
                    canonical_customer_id: buildCanonicalCustomerId(phoneE164),
                    phone_e164: phoneE164,
                    phone_last4: last4(phoneE164),
                },
        });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer-core/identities', async (req, res) => {
    try {
        const payload = requireBodyObject(req.body);
        const merchantId = await resolveCustomerCoreMerchantId(req, payload);
        const rawPhone = requirePayloadString(payload, 'phone');
        const phoneE164 = normalizeMozambiquePhoneToE164(rawPhone);
        const identity = await findOrCreateCanonicalCustomerIdentity(merchantId, phoneE164);
        return res.json({
            success: true,
            created: identity.created,
            data: {
                merchant_id: merchantId,
                ...serializeCanonicalCustomerIdentity(identity),
            },
        });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer-core/business-customers/link', async (req, res) => {
    try {
        const payload = requireBodyObject(req.body);
        const merchantId = await resolveCustomerCoreMerchantId(req, payload);
        const result = await handleBusinessCustomerLinkRequest(req, merchantId, payload);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/customer-core/business-customers/backfill', async (req, res) => {
    try {
        const result = await handleCustomerCoreBackfillRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/loyalty/ledger/backfill', async (req, res) => {
    try {
        const result = await handleLoyaltyLedgerBackfillRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/loyalty/ledger/reconcile', async (req, res) => {
    try {
        const result = await handleLoyaltyLedgerReconcileRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/loyalty/redemptions', async (req, res) => {
    try {
        const payload = requireBodyObject(req.body);
        const result = await handleAssistedLoyaltyRedemptionRequest(req, payload);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/retention/policies', async (req, res) => {
    try {
        const result = await handleRetentionPolicyUpsertRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.post('/retention/classifications/scan', async (req, res) => {
    try {
        const result = await handleRetentionClassificationScanRequest(req, req.body);
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/sync/:entityType', async (req, res) => {
    const { entityType } = req.params;
    const config = ENTITY_CONFIG[entityType];
    if (!config) {
        return res.status(404).json({ success: false, message: 'Unknown entity' });
    }
    const merchantId = req.merchantId;
    const sql = `
    SELECT ${config.selectSql}
    FROM ${config.table}
    WHERE merchant_id = $1
    ORDER BY ${config.orderField} ASC, ${config.idField} ASC
  `;
    try {
        const result = await pool.query(sql, [merchantId]);
        return res.json({ success: true, data: result.rows });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.get('/sync/:entityType/changes', async (req, res) => {
    const { entityType } = req.params;
    const config = ENTITY_CONFIG[entityType];
    if (!config) {
        return res.status(404).json({ success: false, message: 'Unknown entity' });
    }
    const merchantId = req.merchantId;
    const lastValue = parseNumber(req.query.last_value);
    const lastDocId = typeof req.query.last_doc_id === 'string' ? req.query.last_doc_id : null;
    const limit = clampLimit(req.query.limit, 200, 500);
    const params = [merchantId];
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
    }
    catch (error) {
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
    const merchantId = req.merchantId;
    const payloadMerchantId = pickString(payload, 'merchant_id') ?? pickString(payload, 'merchantId');
    if (payloadMerchantId && payloadMerchantId !== merchantId) {
        return res.status(403).json({ success: false, message: 'Tenant mismatch' });
    }
    const payloadId = pickString(payload, 'id');
    if (payloadId && payloadId !== entityId) {
        return res.status(400).json({ success: false, message: 'ID mismatch' });
    }
    if (OWNER_ONLY_SYNC_ENTITIES.has(entityType) &&
        !isOwnerOrAdminRequest(req)) {
        return res.status(403).json({ success: false, message: 'Owner access required' });
    }
    try {
        switch (entityType) {
            case 'customer':
                if (operation === 'delete') {
                    await deleteById('customers', entityId, merchantId);
                }
                else {
                    await upsertCustomer(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'merchant_item':
                if (operation === 'delete') {
                    await deleteById('merchant_items', entityId, merchantId);
                }
                else {
                    await upsertMerchantItem(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'sale':
                if (operation === 'delete') {
                    await deleteById('sales', entityId, merchantId);
                }
                else {
                    await upsertSale(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'sale_item':
                if (operation === 'delete') {
                    await deleteById('sale_items', entityId, merchantId);
                }
                else {
                    await upsertSaleItem(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'reward':
                if (operation === 'delete') {
                    await deleteById('rewards', entityId, merchantId);
                }
                else {
                    await upsertReward(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'redemption':
                if (operation === 'delete') {
                    await deleteById('redemptions', entityId, merchantId);
                }
                else {
                    await upsertRedemption(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'appointment':
                if (operation === 'delete') {
                    await deleteById('appointments', entityId, merchantId);
                }
                else {
                    await upsertAppointment(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'retention_metric':
                if (operation === 'delete') {
                    await deleteById('retention_metrics', entityId, merchantId);
                }
                else {
                    await upsertRetentionMetric(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'customer_risk_score':
                if (operation === 'delete') {
                    await deleteById('customer_risk_scores', entityId, merchantId);
                }
                else {
                    await upsertCustomerRiskScore(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'recovery_task':
                if (operation === 'delete') {
                    await deleteById('recovery_tasks', entityId, merchantId);
                    return res.json({ success: true });
                }
                if ((pickString(payload, 'status') ?? 'open').toLowerCase() === 'open') {
                    const result = await (0, recovery_task_creation_js_1.createOrGetOpenRecoveryTask)(pool, {
                        id: entityId,
                        merchantId,
                        customerId: pickString(payload, 'customer_id') ??
                            pickString(payload, 'customerId') ??
                            '',
                        priority: pickString(payload, 'priority') ?? 'medium',
                        dueAt: pickNumber(payload, 'due_at') ?? pickNumber(payload, 'dueAt'),
                        notes: pickString(payload, 'notes'),
                        now: pickNumber(payload, 'updated_at') ?? Date.now(),
                        createdAt: pickNumber(payload, 'created_at') ??
                            pickNumber(payload, 'createdAt') ??
                            undefined,
                        actorAppUserId: pickString(payload, 'updated_by_app_user_id') ??
                            pickString(payload, 'updatedByAppUserId') ??
                            null,
                    });
                    return res.json({
                        success: true,
                        data: {
                            outcome: result.outcome,
                            canonical_entity: result.task,
                        },
                    });
                }
                else {
                    await upsertRecoveryTask(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'recovery_action':
                if (operation === 'delete') {
                    await deleteById('recovery_actions', entityId, merchantId);
                }
                else {
                    await upsertRecoveryAction(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'visit_report':
                if (operation === 'delete') {
                    await deleteById('visit_reports', entityId, merchantId);
                }
                else {
                    await upsertVisitReport(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'survey':
                if (operation === 'delete') {
                    await deleteById('surveys', entityId, merchantId);
                }
                else {
                    await upsertSurvey(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'survey_question':
                if (operation === 'delete') {
                    await deleteById('survey_questions', entityId, merchantId);
                }
                else {
                    await upsertSurveyQuestion(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'survey_response':
                if (operation === 'delete') {
                    await deleteById('survey_responses', entityId, merchantId);
                }
                else {
                    await upsertSurveyResponse(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'survey_response_answer':
                if (operation === 'delete') {
                    await deleteById('survey_response_answers', entityId, merchantId);
                }
                else {
                    await upsertSurveyResponseAnswer(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'subscription_state':
                await upsertSubscriptionState(merchantId, payload);
                return res.json({ success: true });
            case 'entitlement':
                if (operation === 'delete') {
                    await deleteById('entitlements', entityId, merchantId);
                }
                else {
                    await upsertEntitlement(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'feature_flag':
                if (operation === 'delete') {
                    await deleteById('feature_flags', entityId, merchantId);
                }
                else {
                    await upsertFeatureFlag(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            case 'remote_config':
                if (operation === 'delete') {
                    await deleteById('remote_config', entityId, merchantId);
                }
                else {
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
            case 'app_user':
                if (operation === 'delete') {
                    await deleteById('app_users', entityId, merchantId);
                }
                else {
                    await upsertAppUser(merchantId, payload, entityId);
                }
                return res.json({ success: true });
            default:
                return res.status(404).json({ success: false, message: 'Unknown entity' });
        }
    }
    catch (error) {
        console.error('Sync write failed', {
            entityType,
            entityId,
            operation,
            error,
        });
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.post('/notifications/queue', async (req, res) => {
    try {
        const body = requireBodyObject(req.body);
        const merchantId = await resolveCustomerCoreMerchantId(req, body);
        const notificationId = requirePayloadString(body, 'notification_id');
        const channel = requirePayloadString(body, 'channel').toLowerCase();
        const payloadRaw = body.payload;
        if (!payloadRaw || typeof payloadRaw !== 'object') {
            throw new CustomerCoreError(400, 'notification_payload_invalid', 'Notification payload must be an object.');
        }
        const payload = payloadRaw;
        const customerId = requirePayloadString(payload, 'customer_id');
        const scheduledAtRaw = maybePayloadString(body, 'scheduled_at', 'scheduledAt');
        const scheduledAt = scheduledAtRaw ? Date.parse(scheduledAtRaw) : Date.now();
        if (!Number.isFinite(scheduledAt)) {
            throw new CustomerCoreError(400, 'notification_schedule_invalid', 'scheduled_at must be a valid date.');
        }
        if (channel !== 'whatsapp') {
            throw new CustomerCoreError(400, 'notification_channel_unsupported', 'Only WhatsApp queueing is currently supported.');
        }
        const customerSnapshot = await businessCustomerRef(merchantId, customerId).get();
        if (!customerSnapshot.exists) {
            throw new CustomerCoreError(404, 'notification_customer_not_found', 'Business customer not found.', { merchant_id: merchantId, customer_id: customerId });
        }
        const customerData = snapshotDataRecord(customerSnapshot);
        if (maybePayloadString(customerData, 'whatsapp_consent_status')?.toUpperCase() !==
            'GRANTED') {
            throw new CustomerCoreError(409, 'notification_consent_required', 'WhatsApp consent is required before queueing this notification.', { merchant_id: merchantId, customer_id: customerId });
        }
        const customerPhone = requirePayloadString(customerData, 'phone');
        const normalizedPayload = {
            ...payload,
            customer_id: customerId,
            phone: normalizeMozambiquePhoneToE164(customerPhone),
        };
        const notificationRef = businessDocumentRef(merchantId)
            .collection('notification_queue')
            .doc(notificationId);
        const idempotentReplay = await admin.firestore().runTransaction(async (transaction) => {
            const existing = await transaction.get(notificationRef);
            if (existing.exists) {
                const existingData = snapshotDataRecord(existing);
                if (maybePayloadString(existingData, 'merchant_id') !== merchantId ||
                    maybePayloadString(existingData, 'customer_id') !== customerId) {
                    throw new CustomerCoreError(409, 'notification_idempotency_conflict', 'notification_id was already used for another customer.');
                }
                return true;
            }
            transaction.create(notificationRef, {
                id: notificationId,
                client_notification_id: notificationId,
                merchant_id: merchantId,
                customer_id: customerId,
                channel,
                payload: normalizedPayload,
                scheduled_at: scheduledAt,
                status: 'queued',
                created_at: Date.now(),
            });
            return false;
        });
        return res.json({
            success: true,
            notification_id: notificationId,
            idempotent_replay: idempotentReplay,
        });
    }
    catch (error) {
        return respondCustomerCoreError(res, error);
    }
});
app.get('/engage/dashboard', async (req, res) => {
    const merchantId = req.merchantId;
    const sql = `
    SELECT
      SUM(CASE WHEN crs.risk_level = 'green' THEN 1 ELSE 0 END) AS customers_active,
      SUM(CASE WHEN crs.risk_level IN ('yellow', 'orange', 'red') THEN 1 ELSE 0 END) AS customers_at_risk,
      SUM(CASE WHEN crs.risk_level = 'red' THEN 1 ELSE 0 END) AS critical_customers,
      SUM(CASE WHEN crs.risk_level IN ('orange', 'red') THEN COALESCE(rm.total_spent, 0) ELSE 0 END) AS revenue_at_risk,
      SUM(CASE WHEN COALESCE(rm.recovered, 0) = 1 THEN 1 ELSE 0 END) AS recovered_customers
    FROM customer_risk_scores crs
    LEFT JOIN retention_metrics rm
      ON rm.customer_id = crs.customer_id AND rm.merchant_id = crs.merchant_id
    WHERE crs.merchant_id = $1
  `;
    try {
        const result = await pool.query(sql, [merchantId]);
        return res.json({ success: true, data: result.rows[0] ?? {} });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.get('/engage/recovery-queue', async (req, res) => {
    const merchantId = req.merchantId;
    const limit = clampLimit(req.query.limit, 20, 100);
    const sql = `
    SELECT crs.customer_id,
           c.name AS customer_name,
           crs.days_since_visit,
           crs.risk_level,
           crs.priority,
           COALESCE(rm.total_spent, 0) AS total_spent,
           COALESCE(c.total_points, 0) AS total_points,
           rm.last_visit_at
    FROM customer_risk_scores crs
    INNER JOIN customers c
      ON c.id = crs.customer_id AND c.merchant_id = crs.merchant_id
    LEFT JOIN retention_metrics rm
      ON rm.customer_id = crs.customer_id AND rm.merchant_id = crs.merchant_id
    WHERE crs.merchant_id = $1
      AND crs.risk_level IN ('yellow', 'orange', 'red')
    ORDER BY COALESCE(rm.total_spent, 0) DESC,
             crs.priority DESC,
             COALESCE(c.total_points, 0) DESC
    LIMIT $2
  `;
    try {
        const result = await pool.query(sql, [merchantId, limit]);
        return res.json({ success: true, data: result.rows });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.post('/engage/task', async (req, res) => {
    const authedReq = req;
    const merchantId = authedReq.merchantId;
    const actorAppUserId = authedReq.appUserId ?? null;
    const payload = req.body ?? {};
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const priority = pickString(payload, 'priority') ?? 'medium';
    const dueAt = pickNumber(payload, 'due_at') ?? pickNumber(payload, 'dueAt');
    const notes = pickString(payload, 'notes');
    if (!customerId) {
        return res.status(400).json({ success: false, message: 'Missing customer_id' });
    }
    const now = Date.now();
    try {
        const result = await (0, recovery_task_creation_js_1.createOrGetOpenRecoveryTask)(pool, {
            id: pickString(payload, 'id') ?? undefined,
            merchantId,
            customerId,
            priority,
            dueAt,
            notes,
            now,
            actorAppUserId,
        });
        return res.json({ success: true, data: result });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.post('/engage/task/complete', async (req, res) => {
    const authedReq = req;
    const merchantId = authedReq.merchantId;
    const actorAppUserId = authedReq.appUserId ?? null;
    const payload = req.body ?? {};
    const taskId = pickString(payload, 'task_id') ?? pickString(payload, 'taskId');
    if (!taskId) {
        return res.status(400).json({ success: false, message: 'Missing task_id' });
    }
    const sql = `
    UPDATE recovery_tasks
    SET status = 'completed',
      updated_at = $3,
      updated_by_app_user_id = $4
    WHERE id = $1 AND merchant_id = $2
    RETURNING *
  `;
    try {
        const now = Date.now();
        const result = await pool.query(sql, [taskId, merchantId, now, actorAppUserId]);
        return res.json({ success: true, data: result.rows[0] ?? null });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.post('/engage/action', async (req, res) => {
    const authedReq = req;
    const merchantId = authedReq.merchantId;
    const actorAppUserId = authedReq.appUserId ?? null;
    const payload = req.body ?? {};
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const actionType = pickString(payload, 'action_type') ?? pickString(payload, 'actionType');
    const taskId = pickString(payload, 'task_id') ?? pickString(payload, 'taskId');
    const details = payload['payload'] && typeof payload['payload'] === 'object'
        ? payload['payload']
        : null;
    if (!customerId || !actionType) {
        return res.status(400).json({ success: false, message: 'Missing action data' });
    }
    const id = pickString(payload, 'id') ?? (0, crypto_1.randomUUID)();
    const now = Date.now();
    const sql = `
    WITH inserted AS (
      INSERT INTO recovery_actions (
        id,
        merchant_id,
        customer_id,
        task_id,
        action_type,
        payload,
        created_at,
        updated_at,
        created_by_app_user_id,
        updated_by_app_user_id
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
      ON CONFLICT (id) DO NOTHING
      RETURNING *
    )
    SELECT * FROM inserted
    UNION ALL
    SELECT * FROM recovery_actions
    WHERE id = $1 AND merchant_id = $2
    LIMIT 1
  `;
    try {
        const result = await pool.query(sql, [
            id,
            merchantId,
            customerId,
            taskId,
            actionType,
            details,
            now,
            now,
            actorAppUserId,
            actorAppUserId,
        ]);
        if (!result.rows[0]) {
            return res.status(409).json({ success: false, message: 'Action ID already in use' });
        }
        return res.json({ success: true, data: result.rows[0] });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.post('/engage/visit-report', async (req, res) => {
    const authedReq = req;
    const merchantId = authedReq.merchantId;
    const actorAppUserId = authedReq.appUserId ?? null;
    const payload = req.body ?? {};
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const resultValue = pickString(payload, 'result');
    const taskId = pickString(payload, 'task_id') ?? pickString(payload, 'taskId');
    const notes = pickString(payload, 'notes');
    const visitedAt = pickNumber(payload, 'visited_at') ?? pickNumber(payload, 'visitedAt') ?? Date.now();
    if (!customerId || !resultValue) {
        return res.status(400).json({ success: false, message: 'Missing visit report data' });
    }
    const id = pickString(payload, 'id') ?? (0, crypto_1.randomUUID)();
    const now = Date.now();
    const sql = `
    WITH inserted AS (
      INSERT INTO visit_reports (
        id,
        merchant_id,
        task_id,
        customer_id,
        result,
        notes,
        visited_at,
        created_at,
        updated_at,
        created_by_app_user_id,
        updated_by_app_user_id
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
      ON CONFLICT (id) DO NOTHING
      RETURNING *
    )
    SELECT * FROM inserted
    UNION ALL
    SELECT * FROM visit_reports
    WHERE id = $1 AND merchant_id = $2
    LIMIT 1
  `;
    try {
        const result = await pool.query(sql, [
            id,
            merchantId,
            taskId,
            customerId,
            resultValue,
            notes,
            visitedAt,
            now,
            now,
            actorAppUserId,
            actorAppUserId,
        ]);
        if (!result.rows[0]) {
            return res.status(409).json({ success: false, message: 'Visit report ID already in use' });
        }
        return res.json({ success: true, data: result.rows[0] });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.get('/engage/surveys', async (req, res) => {
    const merchantId = req.merchantId;
    const surveysSql = `
    SELECT id, merchant_id, title, description, is_active, created_at, updated_at
    FROM surveys
    WHERE merchant_id = $1 AND is_active = true
    ORDER BY updated_at DESC
  `;
    const questionsSql = `
    SELECT id,
           merchant_id,
           survey_id,
           question_text,
           question_type,
           sort_order,
           is_required,
           options_payload,
           created_at,
           updated_at
    FROM survey_questions
    WHERE merchant_id = $1
    ORDER BY survey_id ASC, sort_order ASC
  `;
    try {
        const [surveysResult, questionsResult] = await Promise.all([
            pool.query(surveysSql, [merchantId]),
            pool.query(questionsSql, [merchantId]),
        ]);
        const questionsBySurvey = new Map();
        for (const row of questionsResult.rows) {
            const surveyId = String(row.survey_id ?? '');
            if (!questionsBySurvey.has(surveyId)) {
                questionsBySurvey.set(surveyId, []);
            }
            questionsBySurvey.get(surveyId).push(row);
        }
        const data = surveysResult.rows.map((row) => ({
            ...row,
            questions: questionsBySurvey.get(String(row.id)) ?? [],
        }));
        return res.json({ success: true, data });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
app.post('/engage/surveys', async (req, res) => {
    const authedReq = req;
    const merchantId = authedReq.merchantId;
    const actorAppUserId = authedReq.appUserId ?? null;
    const payload = req.body ?? {};
    const title = pickString(payload, 'title');
    const description = pickString(payload, 'description');
    const rawQuestions = Array.isArray(payload.questions) ? payload.questions : [];
    if (!title) {
        return res.status(400).json({ success: false, message: 'Missing title' });
    }
    if (rawQuestions.length === 0) {
        return res.status(400).json({ success: false, message: 'Missing questions' });
    }
    if (rawQuestions.length > 5) {
        return res.status(400).json({ success: false, message: 'Max 5 questions allowed' });
    }
    const activeCountSql = `
    SELECT COUNT(*)::int AS total
    FROM surveys
    WHERE merchant_id = $1 AND is_active = true
  `;
    const surveyId = (0, crypto_1.randomUUID)();
    const now = Date.now();
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const activeCountResult = await client.query(activeCountSql, [merchantId]);
        const totalActive = Number(activeCountResult.rows[0]?.total ?? 0);
        if (totalActive >= 10) {
            await client.query('ROLLBACK');
            return res.status(400).json({ success: false, message: 'Max 10 active surveys allowed' });
        }
        await client.query(`
      INSERT INTO surveys (
        id, merchant_id, title, description, is_active, created_at, updated_at, created_by_app_user_id, updated_by_app_user_id
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      `, [surveyId, merchantId, title, description, true, now, now, actorAppUserId, actorAppUserId]);
        const questionsData = [];
        for (let index = 0; index < rawQuestions.length; index += 1) {
            const item = rawQuestions[index];
            const questionText = pickString(item, 'question_text');
            const questionType = pickString(item, 'question_type') ?? 'SHORT_TEXT';
            const isRequired = pickBoolean(item, 'is_required') ?? false;
            const sortOrder = pickNumber(item, 'sort_order') ?? index;
            const optionsPayload = Array.isArray(item.options_payload)
                ? item.options_payload
                : [];
            if (!questionText) {
                await client.query('ROLLBACK');
                return res.status(400).json({ success: false, message: 'Question text is required' });
            }
            const questionId = (0, crypto_1.randomUUID)();
            await client.query(`
        INSERT INTO survey_questions (
          id,
          merchant_id,
          survey_id,
          question_text,
          question_type,
          sort_order,
          is_required,
          options_payload,
          created_at,
          updated_at,
          created_by_app_user_id,
          updated_by_app_user_id
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
        `, [
                questionId,
                merchantId,
                surveyId,
                questionText,
                questionType,
                sortOrder,
                isRequired,
                optionsPayload,
                now,
                now,
                actorAppUserId,
                actorAppUserId,
            ]);
            questionsData.push({
                id: questionId,
                merchant_id: merchantId,
                survey_id: surveyId,
                question_text: questionText,
                question_type: questionType,
                sort_order: sortOrder,
                is_required: isRequired,
                options_payload: optionsPayload,
                created_at: now,
                updated_at: now,
            });
        }
        await client.query('COMMIT');
        return res.json({
            success: true,
            data: {
                id: surveyId,
                merchant_id: merchantId,
                title,
                description,
                is_active: true,
                created_at: now,
                updated_at: now,
                questions: questionsData,
            },
        });
    }
    catch (error) {
        await client.query('ROLLBACK');
        return res.status(500).json({ success: false, message: 'Server error' });
    }
    finally {
        client.release();
    }
});
app.post('/engage/survey-response', async (req, res) => {
    const authedReq = req;
    const merchantId = authedReq.merchantId;
    const actorAppUserId = authedReq.appUserId ?? null;
    const payload = req.body ?? {};
    const surveyId = pickString(payload, 'survey_id') ?? pickString(payload, 'surveyId');
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const channel = pickString(payload, 'channel') ?? 'manual';
    const answers = Array.isArray(payload.answers) ? payload.answers : [];
    if (!surveyId) {
        return res.status(400).json({ success: false, message: 'Missing survey_id' });
    }
    if (answers.length === 0) {
        return res.status(400).json({ success: false, message: 'Missing answers' });
    }
    const responseId = pickString(payload, 'id') ??
        pickString(payload, 'response_id') ??
        pickString(payload, 'responseId') ??
        (0, crypto_1.randomUUID)();
    const now = Date.now();
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const responseResult = await client.query(`
      WITH inserted AS (
        INSERT INTO survey_responses (
          id,
          merchant_id,
          survey_id,
          customer_id,
          submitted_at,
          channel,
          created_at,
          updated_at,
          created_by_app_user_id,
          updated_by_app_user_id
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
        ON CONFLICT (id) DO NOTHING
        RETURNING id
      )
      SELECT id, true AS inserted FROM inserted
      UNION ALL
      SELECT id, false AS inserted
      FROM survey_responses
      WHERE id = $1 AND merchant_id = $2
      LIMIT 1
      `, [
            responseId,
            merchantId,
            surveyId,
            customerId,
            now,
            channel,
            now,
            now,
            actorAppUserId,
            actorAppUserId,
        ]);
        if (!responseResult.rows[0]) {
            await client.query('ROLLBACK');
            return res.status(409).json({ success: false, message: 'Response ID already in use' });
        }
        const inserted = responseResult.rows[0].inserted === true;
        for (const [index, item] of answers.entries()) {
            const row = item;
            const questionId = pickString(row, 'question_id') ?? pickString(row, 'questionId');
            if (!questionId)
                continue;
            const answerId = pickString(row, 'id') ??
                deterministicDocumentId('sra', [merchantId, responseId, questionId, String(index)]);
            const answerText = pickString(row, 'answer_text') ?? pickString(row, 'answerText');
            const answerNumeric = pickNumber(row, 'answer_numeric') ?? pickNumber(row, 'answerNumeric');
            const answerBool = pickBoolean(row, 'answer_bool') ?? pickBoolean(row, 'answerBool');
            await client.query(`
        INSERT INTO survey_response_answers (
          id,
          merchant_id,
          response_id,
          question_id,
          answer_text,
          answer_numeric,
          answer_bool,
          created_at,
          updated_at,
          created_by_app_user_id,
          updated_by_app_user_id
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
        ON CONFLICT (id) DO UPDATE SET
          answer_text = EXCLUDED.answer_text,
          answer_numeric = EXCLUDED.answer_numeric,
          answer_bool = EXCLUDED.answer_bool,
          updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
          updated_at = EXCLUDED.updated_at
        WHERE survey_response_answers.merchant_id = EXCLUDED.merchant_id
          AND survey_response_answers.response_id = EXCLUDED.response_id
          AND survey_response_answers.question_id = EXCLUDED.question_id
        `, [
                answerId,
                merchantId,
                responseId,
                questionId,
                answerText,
                answerNumeric,
                answerBool,
                now,
                now,
                actorAppUserId,
                actorAppUserId,
            ]);
        }
        await client.query('COMMIT');
        // Best-effort automation: survey-completed action log and risk adjustment.
        if (inserted) {
            try {
                await runSurveyCompletedAutomation(merchantId, surveyId, customerId, answers, responseId, now);
            }
            catch {
                // Do not fail response delivery if automation side-effects fail.
            }
        }
        return res.json({ success: true, data: { response_id: responseId } });
    }
    catch (error) {
        await client.query('ROLLBACK');
        return res.status(500).json({ success: false, message: 'Server error' });
    }
    finally {
        client.release();
    }
});
app.get('/engage/analytics', async (req, res) => {
    const merchantId = req.merchantId;
    const totalsSql = `
    SELECT
      (SELECT COUNT(*)::int FROM surveys WHERE merchant_id = $1 AND is_active = true) AS active_surveys,
      (SELECT COUNT(*)::int FROM survey_responses WHERE merchant_id = $1) AS responses_total,
      (
        SELECT AVG(sra.answer_numeric)
        FROM survey_response_answers sra
        WHERE sra.merchant_id = $1
          AND sra.answer_numeric IS NOT NULL
      ) AS customer_satisfaction
  `;
    const topSql = `
    SELECT COALESCE(answer_text, '') AS answer_text, COUNT(*)::int AS total
    FROM survey_response_answers
    WHERE merchant_id = $1
      AND answer_text IS NOT NULL
      AND answer_text <> ''
    GROUP BY answer_text
    ORDER BY total DESC
    LIMIT 3
  `;
    try {
        const [totalsResult, topResult] = await Promise.all([
            pool.query(totalsSql, [merchantId]),
            pool.query(topSql, [merchantId]),
        ]);
        const totals = totalsResult.rows[0] ?? {};
        const activeSurveys = Number(totals.active_surveys ?? 0);
        const responsesTotal = Number(totals.responses_total ?? 0);
        const customerSatisfaction = Number(totals.customer_satisfaction ?? 0);
        const topTexts = topResult.rows
            .map((row) => String(row.answer_text ?? '').trim())
            .filter((value) => value.length > 0);
        const responseRate = activeSurveys === 0 ? 0 : (responsesTotal / activeSurveys) * 100;
        return res.json({
            success: true,
            data: {
                response_rate: responseRate,
                customer_satisfaction: customerSatisfaction,
                responses_total: responsesTotal,
                top_churn_reasons: topTexts,
                top_recovery_incentives: topTexts,
                staff_ratings: topTexts,
            },
        });
    }
    catch (error) {
        return res.status(500).json({ success: false, message: 'Server error' });
    }
});
exports.api = (0, https_1.onRequest)({
    cors: true,
    invoker: 'public',
    secrets: [customerIdentityHmacSecret],
}, app);
exports.customerCoreCanonicalLinkOnCustomerWrite = (0, firestore_1.onDocumentWritten)({
    document: 'businesses/{merchantId}/customers/{customerId}',
    secrets: [customerIdentityHmacSecret],
}, async (event) => {
    const merchantId = isNonEmptyString(event.params.merchantId)
        ? event.params.merchantId.trim()
        : '';
    const customerId = isNonEmptyString(event.params.customerId)
        ? event.params.customerId.trim()
        : '';
    if (!merchantId || !customerId) {
        return;
    }
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;
    if (!afterSnapshot?.exists) {
        return;
    }
    const beforeData = beforeSnapshot?.exists
        ? snapshotDataRecord(beforeSnapshot)
        : {};
    const afterData = snapshotDataRecord(afterSnapshot);
    if (beforeSnapshot?.exists &&
        shouldIgnoreCustomerCanonicalProjectionWrite(beforeData, afterData)) {
        return;
    }
    try {
        await linkCanonicalCustomerToBusinessCustomer({
            merchantId,
            customerId,
            rawPhone: maybePayloadString(afterData, 'phone'),
            customerName: maybePayloadString(afterData, 'name'),
            createCustomerIfMissing: false,
            dryRun: false,
        });
    }
    catch (error) {
        if (error instanceof CustomerCoreError) {
            if (error.code.startsWith('retention_')) {
                console.error('retention_classification_after_link_error', {
                    merchant_id: merchantId,
                    customer_id: customerId,
                    code: error.code,
                    message: error.message,
                    details: error.details,
                });
                throw error;
            }
            console.error('customer_core_trigger_error', {
                merchant_id: merchantId,
                customer_id: customerId,
                code: error.code,
                message: error.message,
                details: error.details,
            });
            await afterSnapshot.ref.set({
                canonical_link_status: 'ERROR',
                canonical_link_error_code: error.code,
                canonical_link_error_message: error.message,
                canonical_link_error_at: Date.now(),
            }, { merge: true });
            return;
        }
        throw error;
    }
});
exports.loyaltyLedgerSaleOnSaleWrite = (0, firestore_1.onDocumentWritten)({
    document: 'businesses/{merchantId}/sales/{saleId}',
    secrets: [customerIdentityHmacSecret],
}, async (event) => {
    const merchantId = isNonEmptyString(event.params.merchantId)
        ? event.params.merchantId.trim()
        : '';
    const saleId = isNonEmptyString(event.params.saleId)
        ? event.params.saleId.trim()
        : '';
    if (!merchantId || !saleId) {
        return;
    }
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;
    if (!afterSnapshot?.exists) {
        return;
    }
    const beforeData = beforeSnapshot?.exists
        ? snapshotDataRecord(beforeSnapshot)
        : {};
    const afterData = snapshotDataRecord(afterSnapshot);
    if (beforeSnapshot?.exists && shouldIgnoreSaleProjectionWrite(beforeData, afterData)) {
        return;
    }
    try {
        await applySaleToLoyaltyLedger({
            merchantId,
            saleId,
            saleSnapshot: afterSnapshot,
            allowLegacyBootstrap: false,
            saleUpdateMode: 'trigger',
        });
    }
    catch (error) {
        if (error instanceof CustomerCoreError) {
            if (error.code.startsWith('retention_')) {
                console.error('retention_classification_after_sale_error', {
                    merchant_id: merchantId,
                    sale_id: saleId,
                    code: error.code,
                    message: error.message,
                    details: error.details,
                });
                throw error;
            }
            console.error('loyalty_sale_trigger_error', {
                merchant_id: merchantId,
                sale_id: saleId,
                code: error.code,
                message: error.message,
                details: error.details,
            });
            await afterSnapshot.ref.set({
                confirmation_status: error.code === 'loyalty_backfill_required'
                    ? 'BASELINE_REQUIRED'
                    : 'REJECTED',
                confirmation_error_code: error.code,
                confirmed_at: admin.firestore.FieldValue.delete(),
                confirmed_points: admin.firestore.FieldValue.delete(),
                updated_at: Date.now(),
                loyalty_policy_version: admin.firestore.FieldValue.delete(),
                confirmed_points_awarded: admin.firestore.FieldValue.delete(),
                loyalty_ledger_entry_id: admin.firestore.FieldValue.delete(),
                loyalty_points_per_mzn: admin.firestore.FieldValue.delete(),
                loyalty_config_version: admin.firestore.FieldValue.delete(),
                loyalty_status: admin.firestore.FieldValue.delete(),
                loyalty_error_code: admin.firestore.FieldValue.delete(),
                loyalty_error_message: admin.firestore.FieldValue.delete(),
                loyalty_error_at: admin.firestore.FieldValue.delete(),
                loyalty_processed_at: admin.firestore.FieldValue.delete(),
            }, { merge: true });
            const customerId = maybePayloadString(afterData, 'customer_id', 'customerId');
            if (customerId && error.code === 'loyalty_backfill_required') {
                await businessCustomerRef(merchantId, customerId).set({
                    loyalty_projection_status: 'BACKFILL_REQUIRED',
                    loyalty_backfill_required: true,
                    loyalty_last_reconciled_at: Date.now(),
                }, { merge: true });
            }
            return;
        }
        throw error;
    }
});
function resolveMerchantId(decoded) {
    const claims = decoded;
    const fromClaims = typeof claims.merchant_id === 'string'
        ? claims.merchant_id
        : typeof claims.merchantId === 'string'
            ? claims.merchantId
            : null;
    return fromClaims ?? decoded.uid ?? null;
}
function resolveAppUserId(decoded) {
    const claims = decoded;
    const fromClaims = typeof claims.app_user_id === 'string'
        ? claims.app_user_id
        : typeof claims.appUserId === 'string'
            ? claims.appUserId
            : undefined;
    return fromClaims ?? decoded.uid ?? undefined;
}
function resolveAppUserRole(decoded) {
    const claims = decoded;
    const claimRole = typeof claims.app_user_role === 'string'
        ? claims.app_user_role
        : typeof claims.appUserRole === 'string'
            ? claims.appUserRole
            : typeof claims.role === 'string'
                ? claims.role
                : null;
    const normalized = claimRole?.trim().toUpperCase();
    if (normalized === 'STAFF') {
        return 'STAFF';
    }
    return 'OWNER';
}
function isAdminRequest(req) {
    if (hasValidAdminApiKey(req))
        return true;
    return hasAdminClaims(req.auth);
}
function hasAdminClaims(claims) {
    if (!claims)
        return false;
    if (claims.admin === true)
        return true;
    if (claims.is_admin === true)
        return true;
    if (claims.internal_admin === true)
        return true;
    const role = typeof claims.role === 'string'
        ? claims.role.trim().toLowerCase()
        : null;
    if (role === 'admin')
        return true;
    if (role === 'internal_admin')
        return true;
    return false;
}
function hasValidAdminApiKey(req) {
    const adminKey = process.env.ADMIN_API_KEY;
    const headerKey = pickHeaderString(req.headers['x-admin-key']);
    return Boolean(adminKey && headerKey && adminKey === headerKey);
}
function isAdminPath(req) {
    return req.path === '/admin' || req.path.startsWith('/admin/');
}
function supportsBodyMerchantScope(req) {
    return req.path.startsWith('/customer-core/') ||
        req.path.startsWith('/loyalty/') ||
        req.path.startsWith('/retention/') ||
        req.path.startsWith('/notifications/');
}
function isOwnerRequest(req) {
    const role = req.appUserRole?.trim().toUpperCase();
    return role == null || role.length === 0 || role === 'OWNER';
}
function isOwnerOrAdminRequest(req) {
    return isAdminRequest(req) || isOwnerRequest(req);
}
function parseNumber(value) {
    if (typeof value === 'number' && Number.isFinite(value))
        return value;
    if (isNonEmptyString(value)) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}
function clampLimit(value, fallback, max) {
    const parsed = parseNumber(value);
    if (parsed == null || parsed <= 0)
        return fallback;
    return Math.min(Math.floor(parsed), max);
}
function pickString(payload, key) {
    const value = payload[key];
    if (isNonEmptyString(value)) {
        return value.trim();
    }
    return null;
}
function pickBoolean(payload, key) {
    const value = payload[key];
    if (typeof value === 'boolean')
        return value;
    if (typeof value === 'number')
        return value !== 0;
    if (typeof value === 'string') {
        const normalized = value.trim().toLowerCase();
        if (normalized === 'true')
            return true;
        if (normalized === 'false')
            return false;
        if (normalized === '1')
            return true;
        if (normalized === '0')
            return false;
    }
    return null;
}
exports.retentionDomainEventPostgresProjection = (0, firestore_1.onDocumentWritten)('businesses/{merchantId}/domain_events/{eventId}', async (event) => {
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;
    if (beforeSnapshot?.exists || !afterSnapshot?.exists) {
        return;
    }
    const merchantId = isNonEmptyString(event.params.merchantId)
        ? event.params.merchantId.trim()
        : '';
    const eventId = isNonEmptyString(event.params.eventId)
        ? event.params.eventId.trim()
        : '';
    const data = snapshotDataRecord(afterSnapshot);
    if (!merchantId ||
        !eventId ||
        maybePayloadString(data, 'event_id') !== eventId ||
        maybePayloadString(data, 'merchant_id') !== merchantId) {
        throw new Error('Invalid retention domain event path identity.');
    }
    const sourceRaw = data.source;
    const source = sourceRaw != null && typeof sourceRaw === 'object'
        ? sourceRaw
        : {};
    await pool.query(`
        INSERT INTO retention_domain_events (
          event_id,
          event_type,
          schema_version,
          merchant_id,
          canonical_customer_id,
          business_customer_id,
          source_type,
          source_id,
          correlation_id,
          causation_id,
          occurred_at,
          recorded_at,
          payload,
          projected_at
        ) VALUES (
          $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb,$14
        )
        ON CONFLICT (event_id) DO NOTHING
      `, [
        eventId,
        maybePayloadString(data, 'event_type'),
        pickNumber(data, 'schema_version'),
        merchantId,
        maybePayloadString(data, 'canonical_customer_id'),
        maybePayloadString(data, 'business_customer_id'),
        maybePayloadString(source, 'type'),
        maybePayloadString(source, 'id'),
        maybePayloadString(data, 'correlation_id'),
        maybePayloadString(data, 'causation_id'),
        pickNumber(data, 'occurred_at'),
        pickNumber(data, 'recorded_at'),
        JSON.stringify(data.payload ?? {}),
        Date.now(),
    ]);
});
function pickHeaderString(value) {
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
function pickQueryString(value) {
    if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
    }
    if (Array.isArray(value)) {
        const first = value.find((item) => typeof item === 'string' && item.trim().length > 0);
        return typeof first === 'string' ? first.trim() : null;
    }
    return null;
}
class CustomerCoreError extends Error {
    constructor(status, code, message, details) {
        super(message);
        this.name = 'CustomerCoreError';
        this.status = status;
        this.code = code;
        this.details = details;
    }
}
function respondCustomerCoreError(res, error) {
    if (error instanceof CustomerCoreError) {
        return res.status(error.status).json({
            success: false,
            code: error.code,
            message: error.message,
            ...(error.details ? { details: error.details } : {}),
        });
    }
    console.error('customer_core_error', error);
    return res.status(500).json({
        success: false,
        code: 'customer_core_internal',
        message: 'Server error',
    });
}
function requireBodyObject(body) {
    if (body == null || typeof body !== 'object' || Array.isArray(body)) {
        throw new CustomerCoreError(400, 'invalid_payload', 'Invalid payload.');
    }
    return body;
}
function maybePayloadString(payload, ...keys) {
    for (const key of keys) {
        const value = pickString(payload, key);
        if (value)
            return value;
    }
    return null;
}
function maybePayloadBoolean(payload, ...keys) {
    for (const key of keys) {
        const value = pickBoolean(payload, key);
        if (value != null)
            return value;
    }
    return null;
}
function requirePayloadString(payload, key) {
    const value = pickString(payload, key);
    if (!value) {
        throw new CustomerCoreError(400, 'missing_field', `Missing required field: ${key}.`);
    }
    return value;
}
function requireCustomerCoreSecret() {
    const secret = customerIdentityHmacSecret.value();
    if (typeof secret !== 'string' || secret.trim().length < 16) {
        throw new CustomerCoreError(500, 'customer_core_secret_missing', `Set ${CUSTOMER_CORE_SECRET_ENV} before using customer core routes.`);
    }
    return secret;
}
function normalizeMozambiquePhoneToE164(raw) {
    const clean = raw.trim().replace(/[\s-]/g, '');
    let local = null;
    if (clean.startsWith('+258')) {
        local = clean.substring(4);
    }
    else if (clean.startsWith('258') && clean.length === 12) {
        local = clean.substring(3);
    }
    else if (clean.length === 9) {
        local = clean;
    }
    if (local &&
        /^[0-9]{9}$/.test(local) &&
        MOZAMBIQUE_PHONE_PREFIXES.has(local.substring(0, 2))) {
        return `+258${local}`;
    }
    throw new CustomerCoreError(400, 'invalid_phone', 'Use a valid Mozambique phone number in 8X XXX XXXX or +258XXXXXXXXX format.', { phone: raw });
}
function tryNormalizeMozambiquePhoneToE164(raw) {
    if (!isNonEmptyString(raw))
        return null;
    try {
        return normalizeMozambiquePhoneToE164(raw);
    }
    catch {
        return null;
    }
}
function normalizeMozambiquePhoneToLocal(raw) {
    return normalizeMozambiquePhoneToE164(raw).substring(4);
}
function buildCanonicalCustomerId(phoneE164) {
    const secret = requireCustomerCoreSecret();
    return (0, crypto_1.createHmac)('sha256', secret)
        .update(`moz-phone-e164-v1:${phoneE164}`)
        .digest('hex');
}
function serializeCanonicalCustomerIdentity(identity) {
    return {
        canonical_customer_id: identity.canonicalCustomerId,
        lookup_key: identity.canonicalCustomerId,
        phone_e164: identity.phoneE164,
        phone_last4: identity.phoneLast4,
        created_at: identity.createdAt,
        updated_at: identity.updatedAt,
    };
}
function last4(value) {
    return value.slice(-4);
}
function snapshotDataRecord(snapshot) {
    const data = snapshot.data();
    if (data == null || typeof data !== 'object') {
        return {};
    }
    return data;
}
function buildCompoundKey(...parts) {
    return parts
        .map((part) => Buffer.from(part, 'utf8').toString('base64url'))
        .join('__');
}
function valuesEqual(left, right) {
    if (left === right)
        return true;
    if (left == null || right == null)
        return left === right;
    if (typeof left === 'object' || typeof right === 'object') {
        try {
            return JSON.stringify(left) === JSON.stringify(right);
        }
        catch {
            return false;
        }
    }
    return false;
}
function changedKeys(beforeData, afterData) {
    const keys = new Set([
        ...Object.keys(beforeData),
        ...Object.keys(afterData),
    ]);
    return [...keys].filter((key) => !valuesEqual(beforeData[key], afterData[key]));
}
function shouldIgnoreCustomerCanonicalProjectionWrite(beforeData, afterData) {
    const changed = changedKeys(beforeData, afterData);
    return changed.length > 0 && changed.every((key) => key === 'updated_at' || CUSTOMER_SERVER_OWNED_FIELDS.includes(key));
}
function shouldIgnoreSaleProjectionWrite(beforeData, afterData) {
    const changed = changedKeys(beforeData, afterData);
    return changed.length > 0 && changed.every((key) => key === 'updated_at' ||
        SALE_SERVER_OWNED_FIELDS.includes(key));
}
function buildDefaultBusinessCustomerId(canonicalCustomerId) {
    return `cust_${canonicalCustomerId.substring(0, 24)}`;
}
function setIfMissingString(patch, source, key, value) {
    if (maybePayloadString(source, key) == null) {
        patch[key] = value;
    }
}
function setIfMissingNumber(patch, source, key, value) {
    if (pickNumber(source, key) == null) {
        patch[key] = value;
    }
}
function canonicalCustomerIdentityRef(canonicalCustomerId) {
    return admin.firestore().collection(CUSTOMER_IDENTITY_COLLECTION).doc(canonicalCustomerId);
}
function customerAccountRef(firebaseUid) {
    return admin.firestore().collection(CUSTOMER_ACCOUNT_COLLECTION).doc(firebaseUid);
}
function customerPushTokenRef(firebaseUid, token) {
    const tokenId = (0, crypto_1.createHash)('sha256')
        .update(firebaseUid)
        .update('\u001f')
        .update(token)
        .digest('hex');
    return admin.firestore().collection(CUSTOMER_PUSH_TOKEN_COLLECTION).doc(tokenId);
}
function customerIdentityAccountLinkRef(canonicalCustomerId) {
    return admin
        .firestore()
        .collection(CUSTOMER_IDENTITY_ACCOUNT_LINK_COLLECTION)
        .doc(canonicalCustomerId);
}
function businessCustomerRef(merchantId, customerId) {
    return admin
        .firestore()
        .collection('businesses')
        .doc(merchantId)
        .collection('customers')
        .doc(customerId);
}
function businessCustomerLinkRef(merchantId, customerId) {
    return admin
        .firestore()
        .collection(BUSINESS_CUSTOMER_LINK_COLLECTION)
        .doc(buildCompoundKey(merchantId, customerId));
}
function canonicalIdentityBusinessLinkRef(merchantId, canonicalCustomerId) {
    return admin
        .firestore()
        .collection(CANONICAL_IDENTITY_BUSINESS_LINK_COLLECTION)
        .doc(buildCompoundKey(merchantId, canonicalCustomerId));
}
function requestHasMerchantClaim(decoded, merchantId) {
    if (!decoded)
        return false;
    const claims = decoded;
    const directClaim = typeof claims.merchant_id === 'string'
        ? claims.merchant_id
        : typeof claims.merchantId === 'string'
            ? claims.merchantId
            : null;
    if (directClaim === merchantId)
        return true;
    const merchantIds = claims.merchant_ids;
    if (Array.isArray(merchantIds) && merchantIds.includes(merchantId)) {
        return true;
    }
    const merchantIdsAlt = claims.merchantIds;
    if (Array.isArray(merchantIdsAlt) && merchantIdsAlt.includes(merchantId)) {
        return true;
    }
    return false;
}
function requestMatchesBusinessOwner(req, businessData) {
    const authUid = req.auth?.uid;
    const ownerUserId = maybePayloadString(businessData, 'owner_user_id', 'ownerUserId');
    const firebaseUid = maybePayloadString(businessData, 'firebase_uid', 'firebaseUid');
    if (authUid && (ownerUserId === authUid || firebaseUid === authUid)) {
        return true;
    }
    if (req.appUserId && ownerUserId === req.appUserId) {
        return true;
    }
    const businessPhone = tryNormalizeMozambiquePhoneToE164(maybePayloadString(businessData, 'phone'));
    const authPhone = tryNormalizeMozambiquePhoneToE164(req.auth?.phone_number);
    return businessPhone != null && authPhone != null && businessPhone === authPhone;
}
function buildPhoneSearchCandidates(rawPhone, phoneE164) {
    const values = new Set();
    const trimmed = rawPhone.trim();
    if (trimmed.length > 0) {
        values.add(trimmed);
    }
    values.add(phoneE164);
    values.add(normalizeMozambiquePhoneToLocal(phoneE164));
    return [...values];
}
async function requestHasBusinessMembership(req, merchantId) {
    const authPhone = req.auth?.phone_number;
    const normalizedPhone = tryNormalizeMozambiquePhoneToE164(authPhone);
    if (!normalizedPhone || !authPhone) {
        return false;
    }
    const candidates = buildPhoneSearchCandidates(authPhone, normalizedPhone);
    const appUsersRef = admin
        .firestore()
        .collection('businesses')
        .doc(merchantId)
        .collection('app_users');
    for (const candidate of candidates) {
        const snapshot = await appUsersRef.where('phone', '==', candidate).limit(5).get();
        const hasActiveMembership = snapshot.docs.some((doc) => {
            const data = snapshotDataRecord(doc);
            const status = maybePayloadString(data, 'status');
            return status !== 'INACTIVE';
        });
        if (hasActiveMembership) {
            return true;
        }
    }
    return false;
}
async function requestCanAccessMerchant(req, merchantId) {
    if (isAdminRequest(req))
        return true;
    if (!req.auth || !merchantId.trim())
        return false;
    if (requestHasMerchantClaim(req.auth, merchantId)) {
        return true;
    }
    const businessSnapshot = await admin
        .firestore()
        .collection('businesses')
        .doc(merchantId)
        .get();
    if (!businessSnapshot.exists) {
        return false;
    }
    const businessData = snapshotDataRecord(businessSnapshot);
    if (requestMatchesBusinessOwner(req, businessData)) {
        return true;
    }
    return requestHasBusinessMembership(req, merchantId);
}
async function resolveCustomerCoreMerchantId(req, payload) {
    const requestedMerchantId = maybePayloadString(payload, 'merchant_id', 'merchantId');
    if (isAdminRequest(req)) {
        if (!requestedMerchantId) {
            throw new CustomerCoreError(400, 'merchant_scope_required', 'merchant_id is required for admin customer core requests.');
        }
        return requestedMerchantId;
    }
    const merchantId = requestedMerchantId ?? req.merchantId;
    if (!merchantId) {
        throw new CustomerCoreError(403, 'merchant_scope_required', 'Missing merchant scope.');
    }
    if (!(await requestCanAccessMerchant(req, merchantId))) {
        throw new CustomerCoreError(403, 'merchant_access_denied', 'Authenticated user is not allowed to access the requested business.', { merchant_id: merchantId });
    }
    return merchantId;
}
async function findCanonicalCustomerIdentity(phoneE164) {
    const canonicalCustomerId = buildCanonicalCustomerId(phoneE164);
    const snapshot = await canonicalCustomerIdentityRef(canonicalCustomerId).get();
    if (!snapshot.exists) {
        return null;
    }
    const data = snapshotDataRecord(snapshot);
    const createdAt = pickNumber(data, 'created_at') ?? Date.now();
    const updatedAt = pickNumber(data, 'updated_at') ?? createdAt;
    return {
        canonicalCustomerId,
        phoneE164: maybePayloadString(data, 'phone_e164') ?? phoneE164,
        phoneLast4: maybePayloadString(data, 'phone_last4') ?? last4(phoneE164),
        createdAt,
        updatedAt,
        created: false,
    };
}
async function findOrCreateCanonicalCustomerIdentity(merchantId, phoneE164) {
    const canonicalCustomerId = buildCanonicalCustomerId(phoneE164);
    const now = Date.now();
    const result = await admin.firestore().runTransaction(async (transaction) => {
        const identityRef = canonicalCustomerIdentityRef(canonicalCustomerId);
        const snapshot = await transaction.get(identityRef);
        if (snapshot.exists) {
            const data = snapshotDataRecord(snapshot);
            const createdAt = pickNumber(data, 'created_at') ?? now;
            const updatedAt = pickNumber(data, 'updated_at') ?? createdAt;
            return {
                canonicalCustomerId,
                phoneE164: maybePayloadString(data, 'phone_e164') ?? phoneE164,
                phoneLast4: maybePayloadString(data, 'phone_last4') ?? last4(phoneE164),
                createdAt,
                updatedAt,
                created: false,
            };
        }
        transaction.set(identityRef, {
            id: canonicalCustomerId,
            lookup_key: canonicalCustomerId,
            phone_e164: phoneE164,
            phone_last4: last4(phoneE164),
            country_code: 'MZ',
            identity_version: 1,
            created_at: now,
            updated_at: now,
            created_by_merchant_id: merchantId,
            last_linked_merchant_id: merchantId,
            last_linked_at: now,
        });
        return {
            canonicalCustomerId,
            phoneE164,
            phoneLast4: last4(phoneE164),
            createdAt: now,
            updatedAt: now,
            created: true,
        };
    });
    return result;
}
async function handleCustomerSessionRequest(req) {
    const firebaseUid = req.auth?.uid?.trim() ?? '';
    if (!firebaseUid) {
        throw new CustomerCoreError(401, 'customer_auth_required', 'Authenticated customer identity is required.');
    }
    const tokenPhone = req.auth?.phone_number;
    if (!isNonEmptyString(tokenPhone)) {
        throw new CustomerCoreError(403, 'verified_phone_required', 'Customer access requires a verified phone number.');
    }
    const phoneE164 = normalizeMozambiquePhoneToE164(tokenPhone);
    const canonicalCustomerId = buildCanonicalCustomerId(phoneE164);
    const now = Date.now();
    let binding;
    try {
        binding = await admin.firestore().runTransaction(async (transaction) => {
            const accountRef = customerAccountRef(firebaseUid);
            const identityAccountLinkRef = customerIdentityAccountLinkRef(canonicalCustomerId);
            const identityRef = canonicalCustomerIdentityRef(canonicalCustomerId);
            const [accountSnapshot, identityAccountLinkSnapshot, identitySnapshot] = await Promise.all([
                transaction.get(accountRef),
                transaction.get(identityAccountLinkRef),
                transaction.get(identityRef),
            ]);
            const accountData = snapshotDataRecord(accountSnapshot);
            const identityAccountLinkData = snapshotDataRecord(identityAccountLinkSnapshot);
            const conflict = (0, customer_account_binding_js_1.findCustomerAccountBindingConflict)({
                firebaseUid,
                canonicalCustomerId,
                existingAccountCanonicalCustomerId: maybePayloadString(accountData, 'canonical_customer_id', 'canonicalCustomerId'),
                existingIdentityFirebaseUid: maybePayloadString(identityAccountLinkData, 'firebase_uid', 'firebaseUid'),
            });
            if (conflict === 'account_identity_mismatch') {
                throw new CustomerCoreError(409, conflict, 'The authenticated account is already linked to another customer identity.');
            }
            if (conflict === 'identity_account_mismatch') {
                throw new CustomerCoreError(409, conflict, 'This customer identity is already linked to another authenticated account.');
            }
            if (!identitySnapshot.exists) {
                transaction.set(identityRef, {
                    id: canonicalCustomerId,
                    lookup_key: canonicalCustomerId,
                    phone_e164: phoneE164,
                    phone_last4: last4(phoneE164),
                    country_code: 'MZ',
                    identity_version: 1,
                    account_state: 'CLAIMED',
                    account_linked_at: now,
                    created_by_actor: 'CUSTOMER',
                    created_at: now,
                    updated_at: now,
                });
            }
            else {
                transaction.set(identityRef, {
                    account_state: 'CLAIMED',
                    account_linked_at: pickNumber(snapshotDataRecord(identitySnapshot), 'account_linked_at') ?? now,
                    updated_at: now,
                }, { merge: true });
            }
            transaction.set(accountRef, {
                firebase_uid: firebaseUid,
                canonical_customer_id: canonicalCustomerId,
                phone_e164: phoneE164,
                phone_last4: last4(phoneE164),
                status: 'ACTIVE',
                schema_version: 1,
                created_at: pickNumber(accountData, 'created_at') ?? now,
                updated_at: now,
            }, { merge: true });
            transaction.set(identityAccountLinkRef, {
                canonical_customer_id: canonicalCustomerId,
                firebase_uid: firebaseUid,
                status: 'ACTIVE',
                schema_version: 1,
                created_at: pickNumber(identityAccountLinkData, 'created_at') ?? now,
                updated_at: now,
            }, { merge: true });
            return {
                accountCreated: !accountSnapshot.exists,
                identityCreated: !identitySnapshot.exists,
            };
        });
    }
    catch (error) {
        if (error instanceof CustomerCoreError &&
            (error.code === 'account_identity_mismatch' ||
                error.code === 'identity_account_mismatch')) {
            console.warn('customer_account_binding_conflict', {
                firebase_uid: firebaseUid,
                phone_last4: last4(phoneE164),
                code: error.code,
            });
        }
        throw error;
    }
    const businessLinksSnapshot = await admin
        .firestore()
        .collection(CANONICAL_IDENTITY_BUSINESS_LINK_COLLECTION)
        .where('canonical_customer_id', '==', canonicalCustomerId)
        .get();
    const businessLinks = businessLinksSnapshot.docs
        .map((snapshot) => {
        const data = snapshotDataRecord(snapshot);
        return {
            merchant_id: maybePayloadString(data, 'merchant_id'),
            business_customer_id: maybePayloadString(data, 'business_customer_id', 'customer_id'),
            relationship_created_at: pickNumber(data, 'created_at'),
            relationship_updated_at: pickNumber(data, 'updated_at'),
        };
    })
        .filter((link) => link.merchant_id != null && link.business_customer_id != null)
        .sort((left, right) => left.merchant_id.localeCompare(right.merchant_id));
    const featureFlags = serializeCustomerFeatureFlags(firebaseUid);
    return {
        actor: 'CUSTOMER',
        customer_app_enabled: featureFlags.customer_app_enabled,
        feature_flags: featureFlags,
        phone_e164: phoneE164,
        phone_last4: last4(phoneE164),
        account_created: binding.accountCreated,
        identity_created: binding.identityCreated,
        business_relationships: businessLinks,
    };
}
function serializeCustomerFeatureFlags(firebaseUid) {
    const flags = (0, customer_feature_flags_js_1.resolveCustomerFeatureFlags)(process.env);
    const appEnabled = flags.customerAppEnabled &&
        (firebaseUid == null || (0, customer_feature_flags_js_1.isCustomerUidAllowed)(process.env, firebaseUid));
    return {
        customer_app_enabled: appEnabled,
        customer_redemption_enabled: appEnabled && flags.customerRedemptionEnabled,
        customer_qr_enabled: appEnabled && flags.customerQrEnabled,
        customer_push_enabled: appEnabled && flags.customerPushEnabled,
        customer_deep_links_enabled: appEnabled && flags.customerDeepLinksEnabled,
    };
}
function requireCustomerFeature(feature) {
    const flags = (0, customer_feature_flags_js_1.resolveCustomerFeatureFlags)(process.env);
    if (!flags.customerAppEnabled || !flags[feature]) {
        throw new CustomerCoreError(403, 'customer_feature_disabled', 'This customer feature is not enabled.');
    }
}
function isSafeFirestoreDocumentId(value) {
    return value.length <= 256 && !value.includes('/');
}
function customerPreferencesFromAccount(accountData) {
    const raw = accountData.customer_preferences;
    const preferences = raw != null && typeof raw === 'object' && !Array.isArray(raw)
        ? raw
        : {};
    return {
        notifications_enabled: pickBoolean(preferences, 'notifications_enabled') ?? true,
        marketing_enabled: pickBoolean(preferences, 'marketing_enabled') ?? false,
        deep_links_enabled: pickBoolean(preferences, 'deep_links_enabled') ?? true,
    };
}
async function requireBoundCustomerAccount(req) {
    const firebaseUid = req.auth?.uid?.trim() ?? '';
    if (!firebaseUid) {
        throw new CustomerCoreError(401, 'customer_auth_required', 'Authenticated customer identity is required.');
    }
    if (!(0, customer_feature_flags_js_1.isCustomerUidAllowed)(process.env, firebaseUid)) {
        throw new CustomerCoreError(403, 'customer_feature_disabled', 'This customer account is not enabled for the current rollout.');
    }
    const accountSnapshot = await customerAccountRef(firebaseUid).get();
    if (!accountSnapshot.exists) {
        throw new CustomerCoreError(403, 'customer_account_required', 'Open the customer session before accessing customer data.');
    }
    const accountData = snapshotDataRecord(accountSnapshot);
    const canonicalCustomerId = maybePayloadString(accountData, 'canonical_customer_id', 'canonicalCustomerId');
    if (!canonicalCustomerId || maybePayloadString(accountData, 'status') !== 'ACTIVE') {
        throw new CustomerCoreError(403, 'customer_account_inactive', 'Customer account is not active.');
    }
    const identityLinkSnapshot = await customerIdentityAccountLinkRef(canonicalCustomerId).get();
    const identityLinkData = snapshotDataRecord(identityLinkSnapshot);
    if (!identityLinkSnapshot.exists ||
        maybePayloadString(identityLinkData, 'firebase_uid', 'firebaseUid') !== firebaseUid ||
        maybePayloadString(identityLinkData, 'status') !== 'ACTIVE') {
        throw new CustomerCoreError(403, 'customer_account_link_inconsistent', 'Customer account binding is inconsistent.');
    }
    return { firebaseUid, canonicalCustomerId, accountData };
}
async function listCustomerRelationshipLocators(canonicalCustomerId) {
    const snapshot = await admin
        .firestore()
        .collection(CANONICAL_IDENTITY_BUSINESS_LINK_COLLECTION)
        .where('canonical_customer_id', '==', canonicalCustomerId)
        .get();
    const locators = new Map();
    for (const document of snapshot.docs) {
        const data = snapshotDataRecord(document);
        const merchantId = maybePayloadString(data, 'merchant_id');
        const customerId = maybePayloadString(data, 'business_customer_id', 'customer_id');
        if (merchantId && customerId) {
            locators.set(`${merchantId}\u001f${customerId}`, { merchantId, customerId });
        }
    }
    return [...locators.values()].sort((left, right) => left.merchantId.localeCompare(right.merchantId));
}
async function requireCustomerBusinessRelationship(account, merchantId) {
    const locator = (await listCustomerRelationshipLocators(account.canonicalCustomerId))
        .find((item) => item.merchantId === merchantId);
    if (!locator) {
        throw new CustomerCoreError(404, 'customer_business_not_found', 'Business is not linked to the authenticated customer.');
    }
    const [customerSnapshot, forwardLinkSnapshot, reverseLinkSnapshot, businessSnapshot] = await Promise.all([
        businessCustomerRef(locator.merchantId, locator.customerId).get(),
        businessCustomerLinkRef(locator.merchantId, locator.customerId).get(),
        canonicalIdentityBusinessLinkRef(locator.merchantId, account.canonicalCustomerId).get(),
        businessDocumentRef(locator.merchantId).get(),
    ]);
    const customerData = snapshotDataRecord(customerSnapshot);
    const forwardLinkData = snapshotDataRecord(forwardLinkSnapshot);
    const reverseLinkData = snapshotDataRecord(reverseLinkSnapshot);
    if (!customerSnapshot.exists ||
        !businessSnapshot.exists ||
        maybePayloadString(customerData, 'canonical_customer_id', 'canonicalCustomerId') !==
            account.canonicalCustomerId ||
        !forwardLinkSnapshot.exists ||
        maybePayloadString(forwardLinkData, 'canonical_customer_id') !==
            account.canonicalCustomerId ||
        !reverseLinkSnapshot.exists ||
        maybePayloadString(reverseLinkData, 'business_customer_id', 'customer_id') !==
            locator.customerId) {
        throw new CustomerCoreError(409, 'customer_business_link_inconsistent', 'Customer business relationship is inconsistent.');
    }
    return {
        merchantId: locator.merchantId,
        customerId: locator.customerId,
        customerData,
        businessData: snapshotDataRecord(businessSnapshot),
    };
}
function serializeCustomerBusiness(relationship) {
    const customer = relationship.customerData;
    const business = relationship.businessData;
    return {
        business_id: relationship.merchantId,
        name: maybePayloadString(business, 'name', 'business_name') ?? 'Business',
        logo_url: maybePayloadString(business, 'logo_url', 'logoUrl'),
        address: maybePayloadString(business, 'address'),
        phone: maybePayloadString(business, 'phone'),
        confirmed_points: Math.max(0, pickNumber(customer, 'confirmed_points') ?? 0),
        last_visit_at: pickNumber(customer, 'last_visit_at'),
    };
}
function serializeCustomerReward(rewardId, rewardData, confirmedPoints) {
    const pointsRequired = pickNumber(rewardData, 'points_required') ?? pickNumber(rewardData, 'pointsRequired');
    if ((pickBoolean(rewardData, 'active') ?? true) !== true ||
        pointsRequired == null ||
        pointsRequired <= 0) {
        return null;
    }
    return {
        reward_id: rewardId,
        name: maybePayloadString(rewardData, 'name') ?? 'Reward',
        description: maybePayloadString(rewardData, 'description'),
        points_required: pointsRequired,
        confirmed_points: confirmedPoints,
        points_remaining: Math.max(0, pointsRequired - confirmedPoints),
        eligible: confirmedPoints >= pointsRequired,
        expires_at: pickNumber(rewardData, 'expires_at') ?? pickNumber(rewardData, 'expiresAt'),
    };
}
async function readCustomerBusiness(account, merchantId) {
    const relationship = await requireCustomerBusinessRelationship(account, merchantId);
    const confirmedPoints = Math.max(0, pickNumber(relationship.customerData, 'confirmed_points') ?? 0);
    const rewardsSnapshot = await businessRewardsCollectionRef(merchantId).limit(100).get();
    const rewards = rewardsSnapshot.docs
        .map((document) => serializeCustomerReward(document.id, snapshotDataRecord(document), confirmedPoints))
        .filter((reward) => reward != null)
        .sort((left, right) => left.points_required - right.points_required);
    const nextReward = rewards.find((reward) => reward.points_required > confirmedPoints) ??
        rewards.find((reward) => reward.eligible === true) ??
        null;
    return {
        ...serializeCustomerBusiness(relationship),
        rewards,
        next_reward: nextReward,
    };
}
async function readCustomerActivity(account, maximumEntries) {
    const locators = await listCustomerRelationshipLocators(account.canonicalCustomerId);
    const entries = await Promise.all(locators.map(async (locator) => {
        const relationship = await requireCustomerBusinessRelationship(account, locator.merchantId);
        const ledgerSnapshot = await boundedCustomerLedgerQuery(relationship.merchantId, relationship.customerId).get();
        assertLedgerQueryIsBounded(ledgerSnapshot, relationship.merchantId, relationship.customerId);
        return ledgerSnapshot.docs.map((document) => {
            const data = loyaltyLedgerEntryFromData(snapshotDataRecord(document));
            return {
                business_id: relationship.merchantId,
                entry_id: document.id,
                type: data.entry_type,
                points_delta: data.points_delta,
                occurred_at: data.occurred_at,
                reward_id: data.reward_id ?? null,
            };
        });
    }));
    return entries.flat()
        .sort((left, right) => right.occurred_at - left.occurred_at)
        .slice(0, maximumEntries);
}
async function handleCustomerHomeRequest(req) {
    requireCustomerFeature('customerAppEnabled');
    const account = await requireBoundCustomerAccount(req);
    const locators = await listCustomerRelationshipLocators(account.canonicalCustomerId);
    const businesses = await Promise.all(locators.map((locator) => readCustomerBusiness(account, locator.merchantId)));
    return {
        businesses,
        recent_activity: await readCustomerActivity(account, 10),
        updated_at: Date.now(),
    };
}
async function handleCustomerBusinessesRequest(req) {
    requireCustomerFeature('customerAppEnabled');
    const account = await requireBoundCustomerAccount(req);
    const locators = await listCustomerRelationshipLocators(account.canonicalCustomerId);
    return {
        businesses: await Promise.all(locators.map((locator) => readCustomerBusiness(account, locator.merchantId))),
    };
}
async function handleCustomerBusinessDetailRequest(req, merchantId) {
    requireCustomerFeature('customerAppEnabled');
    if (!isNonEmptyString(merchantId) || !isSafeFirestoreDocumentId(merchantId.trim())) {
        throw new CustomerCoreError(400, 'business_id_required', 'Business id is required.');
    }
    return readCustomerBusiness(await requireBoundCustomerAccount(req), merchantId.trim());
}
async function handleCustomerRewardsRequest(req) {
    requireCustomerFeature('customerAppEnabled');
    const account = await requireBoundCustomerAccount(req);
    const locators = await listCustomerRelationshipLocators(account.canonicalCustomerId);
    const businesses = await Promise.all(locators.map((locator) => readCustomerBusiness(account, locator.merchantId)));
    return {
        rewards: businesses.flatMap((business) => business.rewards.map((reward) => ({
            business_id: business.business_id,
            ...reward,
        }))),
    };
}
async function handleCustomerActivityRequest(req) {
    requireCustomerFeature('customerAppEnabled');
    return {
        activity: await readCustomerActivity(await requireBoundCustomerAccount(req), MAX_CUSTOMER_ACTIVITY_ENTRIES),
    };
}
async function handleCustomerProfileRequest(req) {
    requireCustomerFeature('customerAppEnabled');
    const account = await requireBoundCustomerAccount(req);
    const locators = await listCustomerRelationshipLocators(account.canonicalCustomerId);
    const firstRelationship = locators.length > 0
        ? await requireCustomerBusinessRelationship(account, locators[0].merchantId)
        : null;
    return {
        display_name: firstRelationship == null
            ? null
            : maybePayloadString(firstRelationship.customerData, 'name'),
        phone_e164: req.auth?.phone_number ?? null,
        preferences: customerPreferencesFromAccount(account.accountData),
        linked_business_count: locators.length,
    };
}
async function handleCustomerPreferencesRequest(req, payload) {
    requireCustomerFeature('customerAppEnabled');
    const allowedKeys = new Set([
        'notifications_enabled',
        'marketing_enabled',
        'deep_links_enabled',
    ]);
    if (Object.keys(payload).length === 0 ||
        Object.keys(payload).some((key) => !allowedKeys.has(key))) {
        throw new CustomerCoreError(400, 'customer_preferences_invalid', 'Only customer notification preference fields may be updated.');
    }
    const account = await requireBoundCustomerAccount(req);
    const current = customerPreferencesFromAccount(account.accountData);
    const preferences = {
        ...current,
        ...Object.fromEntries(Object.keys(payload).map((key) => {
            const value = pickBoolean(payload, key);
            if (value == null) {
                throw new CustomerCoreError(400, 'customer_preferences_invalid', `${key} must be a boolean.`);
            }
            return [key, value];
        })),
    };
    await customerAccountRef(account.firebaseUid).set({
        customer_preferences: preferences,
        customer_preferences_updated_at: Date.now(),
        updated_at: Date.now(),
    }, { merge: true });
    return { preferences };
}
async function handleCustomerPushTokenRegistration(req, payload) {
    requireCustomerFeature('customerPushEnabled');
    const registration = parseCustomerPushToken(payload);
    const account = await requireBoundCustomerAccount(req);
    const tokenRef = customerPushTokenRef(account.firebaseUid, registration.token);
    const now = Date.now();
    await admin.firestore().runTransaction(async (transaction) => {
        const existing = await transaction.get(tokenRef);
        const existingData = snapshotDataRecord(existing);
        transaction.set(tokenRef, {
            account_firebase_uid: account.firebaseUid,
            platform: registration.platform,
            fcm_token: registration.token,
            created_at: pickNumber(existingData, 'created_at') ?? now,
            updated_at: now,
        });
    });
    return { registered: true, platform: registration.platform };
}
async function handleCustomerPushTokenRemoval(req, payload) {
    requireCustomerFeature('customerPushEnabled');
    const registration = parseCustomerPushToken(payload);
    const account = await requireBoundCustomerAccount(req);
    await customerPushTokenRef(account.firebaseUid, registration.token).delete();
    return { removed: true, platform: registration.platform };
}
function parseCustomerPushToken(payload) {
    try {
        return (0, customer_push_tokens_js_1.normalizeCustomerPushToken)(payload);
    }
    catch {
        throw new CustomerCoreError(400, 'customer_push_token_invalid', 'platform and token must be a valid FCM registration.');
    }
}
async function handleCustomerNotificationsRequest(req) {
    requireCustomerFeature('customerAppEnabled');
    const account = await requireBoundCustomerAccount(req);
    const flags = (0, customer_feature_flags_js_1.resolveCustomerFeatureFlags)(process.env);
    return {
        preferences: customerPreferencesFromAccount(account.accountData),
        push: {
            enabled: flags.customerPushEnabled,
            delivery: 'not_configured',
        },
        deep_links: {
            enabled: flags.customerDeepLinksEnabled,
            contract_path: '/customer/deep-links',
        },
    };
}
async function handleCustomerDeepLinksRequest(req) {
    requireCustomerFeature('customerDeepLinksEnabled');
    await requireBoundCustomerAccount(req);
    return {
        routes: [
            '/customer/home',
            '/customer/rewards',
            '/customer/activity',
            '/customer/businesses',
            '/customer/profile',
        ],
        parameterized_routes: [
            '/customer/business/:businessId',
            '/customer/redeem/:rewardId',
        ],
    };
}
async function handleCustomerAnalyticsEventRequest(req, payload) {
    requireCustomerFeature('customerAppEnabled');
    if (Object.keys(payload).some((key) => key !== 'event_type')) {
        throw new CustomerCoreError(400, 'customer_event_invalid', 'Only event_type is accepted for customer analytics.');
    }
    const eventType = requirePayloadString(payload, 'event_type');
    const allowedEventTypes = new Set([
        'CUSTOMER_HOME_OPENED',
        'CUSTOMER_REWARD_VIEWED',
        'CUSTOMER_QR_VIEWED',
        'CUSTOMER_DEEP_LINK_OPENED',
    ]);
    if (!allowedEventTypes.has(eventType)) {
        throw new CustomerCoreError(400, 'customer_event_invalid', 'Unsupported customer analytics event.');
    }
    const account = await requireBoundCustomerAccount(req);
    const eventId = `cae_${(0, crypto_1.randomUUID)()}`;
    await admin.firestore().collection(CUSTOMER_ANALYTICS_EVENT_COLLECTION).doc(eventId).set({
        id: eventId,
        firebase_uid: account.firebaseUid,
        event_type: eventType,
        occurred_at: Date.now(),
    });
    return { accepted: true };
}
async function ensureCustomerQrSubject(account) {
    return admin.firestore().runTransaction(async (transaction) => {
        const accountRef = customerAccountRef(account.firebaseUid);
        const snapshot = await transaction.get(accountRef);
        const data = snapshotDataRecord(snapshot);
        if (!snapshot.exists ||
            maybePayloadString(data, 'canonical_customer_id', 'canonicalCustomerId') !==
                account.canonicalCustomerId ||
            maybePayloadString(data, 'status') !== 'ACTIVE') {
            throw new CustomerCoreError(403, 'customer_account_inactive', 'Customer account is not active.');
        }
        const existingSubject = maybePayloadString(data, 'qr_subject');
        if (existingSubject && /^[A-Za-z0-9_-]{16,128}$/.test(existingSubject)) {
            return existingSubject;
        }
        const subject = (0, crypto_1.randomBytes)(24).toString('base64url');
        transaction.set(accountRef, {
            qr_subject: subject,
            qr_subject_created_at: Date.now(),
            updated_at: Date.now(),
        }, { merge: true });
        return subject;
    });
}
async function handleCustomerQrRequest(req) {
    requireCustomerFeature('customerQrEnabled');
    const account = await requireBoundCustomerAccount(req);
    const now = Date.now();
    const expiresAt = now + CUSTOMER_QR_TOKEN_TTL_MS;
    return {
        token: (0, customer_qr_js_1.createCustomerQrToken)({
            subject: await ensureCustomerQrSubject(account),
            issuedAt: now,
            expiresAt,
            secret: requireCustomerCoreSecret(),
        }),
        expires_at: expiresAt,
        format: 'cq1',
    };
}
async function handleCustomerRedemptionRequest(req, payload) {
    requireCustomerFeature('customerRedemptionEnabled');
    const allowedKeys = new Set(['reward_id', 'idempotency_key']);
    if (Object.keys(payload).some((key) => !allowedKeys.has(key)) ||
        Object.keys(payload).length !== 2) {
        throw new CustomerCoreError(400, 'customer_redemption_invalid', 'reward_id and idempotency_key are required.');
    }
    const rewardId = requirePayloadString(payload, 'reward_id');
    const idempotencyKey = requirePayloadString(payload, 'idempotency_key');
    if (!isSafeFirestoreDocumentId(rewardId)) {
        throw new CustomerCoreError(400, 'customer_redemption_invalid', 'Invalid reward_id.');
    }
    if (!/^[A-Za-z0-9_-]{8,200}$/.test(idempotencyKey)) {
        throw new CustomerCoreError(400, 'loyalty_idempotency_key_invalid', 'idempotency_key must be an opaque client operation identifier.');
    }
    const account = await requireBoundCustomerAccount(req);
    const locators = await listCustomerRelationshipLocators(account.canonicalCustomerId);
    const replayCandidates = await Promise.all(locators.map(async (locator) => {
        const relationship = await requireCustomerBusinessRelationship(account, locator.merchantId);
        const redemptionId = buildDeterministicRedemptionId(relationship.merchantId, idempotencyKey);
        const redemptionSnapshot = await businessRedemptionsCollectionRef(relationship.merchantId).doc(redemptionId).get();
        if (!redemptionSnapshot.exists)
            return null;
        const redemption = snapshotDataRecord(redemptionSnapshot);
        if (maybePayloadString(redemption, 'customer_id', 'customerId') !==
            relationship.customerId ||
            maybePayloadString(redemption, 'reward_id', 'rewardId') !== rewardId ||
            maybePayloadString(redemption, 'idempotency_key', 'idempotencyKey') !==
                idempotencyKey) {
            throw new CustomerCoreError(409, 'loyalty_redemption_idempotency_conflict', 'The supplied idempotency_key was already used for a different redemption request.', {
                merchant_id: relationship.merchantId,
                redemption_id: redemptionId,
            });
        }
        const ledgerEntryId = buildDeterministicLoyaltyLedgerEntryId('REDEMPTION', redemptionId);
        const [ledgerSnapshot, ledgerQuerySnapshot] = await Promise.all([
            loyaltyLedgerDocumentRef(relationship.merchantId, ledgerEntryId).get(),
            boundedCustomerLedgerQuery(relationship.merchantId, relationship.customerId).get(),
        ]);
        if (!ledgerSnapshot.exists) {
            throw new CustomerCoreError(409, 'loyalty_redemption_replay_inconsistent', 'The existing redemption is missing its confirmed ledger entry.');
        }
        assertLedgerQueryIsBounded(ledgerQuerySnapshot, relationship.merchantId, relationship.customerId);
        const projection = computeCustomerProjectionFromLedgerEntries(ledgerQuerySnapshot.docs.map((document) => loyaltyLedgerEntryFromData(snapshotDataRecord(document))));
        return {
            business_id: relationship.merchantId,
            redemption_id: redemptionId,
            reward_id: rewardId,
            points_spent: pickNumber(redemption, 'confirmed_points_spent') ??
                pickNumber(redemption, 'points_spent'),
            confirmed_points: projection.confirmedPoints,
            redemption_code: maybePayloadString(redemption, 'redemption_code'),
            redeemed_at: pickNumber(redemption, 'redeemed_at'),
            idempotent_replay: true,
        };
    }));
    const existingReplays = replayCandidates.filter((candidate) => candidate != null);
    if (existingReplays.length > 1) {
        throw new CustomerCoreError(409, 'customer_redemption_replay_ambiguous', 'The redemption replay is ambiguous across linked businesses.');
    }
    if (existingReplays.length === 1) {
        return existingReplays[0];
    }
    const matches = await Promise.all(locators.map(async (locator) => {
        const relationship = await requireCustomerBusinessRelationship(account, locator.merchantId);
        const reward = await businessRewardsCollectionRef(relationship.merchantId)
            .doc(rewardId)
            .get();
        return reward.exists ? relationship : null;
    }));
    const authorizedBusinesses = matches.filter((relationship) => relationship != null);
    if (authorizedBusinesses.length !== 1) {
        throw new CustomerCoreError(authorizedBusinesses.length === 0 ? 404 : 409, authorizedBusinesses.length === 0
            ? 'customer_reward_not_found'
            : 'customer_reward_ambiguous', authorizedBusinesses.length === 0
            ? 'Reward is not available to the authenticated customer.'
            : 'Reward id is ambiguous across linked businesses.');
    }
    const relationship = authorizedBusinesses[0];
    const result = await handleAssistedLoyaltyRedemptionRequest(req, { reward_id: rewardId, idempotency_key: idempotencyKey }, {
        merchantId: relationship.merchantId,
        customerId: relationship.customerId,
        redemptionCode: `r1_${(0, crypto_1.randomBytes)(18).toString('base64url')}`,
    });
    const redemption = result.redemption;
    return {
        business_id: relationship.merchantId,
        redemption_id: result.redemption_id,
        reward_id: rewardId,
        points_spent: pickNumber(redemption, 'confirmed_points_spent') ??
            pickNumber(redemption, 'points_spent'),
        confirmed_points: result.confirmed_points,
        redemption_code: maybePayloadString(redemption, 'redemption_code'),
        redeemed_at: pickNumber(redemption, 'redeemed_at'),
        idempotent_replay: result.idempotent_replay === true,
    };
}
async function handleMerchantCustomerQrResolveRequest(req, payload) {
    requireCustomerFeature('customerQrEnabled');
    if (!req.merchantId || !(await requestCanAccessMerchant(req, req.merchantId))) {
        throw new CustomerCoreError(403, 'merchant_access_denied', 'Merchant access is required.');
    }
    if (Object.keys(payload).length !== 1 || typeof payload.token !== 'string') {
        throw new CustomerCoreError(400, 'customer_qr_invalid', 'A customer QR token is required.');
    }
    const verified = (0, customer_qr_js_1.verifyCustomerQrToken)({
        token: payload.token,
        secret: requireCustomerCoreSecret(),
        now: Date.now(),
    });
    if (!verified) {
        throw new CustomerCoreError(400, 'customer_qr_invalid', 'Customer QR token is invalid or expired.');
    }
    const accounts = await admin.firestore()
        .collection(CUSTOMER_ACCOUNT_COLLECTION)
        .where('qr_subject', '==', verified.subject)
        .limit(2)
        .get();
    if (accounts.size !== 1) {
        throw new CustomerCoreError(404, 'customer_qr_not_found', 'Customer QR account was not found.');
    }
    const accountData = snapshotDataRecord(accounts.docs[0]);
    const canonicalCustomerId = maybePayloadString(accountData, 'canonical_customer_id');
    if (maybePayloadString(accountData, 'status') !== 'ACTIVE' ||
        !canonicalCustomerId) {
        throw new CustomerCoreError(404, 'customer_qr_not_found', 'Customer QR account was not found.');
    }
    const account = {
        firebaseUid: maybePayloadString(accountData, 'firebase_uid') ?? '',
        canonicalCustomerId,
        accountData,
    };
    const relationship = await requireCustomerBusinessRelationship(account, req.merchantId);
    return {
        business_id: relationship.merchantId,
        customer: {
            customer_id: relationship.customerId,
            name: maybePayloadString(relationship.customerData, 'name'),
            phone: maybePayloadString(relationship.customerData, 'phone'),
        },
        qr_expires_at: verified.expiresAt,
    };
}
async function findMatchingBusinessCustomers(merchantId, rawPhone, phoneE164) {
    const candidates = buildPhoneSearchCandidates(rawPhone, phoneE164);
    const customersRef = admin
        .firestore()
        .collection('businesses')
        .doc(merchantId)
        .collection('customers');
    const matches = new Map();
    for (const candidate of candidates) {
        const snapshot = await customersRef.where('phone', '==', candidate).limit(25).get();
        for (const doc of snapshot.docs) {
            const data = snapshotDataRecord(doc);
            const candidatePhoneE164 = tryNormalizeMozambiquePhoneToE164(maybePayloadString(data, 'phone'));
            if (candidatePhoneE164 === phoneE164) {
                matches.set(doc.id, doc);
            }
        }
    }
    return [...matches.values()];
}
async function handleBusinessCustomerLinkRequest(_req, merchantId, payload) {
    const customerId = maybePayloadString(payload, 'customer_id', 'customerId');
    const rawPhone = maybePayloadString(payload, 'phone');
    const customerName = maybePayloadString(payload, 'customer_name', 'customerName', 'name');
    const createCustomerIfMissing = maybePayloadBoolean(payload, 'create_customer_if_missing', 'createCustomerIfMissing') ??
        false;
    const dryRun = maybePayloadBoolean(payload, 'dry_run', 'dryRun') ?? false;
    if (!customerId && !rawPhone) {
        throw new CustomerCoreError(400, 'customer_locator_required', 'Provide customer_id or phone to link a business customer.');
    }
    return linkCanonicalCustomerToBusinessCustomer({
        merchantId,
        customerId,
        rawPhone,
        customerName,
        createCustomerIfMissing,
        dryRun,
    });
}
async function linkCanonicalCustomerToBusinessCustomer(options) {
    const { merchantId, rawPhone, customerName, createCustomerIfMissing, dryRun } = options;
    let customerId = options.customerId;
    let customerSnapshot = null;
    let customerData = {};
    let phoneE164 = rawPhone ? normalizeMozambiquePhoneToE164(rawPhone) : null;
    if (customerId) {
        customerSnapshot = await businessCustomerRef(merchantId, customerId).get();
        if (customerSnapshot.exists) {
            customerData = snapshotDataRecord(customerSnapshot);
        }
        else if (!createCustomerIfMissing) {
            throw new CustomerCoreError(404, 'business_customer_not_found', 'Business customer not found.', { merchant_id: merchantId, customer_id: customerId });
        }
    }
    const existingCustomerPhone = maybePayloadString(customerData, 'phone');
    const existingCustomerCanonicalId = maybePayloadString(customerData, 'canonical_customer_id', 'canonicalCustomerId');
    const existingCustomerPhoneE164 = tryNormalizeMozambiquePhoneToE164(existingCustomerPhone);
    if (phoneE164 == null && existingCustomerPhoneE164 != null) {
        phoneE164 = existingCustomerPhoneE164;
    }
    if (phoneE164 == null && existingCustomerCanonicalId) {
        const existingIdentity = await canonicalCustomerIdentityRef(existingCustomerCanonicalId).get();
        if (existingIdentity.exists) {
            const identityData = snapshotDataRecord(existingIdentity);
            phoneE164 = maybePayloadString(identityData, 'phone_e164');
        }
    }
    if (phoneE164 == null) {
        throw new CustomerCoreError(400, 'customer_phone_required', 'A valid Mozambique phone number is required to resolve canonical identity.', { merchant_id: merchantId, customer_id: customerId });
    }
    if (existingCustomerPhoneE164 != null &&
        existingCustomerPhoneE164 !== phoneE164) {
        throw new CustomerCoreError(409, 'business_customer_phone_conflict', 'Existing business customer phone does not match the requested canonical phone.', {
            merchant_id: merchantId,
            customer_id: customerId,
            existing_phone_e164: existingCustomerPhoneE164,
            requested_phone_e164: phoneE164,
        });
    }
    const canonicalIdentity = await findCanonicalCustomerIdentity(phoneE164);
    const canonicalCustomerId = canonicalIdentity?.canonicalCustomerId ?? buildCanonicalCustomerId(phoneE164);
    const phoneLast4 = last4(phoneE164);
    if (!customerId) {
        const matches = await findMatchingBusinessCustomers(merchantId, rawPhone ?? phoneE164, phoneE164);
        if (matches.length > 1) {
            throw new CustomerCoreError(409, 'business_customer_ambiguity', 'Multiple business customers share the same normalized phone. Resolve the duplicate customer records first.', {
                merchant_id: merchantId,
                canonical_customer_id: canonicalCustomerId,
                candidate_customer_ids: matches.map((doc) => doc.id),
            });
        }
        if (matches.length === 1) {
            customerSnapshot = matches[0];
            customerId = matches[0].id;
            customerData = snapshotDataRecord(matches[0]);
        }
        else if (createCustomerIfMissing) {
            customerId = buildDefaultBusinessCustomerId(canonicalCustomerId);
        }
        else {
            throw new CustomerCoreError(404, 'business_customer_not_found_by_phone', 'No business customer with that phone was found. Pass customer_id or enable create_customer_if_missing.', {
                merchant_id: merchantId,
                canonical_customer_id: canonicalCustomerId,
            });
        }
    }
    if (!customerId) {
        throw new CustomerCoreError(500, 'customer_core_resolution_failed', 'Unable to resolve business customer target.');
    }
    const idempotentExistingLink = existingCustomerCanonicalId != null &&
        existingCustomerCanonicalId === canonicalCustomerId;
    if (!idempotentExistingLink) {
        const duplicates = await findMatchingBusinessCustomers(merchantId, rawPhone ?? existingCustomerPhone ?? phoneE164, phoneE164);
        const duplicateIds = duplicates
            .map((doc) => doc.id)
            .filter((id) => id !== customerId);
        if (duplicateIds.length > 0) {
            throw new CustomerCoreError(409, 'business_customer_ambiguity', 'Multiple business customers map to the same normalized phone. The backend will not auto-merge verified conflicts.', {
                merchant_id: merchantId,
                customer_id: customerId,
                canonical_customer_id: canonicalCustomerId,
                conflicting_customer_ids: duplicateIds,
            });
        }
    }
    if (!customerSnapshot) {
        customerSnapshot = await businessCustomerRef(merchantId, customerId).get();
        customerData = customerSnapshot.exists ? snapshotDataRecord(customerSnapshot) : {};
    }
    if (!customerSnapshot.exists && !createCustomerIfMissing) {
        throw new CustomerCoreError(404, 'business_customer_not_found', 'Business customer not found.', { merchant_id: merchantId, customer_id: customerId });
    }
    if (!customerSnapshot.exists && (!customerName || customerName.trim().length === 0)) {
        throw new CustomerCoreError(400, 'customer_name_required', 'customer_name is required when creating a missing business customer.', { merchant_id: merchantId, customer_id: customerId });
    }
    if (dryRun) {
        const [customerLinkSnapshot, canonicalLinkSnapshot] = await Promise.all([
            businessCustomerLinkRef(merchantId, customerId).get(),
            canonicalIdentityBusinessLinkRef(merchantId, canonicalCustomerId).get(),
        ]);
        return {
            merchant_id: merchantId,
            customer_id: customerId,
            canonical_customer_id: canonicalCustomerId,
            phone_e164: phoneE164,
            phone_last4: phoneLast4,
            customer_created: !customerSnapshot.exists,
            identity_created: canonicalIdentity == null,
            link_created: !customerLinkSnapshot.exists ||
                !canonicalLinkSnapshot.exists ||
                existingCustomerCanonicalId !== canonicalCustomerId,
            customer_path: `businesses/${merchantId}/customers/${customerId}`,
            dry_run: true,
        };
    }
    const phoneLocal = normalizeMozambiquePhoneToLocal(phoneE164);
    const now = Date.now();
    const result = await admin.firestore().runTransaction(async (transaction) => {
        const currentCustomerRef = businessCustomerRef(merchantId, customerId);
        const identityRef = canonicalCustomerIdentityRef(canonicalCustomerId);
        const currentCustomerLinkRef = businessCustomerLinkRef(merchantId, customerId);
        const currentCanonicalLinkRef = canonicalIdentityBusinessLinkRef(merchantId, canonicalCustomerId);
        const linkedEvent = buildDomainEvent({
            eventType: 'CUSTOMER_LINKED',
            merchantId,
            canonicalCustomerId,
            businessCustomerId: customerId,
            sourceType: 'customer_link',
            sourceId: customerId,
            occurredAt: now,
            recordedAt: now,
            payload: {
                customer_created: !customerSnapshot?.exists,
                phone_last4: phoneLast4,
            },
        });
        const createdEvent = buildDomainEvent({
            eventType: 'CUSTOMER_CREATED',
            merchantId,
            canonicalCustomerId,
            businessCustomerId: customerId,
            sourceType: 'customer_link',
            sourceId: customerId,
            occurredAt: now,
            recordedAt: now,
            payload: {
                customer_created: true,
                phone_last4: phoneLast4,
            },
        });
        const linkedEventRef = domainEventCollectionRef(merchantId).doc(linkedEvent.event_id);
        const createdEventRef = domainEventCollectionRef(merchantId).doc(createdEvent.event_id);
        const [identitySnapshot, currentCustomerSnapshot, currentCustomerLinkSnapshot, currentCanonicalLinkSnapshot, linkedEventSnapshot, createdEventSnapshot,] = await Promise.all([
            transaction.get(identityRef),
            transaction.get(currentCustomerRef),
            transaction.get(currentCustomerLinkRef),
            transaction.get(currentCanonicalLinkRef),
            transaction.get(linkedEventRef),
            transaction.get(createdEventRef),
        ]);
        const currentCustomerData = snapshotDataRecord(currentCustomerSnapshot);
        const currentCanonicalCustomerId = maybePayloadString(currentCustomerData, 'canonical_customer_id', 'canonicalCustomerId');
        if (currentCanonicalCustomerId != null &&
            currentCanonicalCustomerId !== canonicalCustomerId) {
            throw new CustomerCoreError(409, 'business_customer_link_conflict', 'Business customer is already linked to a different canonical customer.', {
                merchant_id: merchantId,
                customer_id: customerId,
                existing_canonical_customer_id: currentCanonicalCustomerId,
                requested_canonical_customer_id: canonicalCustomerId,
            });
        }
        const reverseLinkData = snapshotDataRecord(currentCanonicalLinkSnapshot);
        const reverseLinkedCustomerId = maybePayloadString(reverseLinkData, 'business_customer_id', 'customer_id');
        if (currentCanonicalLinkSnapshot.exists &&
            reverseLinkedCustomerId != null &&
            reverseLinkedCustomerId !== customerId) {
            throw new CustomerCoreError(409, 'canonical_customer_conflict', 'Canonical customer is already linked to a different business customer for this business.', {
                merchant_id: merchantId,
                canonical_customer_id: canonicalCustomerId,
                existing_customer_id: reverseLinkedCustomerId,
                requested_customer_id: customerId,
            });
        }
        const forwardLinkData = snapshotDataRecord(currentCustomerLinkSnapshot);
        const forwardCanonicalCustomerId = maybePayloadString(forwardLinkData, 'canonical_customer_id', 'canonicalCustomerId');
        if (currentCustomerLinkSnapshot.exists &&
            forwardCanonicalCustomerId != null &&
            forwardCanonicalCustomerId !== canonicalCustomerId) {
            throw new CustomerCoreError(409, 'business_customer_link_conflict', 'Business customer link record points to a different canonical customer.', {
                merchant_id: merchantId,
                customer_id: customerId,
                existing_canonical_customer_id: forwardCanonicalCustomerId,
                requested_canonical_customer_id: canonicalCustomerId,
            });
        }
        const currentCustomerPhone = maybePayloadString(currentCustomerData, 'phone');
        const currentCustomerPhoneE164 = tryNormalizeMozambiquePhoneToE164(currentCustomerPhone);
        if (currentCustomerPhone != null &&
            currentCustomerPhoneE164 != null &&
            currentCustomerPhoneE164 !== phoneE164) {
            throw new CustomerCoreError(409, 'business_customer_phone_conflict', 'Existing business customer phone does not match the requested canonical phone.', {
                merchant_id: merchantId,
                customer_id: customerId,
                existing_phone_e164: currentCustomerPhoneE164,
                requested_phone_e164: phoneE164,
            });
        }
        if (!identitySnapshot.exists) {
            transaction.set(identityRef, {
                id: canonicalCustomerId,
                lookup_key: canonicalCustomerId,
                phone_e164: phoneE164,
                phone_last4: phoneLast4,
                country_code: 'MZ',
                identity_version: 1,
                created_at: now,
                updated_at: now,
                created_by_merchant_id: merchantId,
                last_linked_merchant_id: merchantId,
                last_linked_at: now,
            });
        }
        const customerPatch = {
            id: customerId,
            merchant_id: merchantId,
            canonical_customer_id: canonicalCustomerId,
            canonical_lookup_key: canonicalCustomerId,
            canonical_phone_e164: phoneE164,
            canonical_phone_last4: phoneLast4,
            canonical_linked_at: now,
            canonical_link_status: 'LINKED',
            canonical_link_error_code: admin.firestore.FieldValue.delete(),
            canonical_link_error_message: admin.firestore.FieldValue.delete(),
            canonical_link_error_at: admin.firestore.FieldValue.delete(),
            canonical_identity_version: 1,
            updated_at: now,
        };
        setIfMissingString(customerPatch, currentCustomerData, 'account_state', 'UNCLAIMED');
        setIfMissingString(customerPatch, currentCustomerData, 'relationship_status', 'ACTIVE');
        setIfMissingString(customerPatch, currentCustomerData, 'lifecycle_stage', 'NEW');
        setIfMissingString(customerPatch, currentCustomerData, 'retention_status', 'HEALTHY');
        setIfMissingNumber(customerPatch, currentCustomerData, 'total_visits', 0);
        setIfMissingNumber(customerPatch, currentCustomerData, 'total_spent', 0);
        setIfMissingNumber(customerPatch, currentCustomerData, 'average_spend', 0);
        setIfMissingNumber(customerPatch, currentCustomerData, 'schema_version', 1);
        setIfMissingString(customerPatch, currentCustomerData, 'marketing_consent_status', 'UNKNOWN');
        setIfMissingString(customerPatch, currentCustomerData, 'whatsapp_consent_status', 'UNKNOWN');
        if (!currentCustomerSnapshot.exists) {
            customerPatch.name = customerName;
            customerPatch.phone = phoneLocal;
            customerPatch.total_points = 0;
            customerPatch.created_at = now;
        }
        else {
            if (!currentCustomerPhone) {
                customerPatch.phone = phoneLocal;
            }
            if (!maybePayloadString(currentCustomerData, 'name') && customerName) {
                customerPatch.name = customerName;
            }
            if (pickNumber(currentCustomerData, 'created_at') == null) {
                customerPatch.created_at = now;
            }
            if (pickNumber(currentCustomerData, 'total_points') == null) {
                customerPatch.total_points = 0;
            }
        }
        transaction.set(currentCustomerRef, customerPatch, { merge: true });
        const linkPayload = {
            merchant_id: merchantId,
            business_customer_id: customerId,
            canonical_customer_id: canonicalCustomerId,
            phone_e164: phoneE164,
            phone_last4: phoneLast4,
            updated_at: now,
            ...(currentCustomerLinkSnapshot.exists ? {} : { created_at: now }),
        };
        transaction.set(currentCustomerLinkRef, linkPayload, { merge: true });
        transaction.set(currentCanonicalLinkRef, linkPayload, { merge: true });
        const customerEvent = !currentCustomerSnapshot.exists || createdEventSnapshot.exists
            ? createdEvent
            : linkedEvent;
        const customerEventRef = customerEvent.event_type === 'CUSTOMER_CREATED'
            ? createdEventRef
            : linkedEventRef;
        const customerEventSnapshot = customerEvent.event_type === 'CUSTOMER_CREATED'
            ? createdEventSnapshot
            : linkedEventSnapshot;
        if (!customerEventSnapshot.exists) {
            transaction.set(customerEventRef, {
                ...customerEvent,
                occurred_at: pickNumber(currentCustomerData, 'canonical_linked_at') ?? now,
                payload: {
                    ...customerEvent.payload,
                    customer_created: !currentCustomerSnapshot.exists,
                },
            });
        }
        return {
            merchant_id: merchantId,
            customer_id: customerId,
            canonical_customer_id: canonicalCustomerId,
            phone_e164: phoneE164,
            phone_last4: phoneLast4,
            customer_created: !currentCustomerSnapshot.exists,
            identity_created: !identitySnapshot.exists,
            link_created: !currentCustomerLinkSnapshot.exists ||
                !currentCanonicalLinkSnapshot.exists ||
                currentCanonicalCustomerId !== canonicalCustomerId,
            domain_event_id: customerEvent.event_id,
            domain_event_type: customerEvent.event_type,
            customer_path: `businesses/${merchantId}/customers/${customerId}`,
        };
    });
    const classification = await updateCustomerClassification({
        merchantId,
        customerId: result.customer_id,
        sourceType: 'customer_link',
        sourceId: result.customer_id,
        causationId: result.domain_event_id ?? null,
        occurredAt: now,
        dryRun: false,
    });
    return { ...result, classification };
}
async function handleCustomerCoreBackfillRequest(req, body) {
    const payload = requireBodyObject(body);
    const merchantId = await resolveCustomerCoreMerchantId(req, payload);
    const limit = clampLimit(payload.limit, 50, 200);
    const startAfterCustomerId = maybePayloadString(payload, 'start_after_customer_id', 'startAfterCustomerId');
    const dryRun = maybePayloadBoolean(payload, 'dry_run', 'dryRun') ?? false;
    let query = admin
        .firestore()
        .collection('businesses')
        .doc(merchantId)
        .collection('customers')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);
    if (startAfterCustomerId) {
        query = query.startAfter(startAfterCustomerId);
    }
    const snapshot = await query.get();
    const results = [];
    let linkedCount = 0;
    let skippedCount = 0;
    for (const doc of snapshot.docs) {
        const data = snapshotDataRecord(doc);
        try {
            const linkResult = await linkCanonicalCustomerToBusinessCustomer({
                merchantId,
                customerId: doc.id,
                rawPhone: maybePayloadString(data, 'phone'),
                customerName: maybePayloadString(data, 'name'),
                createCustomerIfMissing: false,
                dryRun,
            });
            const status = dryRun
                ? (linkResult.link_created || linkResult.identity_created
                    ? 'dry_run'
                    : 'already_linked')
                : (linkResult.link_created ? 'linked' : 'already_linked');
            if (status === 'linked') {
                linkedCount += 1;
            }
            results.push({
                customer_id: doc.id,
                status,
                canonical_customer_id: linkResult.canonical_customer_id,
                phone_e164: linkResult.phone_e164,
                message: status === 'already_linked'
                    ? 'Canonical link already present.'
                    : dryRun
                        ? 'Canonical link would be applied.'
                        : 'Canonical link applied.',
            });
        }
        catch (error) {
            skippedCount += 1;
            if (error instanceof CustomerCoreError) {
                results.push({
                    customer_id: doc.id,
                    status: error.status >= 500 ? 'error' : 'skipped',
                    code: error.code,
                    message: error.message,
                    ...(error.details ? { details: error.details } : {}),
                });
                continue;
            }
            throw error;
        }
    }
    const nextCursor = snapshot.docs.length === limit && snapshot.docs.length > 0
        ? snapshot.docs[snapshot.docs.length - 1].id
        : null;
    return {
        merchant_id: merchantId,
        dry_run: dryRun,
        processed: snapshot.docs.length,
        linked: linkedCount,
        skipped: skippedCount,
        has_more: nextCursor != null,
        next_cursor: nextCursor,
        results,
    };
}
function businessDocumentRef(merchantId) {
    return admin.firestore().collection('businesses').doc(merchantId);
}
function businessSalesCollectionRef(merchantId) {
    return businessDocumentRef(merchantId).collection('sales');
}
function businessRewardsCollectionRef(merchantId) {
    return businessDocumentRef(merchantId).collection('rewards');
}
function businessRedemptionsCollectionRef(merchantId) {
    return businessDocumentRef(merchantId).collection('redemptions');
}
function loyaltyLedgerCollectionRef(merchantId) {
    return businessDocumentRef(merchantId).collection(LOYALTY_LEDGER_COLLECTION);
}
function loyaltyLedgerDocumentRef(merchantId, entryId) {
    return loyaltyLedgerCollectionRef(merchantId).doc(entryId);
}
function boundedCustomerLedgerQuery(merchantId, customerId) {
    return loyaltyLedgerCollectionRef(merchantId)
        .where('customer_id', '==', customerId)
        .limit(MAX_LEDGER_ENTRIES_PER_CUSTOMER + 1);
}
function assertLedgerQueryIsBounded(snapshot, merchantId, customerId) {
    if (snapshot.size > MAX_LEDGER_ENTRIES_PER_CUSTOMER) {
        throw new CustomerCoreError(409, 'loyalty_ledger_projection_limit_exceeded', 'Customer ledger is too large for synchronous projection; use a dedicated projection job.', {
            merchant_id: merchantId,
            customer_id: customerId,
            maximum_entries: MAX_LEDGER_ENTRIES_PER_CUSTOMER,
        });
    }
}
function domainEventCollectionRef(merchantId) {
    return businessDocumentRef(merchantId).collection(DOMAIN_EVENT_COLLECTION);
}
function retentionPolicyDocumentRef(merchantId, version) {
    return businessDocumentRef(merchantId)
        .collection(RETENTION_POLICY_COLLECTION)
        .doc(`v${version}`);
}
function customerTransitionDocumentRef(merchantId, transitionId) {
    return businessDocumentRef(merchantId)
        .collection(CUSTOMER_TRANSITION_COLLECTION)
        .doc(transitionId);
}
function customerRecommendationDocumentRef(merchantId, customerId) {
    return businessDocumentRef(merchantId)
        .collection(CUSTOMER_RECOMMENDATION_COLLECTION)
        .doc(customerId);
}
function deterministicDocumentId(prefix, parts) {
    const digest = (0, crypto_1.createHash)('sha256')
        .update(parts.join('\u001f'))
        .digest('hex')
        .substring(0, 40);
    return `${prefix}_${digest}`;
}
function buildDomainEvent(params) {
    const eventId = deterministicDocumentId('evt', [
        params.merchantId,
        params.eventType,
        params.sourceType,
        params.sourceId,
    ]);
    return {
        event_id: eventId,
        event_type: params.eventType,
        schema_version: DOMAIN_EVENT_SCHEMA_VERSION,
        merchant_id: params.merchantId,
        canonical_customer_id: params.canonicalCustomerId,
        business_customer_id: params.businessCustomerId,
        source: {
            type: params.sourceType,
            id: params.sourceId,
        },
        correlation_id: params.correlationId ?? eventId,
        causation_id: params.causationId ?? null,
        occurred_at: params.occurredAt,
        recorded_at: params.recordedAt,
        payload: params.payload,
    };
}
function buildDeterministicLoyaltyLedgerEntryId(entryType, sourceId) {
    return `${entryType.toLowerCase()}_${sourceId}`;
}
function buildDeterministicRedemptionId(merchantId, idempotencyKey) {
    const secret = requireCustomerCoreSecret();
    return `red_${(0, crypto_1.createHmac)('sha256', secret)
        .update(`loyalty-redemption-v1:${merchantId}:${idempotencyKey}`)
        .digest('hex')
        .substring(0, 40)}`;
}
function positiveIntegerOrDefault(value, fallback) {
    const parsed = parseNumber(value);
    if (parsed == null || parsed <= 0) {
        return fallback;
    }
    return Math.floor(parsed);
}
function getBusinessLoyaltyConfig(data) {
    const loyaltyConfigRaw = data.loyalty_config;
    const loyaltyConfig = loyaltyConfigRaw != null && typeof loyaltyConfigRaw === 'object'
        ? loyaltyConfigRaw
        : {};
    return {
        pointsPerMzn: positiveIntegerOrDefault(loyaltyConfig.points_per_mzn, DEFAULT_LOYALTY_POINTS_PER_MZN),
        configVersion: positiveIntegerOrDefault(loyaltyConfig.version, DEFAULT_LOYALTY_CONFIG_VERSION),
    };
}
function calculateConfirmedSalePoints(amount, pointsPerMzn) {
    return Math.floor(amount / pointsPerMzn);
}
function loyaltyLedgerEntryFromData(data) {
    return {
        id: maybePayloadString(data, 'id') ?? '',
        merchant_id: maybePayloadString(data, 'merchant_id') ?? '',
        customer_id: maybePayloadString(data, 'customer_id') ?? '',
        entry_type: (maybePayloadString(data, 'entry_type') ?? 'SALE'),
        source_type: (maybePayloadString(data, 'source_type') ?? 'sale'),
        source_id: maybePayloadString(data, 'source_id') ?? '',
        occurred_at: pickNumber(data, 'occurred_at') ?? 0,
        points_delta: pickNumber(data, 'points_delta') ?? 0,
        policy_version: pickNumber(data, 'policy_version') ?? DEFAULT_LOYALTY_CONFIG_VERSION,
        balance_after: pickNumber(data, 'balance_after') ?? 0,
        canonical_customer_id: maybePayloadString(data, 'canonical_customer_id') ?? undefined,
        amount_mzn: pickNumber(data, 'amount_mzn') ?? 0,
        reward_id: maybePayloadString(data, 'reward_id'),
        idempotency_key: maybePayloadString(data, 'idempotency_key'),
        created_at: pickNumber(data, 'created_at') ?? 0,
        updated_at: pickNumber(data, 'updated_at') ?? pickNumber(data, 'created_at') ?? 0,
    };
}
function loyaltyLedgerEntryHasDrift(existingData, expected) {
    const comparableKeys = [
        'merchant_id',
        'customer_id',
        'entry_type',
        'source_type',
        'source_id',
        'occurred_at',
        'points_delta',
        'policy_version',
        'balance_after',
        'amount_mzn',
        'reward_id',
        'idempotency_key',
    ];
    return comparableKeys.some((key) => !valuesEqual(existingData[key], expected[key]));
}
function computeCustomerProjectionFromLedgerEntries(entries) {
    const balancedEntries = computeLedgerEntriesWithBalances(entries);
    const confirmedPoints = entries.reduce((sum, entry) => sum + entry.points_delta, 0);
    const saleEntries = balancedEntries
        .filter((entry) => entry.entry_type === 'SALE')
        .sort((left, right) => left.occurred_at - right.occurred_at);
    const totalVisits = saleEntries.length;
    const totalSpent = saleEntries.reduce((sum, entry) => sum + (entry.amount_mzn ?? 0), 0);
    const firstVisitAt = totalVisits > 0 ? saleEntries[0].occurred_at : null;
    const lastVisitAt = totalVisits > 0
        ? saleEntries[totalVisits - 1].occurred_at
        : null;
    const averageSpend = totalVisits > 0 ? totalSpent / totalVisits : 0;
    const intervals = [];
    for (let index = 1; index < saleEntries.length; index += 1) {
        intervals.push(saleEntries[index].occurred_at - saleEntries[index - 1].occurred_at);
    }
    const averageVisitIntervalDays = intervals.length > 0
        ? Math.round(intervals.reduce((sum, value) => sum + value, 0) /
            intervals.length /
            (24 * 60 * 60 * 1000))
        : 0;
    const lastLedgerEntryAt = balancedEntries.reduce((latest, entry) => {
        if (latest == null || entry.occurred_at > latest) {
            return entry.occurred_at;
        }
        return latest;
    }, null);
    return {
        confirmedPoints,
        firstVisitAt,
        lastVisitAt,
        totalVisits,
        totalSpent,
        averageSpend,
        averageVisitIntervalDays,
        lastLedgerEntryAt,
    };
}
function computeLedgerEntriesWithBalances(entries) {
    const ordered = [...entries].sort((left, right) => {
        const byOccurredAt = left.occurred_at - right.occurred_at;
        if (byOccurredAt !== 0)
            return byOccurredAt;
        const byCreatedAt = left.created_at - right.created_at;
        if (byCreatedAt !== 0)
            return byCreatedAt;
        return left.id.localeCompare(right.id);
    });
    let runningBalance = 0;
    return ordered.map((entry) => {
        runningBalance += entry.points_delta;
        return {
            ...entry,
            balance_after: runningBalance,
        };
    });
}
function buildCustomerProjectionPatch(currentCustomerData, projection, now) {
    const patch = {
        confirmed_points: projection.confirmedPoints,
        total_points: projection.confirmedPoints,
        total_visits: projection.totalVisits,
        total_spent: projection.totalSpent,
        average_spend: projection.averageSpend,
        average_visit_interval_days: projection.averageVisitIntervalDays,
        loyalty_projection_version: LOYALTY_PROJECTION_VERSION,
        loyalty_projection_status: 'READY',
        loyalty_backfill_required: false,
        loyalty_last_reconciled_at: now,
        schema_version: pickNumber(currentCustomerData, 'schema_version') ?? 1,
        updated_at: now,
    };
    patch.first_visit_at = projection.firstVisitAt == null
        ? admin.firestore.FieldValue.delete()
        : projection.firstVisitAt;
    patch.last_visit_at = projection.lastVisitAt == null
        ? admin.firestore.FieldValue.delete()
        : projection.lastVisitAt;
    patch.loyalty_last_ledger_entry_at = projection.lastLedgerEntryAt == null
        ? admin.firestore.FieldValue.delete()
        : projection.lastLedgerEntryAt;
    setIfMissingString(patch, currentCustomerData, 'account_state', 'UNCLAIMED');
    setIfMissingString(patch, currentCustomerData, 'relationship_status', 'ACTIVE');
    setIfMissingString(patch, currentCustomerData, 'lifecycle_stage', 'NEW');
    setIfMissingString(patch, currentCustomerData, 'retention_status', 'HEALTHY');
    setIfMissingString(patch, currentCustomerData, 'marketing_consent_status', 'UNKNOWN');
    setIfMissingString(patch, currentCustomerData, 'whatsapp_consent_status', 'UNKNOWN');
    return patch;
}
async function resolveCanonicalCustomerForLoyalty(merchantId, customerId, customerData, dryRun) {
    const existingCanonicalCustomerId = maybePayloadString(customerData, 'canonical_customer_id', 'canonicalCustomerId');
    const rawPhone = maybePayloadString(customerData, 'phone');
    const canonicalPhoneE164 = maybePayloadString(customerData, 'canonical_phone_e164');
    if (existingCanonicalCustomerId && canonicalPhoneE164) {
        return {
            canonicalCustomerId: existingCanonicalCustomerId,
            phoneE164: canonicalPhoneE164,
        };
    }
    if (existingCanonicalCustomerId && rawPhone) {
        const phoneE164 = normalizeMozambiquePhoneToE164(rawPhone);
        if (buildCanonicalCustomerId(phoneE164) !== existingCanonicalCustomerId) {
            throw new CustomerCoreError(409, 'loyalty_canonical_conflict', 'Customer canonical identity does not match the stored phone number.', {
                merchant_id: merchantId,
                customer_id: customerId,
                canonical_customer_id: existingCanonicalCustomerId,
                phone_e164: phoneE164,
            });
        }
        return {
            canonicalCustomerId: existingCanonicalCustomerId,
            phoneE164,
        };
    }
    if (!rawPhone) {
        throw new CustomerCoreError(409, 'loyalty_customer_phone_missing', 'Customer phone is required before loyalty can be confirmed.', { merchant_id: merchantId, customer_id: customerId });
    }
    const result = await linkCanonicalCustomerToBusinessCustomer({
        merchantId,
        customerId,
        rawPhone,
        customerName: maybePayloadString(customerData, 'name'),
        createCustomerIfMissing: false,
        dryRun,
    });
    return {
        canonicalCustomerId: result.canonical_customer_id,
        phoneE164: result.phone_e164,
    };
}
async function requireCustomerCanonicalRelationship(merchantId, customerId) {
    const customerSnapshot = await businessCustomerRef(merchantId, customerId).get();
    if (!customerSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found.', { merchant_id: merchantId, customer_id: customerId });
    }
    const customerData = snapshotDataRecord(customerSnapshot);
    const canonicalCustomerId = maybePayloadString(customerData, 'canonical_customer_id', 'canonicalCustomerId');
    if (!canonicalCustomerId) {
        throw new CustomerCoreError(409, 'loyalty_canonical_link_required', 'Customer canonical relationship is missing. Run customer linking/backfill first.', { merchant_id: merchantId, customer_id: customerId });
    }
    const [forwardLinkSnapshot, reverseLinkSnapshot] = await Promise.all([
        businessCustomerLinkRef(merchantId, customerId).get(),
        canonicalIdentityBusinessLinkRef(merchantId, canonicalCustomerId).get(),
    ]);
    const forwardLinkData = snapshotDataRecord(forwardLinkSnapshot);
    const reverseLinkData = snapshotDataRecord(reverseLinkSnapshot);
    if (!forwardLinkSnapshot.exists ||
        maybePayloadString(forwardLinkData, 'canonical_customer_id') !== canonicalCustomerId ||
        !reverseLinkSnapshot.exists ||
        maybePayloadString(reverseLinkData, 'business_customer_id', 'customer_id') !== customerId) {
        throw new CustomerCoreError(409, 'loyalty_canonical_link_inconsistent', 'Customer canonical relationship is inconsistent. Run customer backfill to repair it.', {
            merchant_id: merchantId,
            customer_id: customerId,
            canonical_customer_id: canonicalCustomerId,
        });
    }
    return { customerData, canonicalCustomerId };
}
async function assertCustomerReadyForLiveSale(transaction, merchantId, customerId, saleId, customerData, derivedPoints) {
    const projectionVersion = pickNumber(customerData, 'loyalty_projection_version');
    if (projectionVersion === LOYALTY_PROJECTION_VERSION) {
        return;
    }
    const existingLedgerSnapshot = await transaction.get(loyaltyLedgerCollectionRef(merchantId).where('customer_id', '==', customerId).limit(1));
    if (!existingLedgerSnapshot.empty) {
        return;
    }
    const [salesSnapshot, redemptionsSnapshot] = await Promise.all([
        transaction.get(businessSalesCollectionRef(merchantId).where('customer_id', '==', customerId).limit(5)),
        transaction.get(businessRedemptionsCollectionRef(merchantId).where('customer_id', '==', customerId).limit(5)),
    ]);
    const otherSales = salesSnapshot.docs.filter((doc) => doc.id !== saleId);
    const legacyTotalPoints = pickNumber(customerData, 'total_points') ?? 0;
    const canBootstrapFromCurrentSale = otherSales.length === 0 &&
        redemptionsSnapshot.empty &&
        (legacyTotalPoints === 0 || legacyTotalPoints === derivedPoints);
    if (!canBootstrapFromCurrentSale) {
        throw new CustomerCoreError(409, 'loyalty_backfill_required', 'Existing customer loyalty history must be backfilled before live sale confirmation can continue.', {
            merchant_id: merchantId,
            customer_id: customerId,
        });
    }
}
function buildExpectedSaleLedgerEntry(params) {
    const amount = pickNumber(params.saleData, 'amount') ?? 0;
    const sourceCreatedAt = pickNumber(params.saleData, 'created_at') ?? params.now;
    return {
        id: buildDeterministicLoyaltyLedgerEntryId('SALE', params.saleId),
        merchant_id: params.merchantId,
        customer_id: params.customerId,
        entry_type: 'SALE',
        source_type: 'sale',
        source_id: params.saleId,
        occurred_at: sourceCreatedAt,
        points_delta: calculateConfirmedSalePoints(amount, params.businessConfig.pointsPerMzn),
        policy_version: params.businessConfig.configVersion,
        balance_after: 0,
        canonical_customer_id: params.canonicalCustomerId,
        amount_mzn: amount,
        reward_id: null,
        idempotency_key: null,
        created_at: params.createdAt,
        updated_at: params.now,
    };
}
function buildExpectedRedemptionLedgerEntry(params) {
    const pointsSpent = pickNumber(params.redemptionData, 'points_spent') ?? 0;
    const sourceCreatedAt = pickNumber(params.redemptionData, 'redeemed_at') ??
        pickNumber(params.redemptionData, 'created_at') ??
        params.now;
    return {
        id: buildDeterministicLoyaltyLedgerEntryId('REDEMPTION', params.redemptionId),
        merchant_id: params.merchantId,
        customer_id: params.customerId,
        entry_type: 'REDEMPTION',
        source_type: 'redemption',
        source_id: params.redemptionId,
        occurred_at: sourceCreatedAt,
        points_delta: -Math.abs(pointsSpent),
        policy_version: params.businessConfig.configVersion,
        balance_after: 0,
        canonical_customer_id: params.canonicalCustomerId,
        amount_mzn: 0,
        reward_id: maybePayloadString(params.redemptionData, 'reward_id', 'rewardId'),
        idempotency_key: maybePayloadString(params.redemptionData, 'idempotency_key', 'idempotencyKey'),
        created_at: params.createdAt,
        updated_at: params.now,
    };
}
function mergeLedgerEntriesForProjection(snapshot, expectedEntry, removeEntryId) {
    const byId = new Map();
    for (const doc of snapshot.docs) {
        byId.set(doc.id, loyaltyLedgerEntryFromData(snapshotDataRecord(doc)));
    }
    if (removeEntryId) {
        byId.delete(removeEntryId);
    }
    byId.set(expectedEntry.id, expectedEntry);
    return [...byId.values()];
}
async function updateCustomerProjectionFromLedger(transaction, merchantId, customerId, currentCustomerData, expectedEntry, removeEntryId) {
    const ledgerSnapshot = await transaction.get(boundedCustomerLedgerQuery(merchantId, customerId));
    assertLedgerQueryIsBounded(ledgerSnapshot, merchantId, customerId);
    const existingExpectedSnapshot = ledgerSnapshot.docs.find((doc) => doc.id === expectedEntry.id);
    const effectiveExpectedEntry = existingExpectedSnapshot
        ? loyaltyLedgerEntryFromData(snapshotDataRecord(existingExpectedSnapshot))
        : expectedEntry;
    const mergedEntries = mergeLedgerEntriesForProjection(ledgerSnapshot, effectiveExpectedEntry, removeEntryId);
    const balancedEntries = computeLedgerEntriesWithBalances(mergedEntries);
    const balancedExpectedEntry = balancedEntries.find((entry) => entry.id === expectedEntry.id) ??
        effectiveExpectedEntry;
    if (!existingExpectedSnapshot) {
        transaction.set(loyaltyLedgerDocumentRef(merchantId, balancedExpectedEntry.id), balancedExpectedEntry);
    }
    const projection = computeCustomerProjectionFromLedgerEntries(balancedEntries);
    transaction.set(businessCustomerRef(merchantId, customerId), buildCustomerProjectionPatch(currentCustomerData, projection, Date.now()), { merge: true });
    return { projection, balancedExpectedEntry };
}
async function resetCustomerProjectionFromExistingLedger(transaction, merchantId, customerId) {
    const customerSnapshot = await transaction.get(businessCustomerRef(merchantId, customerId));
    if (!customerSnapshot.exists) {
        return;
    }
    const currentCustomerData = snapshotDataRecord(customerSnapshot);
    const ledgerSnapshot = await transaction.get(boundedCustomerLedgerQuery(merchantId, customerId));
    assertLedgerQueryIsBounded(ledgerSnapshot, merchantId, customerId);
    const entries = ledgerSnapshot.docs.map((doc) => loyaltyLedgerEntryFromData(snapshotDataRecord(doc)));
    const projection = computeCustomerProjectionFromLedgerEntries(entries);
    transaction.set(businessCustomerRef(merchantId, customerId), buildCustomerProjectionPatch(currentCustomerData, projection, Date.now()), { merge: true });
}
async function applySaleToLoyaltyLedger(params) {
    const saleSnapshot = params.saleSnapshot ?? await businessSalesCollectionRef(params.merchantId).doc(params.saleId).get();
    if (!saleSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_sale_not_found', 'Sale document not found.', { merchant_id: params.merchantId, sale_id: params.saleId });
    }
    const saleData = snapshotDataRecord(saleSnapshot);
    const customerId = maybePayloadString(saleData, 'customer_id', 'customerId');
    const amount = pickNumber(saleData, 'amount');
    if (!customerId) {
        throw new CustomerCoreError(400, 'loyalty_sale_customer_missing', 'Sale customer_id is required.', { merchant_id: params.merchantId, sale_id: params.saleId });
    }
    if (amount == null || amount <= 0) {
        throw new CustomerCoreError(400, 'loyalty_sale_amount_invalid', 'Sale amount must be greater than zero.', { merchant_id: params.merchantId, sale_id: params.saleId });
    }
    const customerSnapshot = await businessCustomerRef(params.merchantId, customerId).get();
    if (!customerSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found for sale.', { merchant_id: params.merchantId, sale_id: params.saleId, customer_id: customerId });
    }
    const customerData = snapshotDataRecord(customerSnapshot);
    const canonical = await resolveCanonicalCustomerForLoyalty(params.merchantId, customerId, customerData, false);
    const now = Date.now();
    const result = await admin.firestore().runTransaction(async (transaction) => {
        const currentSaleSnapshot = await transaction.get(businessSalesCollectionRef(params.merchantId).doc(params.saleId));
        if (!currentSaleSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_sale_not_found', 'Sale document not found.', { merchant_id: params.merchantId, sale_id: params.saleId });
        }
        const currentSaleData = snapshotDataRecord(currentSaleSnapshot);
        const currentCustomerId = maybePayloadString(currentSaleData, 'customer_id', 'customerId') ?? customerId;
        const currentAmount = pickNumber(currentSaleData, 'amount');
        if (currentCustomerId !== customerId) {
            throw new CustomerCoreError(409, 'loyalty_sale_customer_changed', 'Sale customer changed during processing. Retry the operation.', { merchant_id: params.merchantId, sale_id: params.saleId });
        }
        if (currentAmount == null || currentAmount <= 0) {
            throw new CustomerCoreError(400, 'loyalty_sale_amount_invalid', 'Sale amount must be greater than zero.', { merchant_id: params.merchantId, sale_id: params.saleId });
        }
        const saleEventTypes = [
            'SALE_CONFIRMED',
            'FIRST_PURCHASE',
            'CUSTOMER_VISITED',
            'PURCHASE_COMPLETED',
            'POINTS_EARNED',
        ];
        const saleEventRefs = saleEventTypes.map((eventType) => domainEventCollectionRef(params.merchantId).doc(deterministicDocumentId('evt', [
            params.merchantId,
            eventType,
            'sale',
            params.saleId,
        ])));
        const [businessSnapshot, currentCustomerSnapshot, existingLedgerSnapshot, saleEventSnapshots,] = await Promise.all([
            transaction.get(businessDocumentRef(params.merchantId)),
            transaction.get(businessCustomerRef(params.merchantId, customerId)),
            transaction.get(loyaltyLedgerDocumentRef(params.merchantId, buildDeterministicLoyaltyLedgerEntryId('SALE', params.saleId))),
            Promise.all(saleEventRefs.map((eventRef) => transaction.get(eventRef))),
        ]);
        if (!businessSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_business_not_found', 'Business document not found.', { merchant_id: params.merchantId });
        }
        if (!currentCustomerSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found for sale.', { merchant_id: params.merchantId, sale_id: params.saleId, customer_id: customerId });
        }
        const currentCustomerData = snapshotDataRecord(currentCustomerSnapshot);
        const businessConfig = getBusinessLoyaltyConfig(snapshotDataRecord(businessSnapshot));
        const derivedPoints = calculateConfirmedSalePoints(currentAmount, businessConfig.pointsPerMzn);
        if (!params.allowLegacyBootstrap) {
            await assertCustomerReadyForLiveSale(transaction, params.merchantId, customerId, params.saleId, currentCustomerData, derivedPoints);
        }
        const existingLedgerData = existingLedgerSnapshot.exists
            ? snapshotDataRecord(existingLedgerSnapshot)
            : {};
        const expectedEntry = buildExpectedSaleLedgerEntry({
            merchantId: params.merchantId,
            customerId,
            canonicalCustomerId: canonical.canonicalCustomerId,
            saleId: params.saleId,
            saleData: currentSaleData,
            businessConfig,
            now,
            createdAt: pickNumber(existingLedgerData, 'created_at') ?? now,
        });
        if (existingLedgerSnapshot.exists &&
            loyaltyLedgerEntryHasDrift(existingLedgerData, expectedEntry)) {
            throw new CustomerCoreError(409, 'loyalty_ledger_immutable_conflict', 'The immutable sale ledger entry differs from the current sale.', {
                merchant_id: params.merchantId,
                sale_id: params.saleId,
                ledger_entry_id: expectedEntry.id,
            });
        }
        const existingSaleUpdatedAt = pickNumber(currentSaleData, 'updated_at');
        const saleCreatedAt = pickNumber(currentSaleData, 'created_at') ?? now;
        const { projection, balancedExpectedEntry } = await updateCustomerProjectionFromLedger(transaction, params.merchantId, customerId, currentCustomerData, expectedEntry);
        const saleUpdatedAt = params.saleUpdateMode === 'backfill'
            ? (existingSaleUpdatedAt ?? saleCreatedAt)
            : (maybePayloadString(currentSaleData, 'confirmation_status') === 'CONFIRMED' &&
                pickNumber(currentSaleData, 'confirmed_points') === balancedExpectedEntry.points_delta &&
                pickNumber(currentSaleData, 'loyalty_policy_version') === businessConfig.configVersion &&
                existingSaleUpdatedAt != null
                ? existingSaleUpdatedAt
                : now);
        const previousCustomerId = maybePayloadString(existingLedgerData, 'customer_id');
        if (previousCustomerId && previousCustomerId !== customerId) {
            await resetCustomerProjectionFromExistingLedger(transaction, params.merchantId, previousCustomerId);
        }
        transaction.set(currentSaleSnapshot.ref, {
            confirmation_status: 'CONFIRMED',
            confirmed_points: expectedEntry.points_delta,
            confirmed_at: now,
            confirmation_error_code: admin.firestore.FieldValue.delete(),
            loyalty_policy_version: businessConfig.configVersion,
            updated_at: saleUpdatedAt,
            confirmed_points_awarded: admin.firestore.FieldValue.delete(),
            loyalty_ledger_entry_id: admin.firestore.FieldValue.delete(),
            loyalty_points_per_mzn: admin.firestore.FieldValue.delete(),
            loyalty_config_version: admin.firestore.FieldValue.delete(),
            loyalty_status: admin.firestore.FieldValue.delete(),
            loyalty_error_code: admin.firestore.FieldValue.delete(),
            loyalty_error_message: admin.firestore.FieldValue.delete(),
            loyalty_error_at: admin.firestore.FieldValue.delete(),
            loyalty_processed_at: admin.firestore.FieldValue.delete(),
        }, { merge: true });
        const emittedSaleEventTypes = saleEventTypes.filter((eventType) => eventType !== 'FIRST_PURCHASE' || projection.totalVisits === 1)
            .filter((eventType) => eventType !== 'POINTS_EARNED' || balancedExpectedEntry.points_delta > 0);
        for (const eventType of emittedSaleEventTypes) {
            const eventIndex = saleEventTypes.indexOf(eventType);
            if (saleEventSnapshots[eventIndex].exists)
                continue;
            const event = buildDomainEvent({
                eventType,
                merchantId: params.merchantId,
                canonicalCustomerId: canonical.canonicalCustomerId,
                businessCustomerId: customerId,
                sourceType: 'sale',
                sourceId: params.saleId,
                occurredAt: expectedEntry.occurred_at,
                recordedAt: now,
                payload: {
                    amount_mzn: currentAmount,
                    points_awarded: balancedExpectedEntry.points_delta,
                    ledger_entry_id: balancedExpectedEntry.id,
                    loyalty_policy_version: businessConfig.configVersion,
                },
            });
            transaction.set(saleEventRefs[eventIndex], event);
        }
        return {
            merchant_id: params.merchantId,
            sale_id: params.saleId,
            customer_id: customerId,
            ledger_entry_id: balancedExpectedEntry.id,
            confirmed_points: balancedExpectedEntry.points_delta,
            updated_at: saleUpdatedAt,
            client_points: pickNumber(currentSaleData, 'points'),
            client_points_drift: (pickNumber(currentSaleData, 'points') ?? balancedExpectedEntry.points_delta) !== balancedExpectedEntry.points_delta,
            customer_confirmed_points: projection.confirmedPoints,
            total_visits: projection.totalVisits,
            total_spent: projection.totalSpent,
            drift_detected: existingLedgerSnapshot.exists &&
                loyaltyLedgerEntryHasDrift(existingLedgerData, balancedExpectedEntry),
            confirmation_status: 'CONFIRMED',
        };
    });
    const classification = await updateCustomerClassification({
        merchantId: params.merchantId,
        customerId,
        sourceType: 'sale',
        sourceId: params.saleId,
        causationId: deterministicDocumentId('evt', [
            params.merchantId,
            'PURCHASE_COMPLETED',
            'sale',
            params.saleId,
        ]),
        occurredAt: pickNumber(saleData, 'created_at') ?? now,
        dryRun: false,
    });
    return { ...result, classification };
}
async function inspectSaleForLoyaltyBackfill(params) {
    const saleSnapshot = params.saleSnapshot ?? await businessSalesCollectionRef(params.merchantId).doc(params.saleId).get();
    if (!saleSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_sale_not_found', 'Sale document not found.', { merchant_id: params.merchantId, sale_id: params.saleId });
    }
    const saleData = snapshotDataRecord(saleSnapshot);
    const customerId = maybePayloadString(saleData, 'customer_id', 'customerId');
    const amount = pickNumber(saleData, 'amount');
    if (!customerId) {
        throw new CustomerCoreError(400, 'loyalty_sale_customer_missing', 'Sale customer_id is required.', { merchant_id: params.merchantId, sale_id: params.saleId });
    }
    if (amount == null || amount <= 0) {
        throw new CustomerCoreError(400, 'loyalty_sale_amount_invalid', 'Sale amount must be greater than zero.', { merchant_id: params.merchantId, sale_id: params.saleId });
    }
    const [businessSnapshot, customerSnapshot] = await Promise.all([
        businessDocumentRef(params.merchantId).get(),
        businessCustomerRef(params.merchantId, customerId).get(),
    ]);
    if (!businessSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_business_not_found', 'Business document not found.', { merchant_id: params.merchantId });
    }
    if (!customerSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found for sale.', { merchant_id: params.merchantId, sale_id: params.saleId, customer_id: customerId });
    }
    const customerData = snapshotDataRecord(customerSnapshot);
    const canonical = await resolveCanonicalCustomerForLoyalty(params.merchantId, customerId, customerData, true);
    const businessConfig = getBusinessLoyaltyConfig(snapshotDataRecord(businessSnapshot));
    const expectedEntry = buildExpectedSaleLedgerEntry({
        merchantId: params.merchantId,
        customerId,
        canonicalCustomerId: canonical.canonicalCustomerId,
        saleId: params.saleId,
        saleData,
        businessConfig,
        now: Date.now(),
        createdAt: Date.now(),
    });
    const customerLedgerSnapshot = await boundedCustomerLedgerQuery(params.merchantId, customerId).get();
    assertLedgerQueryIsBounded(customerLedgerSnapshot, params.merchantId, customerId);
    const balancedEntries = computeLedgerEntriesWithBalances(mergeLedgerEntriesForProjection(customerLedgerSnapshot, expectedEntry));
    const balancedExpectedEntry = balancedEntries.find((entry) => entry.id === expectedEntry.id) ?? expectedEntry;
    const existingLedgerSnapshot = await loyaltyLedgerDocumentRef(params.merchantId, expectedEntry.id).get();
    const saleUpdatedAt = pickNumber(saleData, 'updated_at') ??
        pickNumber(saleData, 'created_at') ??
        Date.now();
    return {
        merchant_id: params.merchantId,
        sale_id: params.saleId,
        customer_id: customerId,
        ledger_entry_id: balancedExpectedEntry.id,
        confirmed_points: balancedExpectedEntry.points_delta,
        updated_at: saleUpdatedAt,
        client_points: pickNumber(saleData, 'points'),
        drift_detected: existingLedgerSnapshot.exists &&
            loyaltyLedgerEntryHasDrift(snapshotDataRecord(existingLedgerSnapshot), balancedExpectedEntry),
        client_points_drift: (pickNumber(saleData, 'points') ?? balancedExpectedEntry.points_delta) !== balancedExpectedEntry.points_delta,
        balance_after: balancedExpectedEntry.balance_after,
        status: 'DRY_RUN',
    };
}
async function processExistingRedemptionToLoyaltyLedger(params) {
    const redemptionSnapshot = params.redemptionSnapshot ??
        await businessRedemptionsCollectionRef(params.merchantId).doc(params.redemptionId).get();
    if (!redemptionSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_redemption_not_found', 'Redemption document not found.', { merchant_id: params.merchantId, redemption_id: params.redemptionId });
    }
    const redemptionData = snapshotDataRecord(redemptionSnapshot);
    const customerId = maybePayloadString(redemptionData, 'customer_id', 'customerId');
    const pointsSpent = pickNumber(redemptionData, 'points_spent') ?? pickNumber(redemptionData, 'pointsSpent');
    if (!customerId) {
        throw new CustomerCoreError(400, 'loyalty_redemption_customer_missing', 'Redemption customer_id is required.', { merchant_id: params.merchantId, redemption_id: params.redemptionId });
    }
    if (pointsSpent == null || pointsSpent <= 0) {
        throw new CustomerCoreError(400, 'loyalty_redemption_points_invalid', 'Redemption points_spent must be greater than zero.', { merchant_id: params.merchantId, redemption_id: params.redemptionId });
    }
    const [businessSnapshot, customerSnapshot] = await Promise.all([
        businessDocumentRef(params.merchantId).get(),
        businessCustomerRef(params.merchantId, customerId).get(),
    ]);
    if (!businessSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_business_not_found', 'Business document not found.', { merchant_id: params.merchantId });
    }
    if (!customerSnapshot.exists) {
        throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found for redemption.', { merchant_id: params.merchantId, redemption_id: params.redemptionId, customer_id: customerId });
    }
    const customerData = snapshotDataRecord(customerSnapshot);
    const canonical = await resolveCanonicalCustomerForLoyalty(params.merchantId, customerId, customerData, params.dryRun);
    const businessConfig = getBusinessLoyaltyConfig(snapshotDataRecord(businessSnapshot));
    const ledgerEntryId = buildDeterministicLoyaltyLedgerEntryId('REDEMPTION', params.redemptionId);
    const existingLedgerSnapshot = await loyaltyLedgerDocumentRef(params.merchantId, ledgerEntryId).get();
    const existingLedgerData = existingLedgerSnapshot.exists
        ? snapshotDataRecord(existingLedgerSnapshot)
        : {};
    const now = Date.now();
    const expectedEntry = buildExpectedRedemptionLedgerEntry({
        merchantId: params.merchantId,
        customerId,
        canonicalCustomerId: canonical.canonicalCustomerId,
        redemptionId: params.redemptionId,
        redemptionData,
        businessConfig,
        now,
        createdAt: pickNumber(existingLedgerData, 'created_at') ?? now,
    });
    const customerLedgerSnapshot = await boundedCustomerLedgerQuery(params.merchantId, customerId).get();
    assertLedgerQueryIsBounded(customerLedgerSnapshot, params.merchantId, customerId);
    const balancedEntries = computeLedgerEntriesWithBalances(mergeLedgerEntriesForProjection(customerLedgerSnapshot, expectedEntry));
    const balancedExpectedEntry = balancedEntries.find((entry) => entry.id === expectedEntry.id) ?? expectedEntry;
    if (params.dryRun) {
        return {
            merchant_id: params.merchantId,
            redemption_id: params.redemptionId,
            customer_id: customerId,
            ledger_entry_id: ledgerEntryId,
            points_delta: balancedExpectedEntry.points_delta,
            balance_after: balancedExpectedEntry.balance_after,
            drift_detected: existingLedgerSnapshot.exists &&
                loyaltyLedgerEntryHasDrift(existingLedgerData, balancedExpectedEntry),
            status: 'DRY_RUN',
        };
    }
    const result = await admin.firestore().runTransaction(async (transaction) => {
        const currentCustomerSnapshot = await transaction.get(businessCustomerRef(params.merchantId, customerId));
        if (!currentCustomerSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found for redemption.', { merchant_id: params.merchantId, redemption_id: params.redemptionId, customer_id: customerId });
        }
        const currentCustomerData = snapshotDataRecord(currentCustomerSnapshot);
        const currentExistingLedgerSnapshot = await transaction.get(loyaltyLedgerDocumentRef(params.merchantId, ledgerEntryId));
        const redemptionEvents = [
            'REDEMPTION_CONFIRMED',
            'REWARD_REDEEMED',
        ].map((eventType) => buildDomainEvent({
            eventType,
            merchantId: params.merchantId,
            canonicalCustomerId: canonical.canonicalCustomerId,
            businessCustomerId: customerId,
            sourceType: 'redemption',
            sourceId: params.redemptionId,
            occurredAt: expectedEntry.occurred_at,
            recordedAt: now,
            payload: {
                points_spent: Math.abs(expectedEntry.points_delta),
                ledger_entry_id: ledgerEntryId,
                reward_id: expectedEntry.reward_id ?? null,
            },
        }));
        const redemptionEventRefs = redemptionEvents.map((event) => domainEventCollectionRef(params.merchantId).doc(event.event_id));
        const redemptionEventSnapshots = await Promise.all(redemptionEventRefs.map((eventRef) => transaction.get(eventRef)));
        const currentExistingLedgerData = currentExistingLedgerSnapshot.exists
            ? snapshotDataRecord(currentExistingLedgerSnapshot)
            : {};
        const entryToWrite = {
            ...expectedEntry,
            created_at: pickNumber(currentExistingLedgerData, 'created_at') ?? expectedEntry.created_at,
        };
        if (currentExistingLedgerSnapshot.exists &&
            loyaltyLedgerEntryHasDrift(currentExistingLedgerData, entryToWrite)) {
            throw new CustomerCoreError(409, 'loyalty_ledger_immutable_conflict', 'The immutable redemption ledger entry differs from the redemption.', {
                merchant_id: params.merchantId,
                redemption_id: params.redemptionId,
                ledger_entry_id: ledgerEntryId,
            });
        }
        const { projection, balancedExpectedEntry } = await updateCustomerProjectionFromLedger(transaction, params.merchantId, customerId, currentCustomerData, entryToWrite);
        transaction.set(businessRedemptionsCollectionRef(params.merchantId).doc(params.redemptionId), {
            confirmed_points_spent: Math.abs(entryToWrite.points_delta),
            loyalty_ledger_entry_id: ledgerEntryId,
            loyalty_status: 'CONFIRMED',
            loyalty_processed_at: Date.now(),
        }, { merge: true });
        redemptionEvents.forEach((event, index) => {
            if (!redemptionEventSnapshots[index].exists) {
                transaction.set(redemptionEventRefs[index], event);
            }
        });
        return {
            merchant_id: params.merchantId,
            redemption_id: params.redemptionId,
            customer_id: customerId,
            ledger_entry_id: balancedExpectedEntry.id,
            confirmed_points_balance: projection.confirmedPoints,
            drift_detected: currentExistingLedgerSnapshot.exists &&
                loyaltyLedgerEntryHasDrift(currentExistingLedgerData, balancedExpectedEntry),
            status: 'CONFIRMED',
        };
    });
    const classification = await updateCustomerClassification({
        merchantId: params.merchantId,
        customerId: customerId,
        sourceType: 'redemption',
        sourceId: params.redemptionId,
        causationId: deterministicDocumentId('evt', [
            params.merchantId,
            'REWARD_REDEEMED',
            'redemption',
            params.redemptionId,
        ]),
        occurredAt: expectedEntry.occurred_at,
        dryRun: false,
    });
    return { ...result, classification };
}
async function handleLoyaltyLedgerBackfillRequest(req, body) {
    const payload = requireBodyObject(body);
    const merchantId = await resolveCustomerCoreMerchantId(req, payload);
    const requestedSourceType = maybePayloadString(payload, 'source_type', 'sourceType')?.toLowerCase() ?? 'all';
    if (!['all', 'sales', 'redemptions'].includes(requestedSourceType)) {
        throw new CustomerCoreError(400, 'loyalty_source_type_invalid', 'source_type must be all, sales, or redemptions.');
    }
    const cursorSourceType = (maybePayloadString(payload, 'cursor_source_type', 'cursorSourceType')?.toLowerCase() ??
        (requestedSourceType === 'all' ? 'sales' : requestedSourceType));
    const startAfterId = maybePayloadString(payload, 'start_after_id', 'startAfterId');
    const apply = maybePayloadBoolean(payload, 'apply') ?? false;
    const limit = clampLimit(payload.limit, 50, 200);
    const sourceType = requestedSourceType === 'all'
        ? cursorSourceType
        : requestedSourceType;
    if (!['sales', 'redemptions'].includes(sourceType)) {
        throw new CustomerCoreError(400, 'loyalty_source_type_invalid', 'cursor_source_type must be sales or redemptions.');
    }
    let query = (sourceType === 'sales'
        ? businessSalesCollectionRef(merchantId)
        : businessRedemptionsCollectionRef(merchantId))
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);
    if (startAfterId) {
        query = query.startAfter(startAfterId);
    }
    const snapshot = await query.get();
    const results = [];
    const affectedCustomerIds = new Set();
    let appliedCount = 0;
    let driftCount = 0;
    let ambiguityCount = 0;
    let errorCount = 0;
    for (const doc of snapshot.docs) {
        try {
            const result = sourceType === 'sales'
                ? apply
                    ? await applySaleToLoyaltyLedger({
                        merchantId,
                        saleId: doc.id,
                        saleSnapshot: doc,
                        allowLegacyBootstrap: true,
                        saleUpdateMode: 'backfill',
                    })
                    : await inspectSaleForLoyaltyBackfill({
                        merchantId,
                        saleId: doc.id,
                        saleSnapshot: doc,
                    })
                : await processExistingRedemptionToLoyaltyLedger({
                    merchantId,
                    redemptionId: doc.id,
                    redemptionSnapshot: doc,
                    dryRun: !apply,
                });
            results.push({
                ...result,
                status: apply ? 'APPLIED' : 'DRY_RUN',
            });
            if (result.drift_detected === true ||
                result.client_points_drift === true) {
                driftCount += 1;
            }
            if (apply) {
                appliedCount += 1;
            }
            const affectedCustomerId = maybePayloadString(result, 'customer_id');
            if (affectedCustomerId) {
                affectedCustomerIds.add(affectedCustomerId);
            }
        }
        catch (error) {
            if (error instanceof CustomerCoreError) {
                results.push({
                    source_type: sourceType,
                    source_id: doc.id,
                    status: error.code.includes('ambigu') || error.code.includes('conflict')
                        ? 'AMBIGUITY'
                        : 'ERROR',
                    code: error.code,
                    message: error.message,
                    ...(error.details ? { details: error.details } : {}),
                });
                if (error.code.includes('ambigu') || error.code.includes('conflict')) {
                    ambiguityCount += 1;
                }
                else {
                    errorCount += 1;
                }
                continue;
            }
            throw error;
        }
    }
    const nextCursor = snapshot.docs.length === limit && snapshot.docs.length > 0
        ? { source_type: sourceType, start_after_id: snapshot.docs[snapshot.docs.length - 1].id }
        : requestedSourceType === 'all' && sourceType === 'sales'
            ? { source_type: 'redemptions', start_after_id: null }
            : null;
    return {
        merchant_id: merchantId,
        mode: apply ? 'apply' : 'dry_run',
        source_type: sourceType,
        processed: snapshot.docs.length,
        applied: appliedCount,
        drift_count: driftCount,
        ambiguity_count: ambiguityCount,
        error_count: errorCount,
        affected_customer_ids: [...affectedCustomerIds],
        has_more: nextCursor != null,
        next_cursor: nextCursor,
        results,
    };
}
async function handleLoyaltyLedgerReconcileRequest(req, body) {
    const payload = requireBodyObject(body);
    const merchantId = await resolveCustomerCoreMerchantId(req, payload);
    const apply = maybePayloadBoolean(payload, 'apply') ?? false;
    const limit = clampLimit(payload.limit, 50, 200);
    const startAfterCustomerId = maybePayloadString(payload, 'start_after_customer_id', 'startAfterCustomerId');
    let query = businessDocumentRef(merchantId)
        .collection('customers')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);
    if (startAfterCustomerId) {
        query = query.startAfter(startAfterCustomerId);
    }
    const snapshot = await query.get();
    const results = [];
    let driftCount = 0;
    let appliedCount = 0;
    for (const doc of snapshot.docs) {
        const customerData = snapshotDataRecord(doc);
        const [ledgerSnapshot, salesSnapshot, redemptionsSnapshot] = await Promise.all([
            boundedCustomerLedgerQuery(merchantId, doc.id).get(),
            businessSalesCollectionRef(merchantId).where('customer_id', '==', doc.id).limit(1).get(),
            businessRedemptionsCollectionRef(merchantId).where('customer_id', '==', doc.id).limit(1).get(),
        ]);
        assertLedgerQueryIsBounded(ledgerSnapshot, merchantId, doc.id);
        if (ledgerSnapshot.empty &&
            salesSnapshot.empty &&
            redemptionsSnapshot.empty &&
            (pickNumber(customerData, 'total_points') ?? 0) <= 0 &&
            pickNumber(customerData, 'confirmed_points') == null) {
            results.push({
                customer_id: doc.id,
                status: 'NO_ACTIVITY',
                ledger_entry_count: 0,
            });
            continue;
        }
        if (ledgerSnapshot.empty &&
            (!salesSnapshot.empty ||
                !redemptionsSnapshot.empty ||
                (pickNumber(customerData, 'total_points') ?? 0) > 0)) {
            results.push({
                customer_id: doc.id,
                status: 'BACKFILL_REQUIRED',
                code: 'loyalty_backfill_required',
                message: 'Customer has loyalty activity but no authoritative ledger entries yet.',
            });
            driftCount += 1;
            continue;
        }
        const projection = computeCustomerProjectionFromLedgerEntries(ledgerSnapshot.docs.map((item) => loyaltyLedgerEntryFromData(snapshotDataRecord(item))));
        const expectedPatch = buildCustomerProjectionPatch(customerData, projection, Date.now());
        const drift = !valuesEqual(customerData.confirmed_points, expectedPatch.confirmed_points) ||
            !valuesEqual(customerData.total_points, expectedPatch.total_points) ||
            !valuesEqual(customerData.total_visits, expectedPatch.total_visits) ||
            !valuesEqual(customerData.total_spent, expectedPatch.total_spent) ||
            !valuesEqual(customerData.average_spend, expectedPatch.average_spend) ||
            !valuesEqual(customerData.average_visit_interval_days, expectedPatch.average_visit_interval_days) ||
            !valuesEqual(customerData.first_visit_at, expectedPatch.first_visit_at) ||
            !valuesEqual(customerData.last_visit_at, expectedPatch.last_visit_at);
        if (drift) {
            driftCount += 1;
        }
        if (apply && drift) {
            await doc.ref.set(expectedPatch, { merge: true });
            appliedCount += 1;
        }
        results.push({
            customer_id: doc.id,
            status: drift ? (apply ? 'APPLIED' : 'DRIFT') : 'IN_SYNC',
            ledger_entry_count: ledgerSnapshot.size,
            expected_confirmed_points: expectedPatch.confirmed_points,
            stored_confirmed_points: pickNumber(customerData, 'confirmed_points') ?? 0,
            stored_total_points: pickNumber(customerData, 'total_points') ?? 0,
            expected_total_visits: expectedPatch.total_visits,
            stored_total_visits: pickNumber(customerData, 'total_visits') ?? 0,
        });
    }
    const nextCursor = snapshot.docs.length === limit && snapshot.docs.length > 0
        ? snapshot.docs[snapshot.docs.length - 1].id
        : null;
    return {
        merchant_id: merchantId,
        mode: apply ? 'apply' : 'dry_run',
        processed: snapshot.docs.length,
        drift_count: driftCount,
        applied: appliedCount,
        has_more: nextCursor != null,
        next_cursor: nextCursor,
        results,
    };
}
async function handleAssistedLoyaltyRedemptionRequest(req, payload, trustedCustomerRequest) {
    const merchantId = trustedCustomerRequest?.merchantId ??
        await resolveCustomerCoreMerchantId(req, payload);
    const customerId = trustedCustomerRequest?.customerId ??
        requirePayloadString(payload, 'customer_id');
    const rewardId = requirePayloadString(payload, 'reward_id');
    const idempotencyKey = maybePayloadString(payload, 'idempotency_key', 'idempotencyKey');
    if (!idempotencyKey) {
        throw new CustomerCoreError(400, 'loyalty_idempotency_key_missing', 'idempotency_key is required for assisted redemption.');
    }
    const now = Date.now();
    const redemptionId = buildDeterministicRedemptionId(merchantId, idempotencyKey);
    const redemptionEventTypes = [
        'REDEMPTION_CONFIRMED',
        'REWARD_REDEEMED',
    ];
    const redemptionEventRefs = redemptionEventTypes.map((eventType) => domainEventCollectionRef(merchantId).doc(deterministicDocumentId('evt', [
        merchantId,
        eventType,
        'redemption',
        redemptionId,
    ])));
    const result = await admin.firestore().runTransaction(async (transaction) => {
        const [businessSnapshot, rewardSnapshot, customerSnapshot, redemptionSnapshot, redemptionEventSnapshots,] = await Promise.all([
            transaction.get(businessDocumentRef(merchantId)),
            transaction.get(businessRewardsCollectionRef(merchantId).doc(rewardId)),
            transaction.get(businessCustomerRef(merchantId, customerId)),
            transaction.get(businessRedemptionsCollectionRef(merchantId).doc(redemptionId)),
            Promise.all(redemptionEventRefs.map((eventRef) => transaction.get(eventRef))),
        ]);
        if (!businessSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_business_not_found', 'Business document not found.', { merchant_id: merchantId });
        }
        if (!rewardSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_reward_not_found', 'Reward not found.', { merchant_id: merchantId, reward_id: rewardId });
        }
        if (!customerSnapshot.exists) {
            throw new CustomerCoreError(404, 'loyalty_customer_not_found', 'Business customer not found.', { merchant_id: merchantId, customer_id: customerId });
        }
        const ledgerEntryId = buildDeterministicLoyaltyLedgerEntryId('REDEMPTION', redemptionId);
        const ledgerRef = loyaltyLedgerDocumentRef(merchantId, ledgerEntryId);
        const ledgerSnapshot = await transaction.get(ledgerRef);
        if (redemptionSnapshot.exists && ledgerSnapshot.exists) {
            const existingRedemptionData = snapshotDataRecord(redemptionSnapshot);
            if (maybePayloadString(existingRedemptionData, 'customer_id', 'customerId') !== customerId ||
                maybePayloadString(existingRedemptionData, 'reward_id', 'rewardId') !== rewardId) {
                throw new CustomerCoreError(409, 'loyalty_redemption_idempotency_conflict', 'The supplied idempotency_key was already used for a different redemption request.', { merchant_id: merchantId, redemption_id: redemptionId });
            }
            const existingLedgerEntriesSnapshot = await transaction.get(boundedCustomerLedgerQuery(merchantId, customerId));
            assertLedgerQueryIsBounded(existingLedgerEntriesSnapshot, merchantId, customerId);
            const existingProjection = computeCustomerProjectionFromLedgerEntries(existingLedgerEntriesSnapshot.docs.map((doc) => loyaltyLedgerEntryFromData(snapshotDataRecord(doc))));
            transaction.set(businessCustomerRef(merchantId, customerId), buildCustomerProjectionPatch(snapshotDataRecord(customerSnapshot), existingProjection, now), { merge: true });
            const replayCustomerData = snapshotDataRecord(customerSnapshot);
            const replayLedgerData = snapshotDataRecord(ledgerSnapshot);
            const replayCanonicalCustomerId = maybePayloadString(replayCustomerData, 'canonical_customer_id', 'canonicalCustomerId');
            if (!replayCanonicalCustomerId) {
                throw new CustomerCoreError(409, 'loyalty_canonical_link_required', 'Customer canonical relationship is missing. Run customer linking/backfill first.', { merchant_id: merchantId, customer_id: customerId });
            }
            redemptionEventTypes.forEach((eventType, index) => {
                if (redemptionEventSnapshots[index].exists)
                    return;
                transaction.set(redemptionEventRefs[index], buildDomainEvent({
                    eventType,
                    merchantId,
                    canonicalCustomerId: replayCanonicalCustomerId,
                    businessCustomerId: customerId,
                    sourceType: 'redemption',
                    sourceId: redemptionId,
                    occurredAt: pickNumber(existingRedemptionData, 'redeemed_at') ??
                        pickNumber(existingRedemptionData, 'created_at') ??
                        now,
                    recordedAt: now,
                    payload: {
                        points_spent: Math.abs(pickNumber(replayLedgerData, 'points_delta') ?? 0),
                        ledger_entry_id: ledgerEntryId,
                        reward_id: rewardId,
                    },
                }));
            });
            return {
                merchant_id: merchantId,
                redemption_id: redemptionId,
                customer_id: customerId,
                redemption: {
                    ...existingRedemptionData,
                    confirmed_points: existingProjection.confirmedPoints,
                },
                confirmed_points: existingProjection.confirmedPoints,
                idempotent_replay: true,
            };
        }
        const rewardData = snapshotDataRecord(rewardSnapshot);
        const rewardActive = pickBoolean(rewardData, 'active') ?? true;
        const pointsRequired = pickNumber(rewardData, 'points_required') ?? pickNumber(rewardData, 'pointsRequired');
        if (!rewardActive) {
            throw new CustomerCoreError(409, 'loyalty_reward_inactive', 'Reward is not active.', { merchant_id: merchantId, reward_id: rewardId });
        }
        if (pointsRequired == null || pointsRequired <= 0) {
            throw new CustomerCoreError(409, 'loyalty_reward_points_invalid', 'Reward points_required must be greater than zero.', { merchant_id: merchantId, reward_id: rewardId });
        }
        const customerData = snapshotDataRecord(customerSnapshot);
        const canonicalCustomerId = maybePayloadString(customerData, 'canonical_customer_id', 'canonicalCustomerId');
        if (!canonicalCustomerId) {
            throw new CustomerCoreError(409, 'loyalty_canonical_link_required', 'Customer canonical relationship is missing. Run customer linking/backfill first.', { merchant_id: merchantId, customer_id: customerId });
        }
        if (pickNumber(customerData, 'loyalty_projection_version') !== LOYALTY_PROJECTION_VERSION) {
            throw new CustomerCoreError(409, 'loyalty_backfill_required', 'Customer loyalty history must be backfilled before online redemption.', { merchant_id: merchantId, customer_id: customerId });
        }
        const [forwardLinkSnapshot, reverseLinkSnapshot] = await Promise.all([
            transaction.get(businessCustomerLinkRef(merchantId, customerId)),
            transaction.get(canonicalIdentityBusinessLinkRef(merchantId, canonicalCustomerId)),
        ]);
        const forwardLinkData = snapshotDataRecord(forwardLinkSnapshot);
        const reverseLinkData = snapshotDataRecord(reverseLinkSnapshot);
        if (!forwardLinkSnapshot.exists ||
            maybePayloadString(forwardLinkData, 'canonical_customer_id') !== canonicalCustomerId ||
            !reverseLinkSnapshot.exists ||
            maybePayloadString(reverseLinkData, 'business_customer_id', 'customer_id') !== customerId) {
            throw new CustomerCoreError(409, 'loyalty_canonical_link_inconsistent', 'Customer canonical relationship is inconsistent. Run customer backfill to repair it.', {
                merchant_id: merchantId,
                customer_id: customerId,
                canonical_customer_id: canonicalCustomerId,
            });
        }
        const businessConfig = getBusinessLoyaltyConfig(snapshotDataRecord(businessSnapshot));
        if (redemptionSnapshot.exists) {
            const existingRedemptionData = snapshotDataRecord(redemptionSnapshot);
            if (maybePayloadString(existingRedemptionData, 'customer_id', 'customerId') !== customerId ||
                maybePayloadString(existingRedemptionData, 'reward_id', 'rewardId') !== rewardId) {
                throw new CustomerCoreError(409, 'loyalty_redemption_idempotency_conflict', 'The supplied idempotency_key was already used for a different redemption request.', { merchant_id: merchantId, redemption_id: redemptionId });
            }
        }
        const ledgerQuerySnapshot = await transaction.get(boundedCustomerLedgerQuery(merchantId, customerId));
        assertLedgerQueryIsBounded(ledgerQuerySnapshot, merchantId, customerId);
        const existingEntries = ledgerQuerySnapshot.docs.map((doc) => loyaltyLedgerEntryFromData(snapshotDataRecord(doc)));
        const projectionBefore = computeCustomerProjectionFromLedgerEntries(existingEntries);
        if (projectionBefore.confirmedPoints < pointsRequired) {
            throw new CustomerCoreError(409, 'loyalty_insufficient_confirmed_points', 'Customer does not have enough confirmed points for this reward.', {
                merchant_id: merchantId,
                customer_id: customerId,
                confirmed_points: projectionBefore.confirmedPoints,
                points_required: pointsRequired,
            });
        }
        const existingRedemptionCode = redemptionSnapshot.exists
            ? maybePayloadString(snapshotDataRecord(redemptionSnapshot), 'redemption_code')
            : null;
        const redemptionData = {
            id: redemptionId,
            merchant_id: merchantId,
            customer_id: customerId,
            canonical_customer_id: canonicalCustomerId,
            reward_id: rewardId,
            points_spent: pointsRequired,
            confirmed_points_spent: pointsRequired,
            redeemed_at: pickNumber(payload, 'redeemed_at') ?? now,
            idempotency_key: idempotencyKey,
            loyalty_ledger_entry_id: ledgerEntryId,
            loyalty_status: 'CONFIRMED',
            loyalty_processed_at: now,
            created_at: pickNumber(payload, 'redeemed_at') ?? now,
            updated_at: now,
            ...(trustedCustomerRequest?.redemptionCode
                ? {
                    redemption_code: existingRedemptionCode ?? trustedCustomerRequest.redemptionCode,
                }
                : {}),
        };
        const expectedEntry = buildExpectedRedemptionLedgerEntry({
            merchantId,
            customerId,
            canonicalCustomerId,
            redemptionId,
            redemptionData,
            businessConfig,
            now,
            createdAt: ledgerSnapshot.exists
                ? (pickNumber(snapshotDataRecord(ledgerSnapshot), 'created_at') ?? now)
                : now,
        });
        transaction.set(businessRedemptionsCollectionRef(merchantId).doc(redemptionId), redemptionData, { merge: true });
        if (ledgerSnapshot.exists) {
            const ledgerData = snapshotDataRecord(ledgerSnapshot);
            if (loyaltyLedgerEntryHasDrift(ledgerData, expectedEntry)) {
                throw new CustomerCoreError(409, 'loyalty_ledger_immutable_conflict', 'The immutable redemption ledger entry differs from the redemption request.', {
                    merchant_id: merchantId,
                    redemption_id: redemptionId,
                    ledger_entry_id: ledgerEntryId,
                });
            }
        }
        else {
            transaction.set(ledgerRef, expectedEntry);
        }
        redemptionEventTypes.forEach((eventType, index) => {
            if (redemptionEventSnapshots[index].exists)
                return;
            transaction.set(redemptionEventRefs[index], buildDomainEvent({
                eventType,
                merchantId,
                canonicalCustomerId,
                businessCustomerId: customerId,
                sourceType: 'redemption',
                sourceId: redemptionId,
                occurredAt: expectedEntry.occurred_at,
                recordedAt: now,
                payload: {
                    points_spent: pointsRequired,
                    ledger_entry_id: ledgerEntryId,
                    reward_id: rewardId,
                },
            }));
        });
        const projection = computeCustomerProjectionFromLedgerEntries([
            ...existingEntries.filter((entry) => entry.id !== expectedEntry.id),
            expectedEntry,
        ]);
        transaction.set(businessCustomerRef(merchantId, customerId), buildCustomerProjectionPatch(customerData, projection, now), { merge: true });
        return {
            merchant_id: merchantId,
            redemption_id: redemptionId,
            customer_id: customerId,
            redemption: {
                ...redemptionData,
                confirmed_points: projection.confirmedPoints,
            },
            confirmed_points: projection.confirmedPoints,
            idempotent_replay: redemptionSnapshot.exists && ledgerSnapshot.exists,
        };
    });
    const classification = await updateCustomerClassification({
        merchantId,
        customerId,
        sourceType: 'redemption',
        sourceId: redemptionId,
        causationId: deterministicDocumentId('evt', [
            merchantId,
            'REWARD_REDEEMED',
            'redemption',
            redemptionId,
        ]),
        occurredAt: pickNumber(payload, 'redeemed_at') ?? now,
        dryRun: false,
    });
    return { ...result, classification };
}
function retentionDefaultsForBusiness(businessData) {
    const businessType = (maybePayloadString(businessData, 'business_type', 'businessType') ?? 'other').toLowerCase();
    const defaults = {
        barbershop: [14, 30, 60],
        salon: [21, 45, 75],
        spa: [30, 60, 90],
        retail: [30, 60, 120],
        restaurant: [7, 21, 45],
        cafe: [7, 21, 45],
        clinic: [30, 60, 90],
        gym: [7, 14, 30],
        workshop: [60, 120, 240],
        professional_services: [30, 60, 90],
        other: [30, 60, 90],
    };
    const selected = defaults[businessType] ?? defaults.other;
    const rawConfig = businessData.retention_config;
    const config = rawConfig != null && typeof rawConfig === 'object'
        ? rawConfig
        : {};
    const activeDays = positiveIntegerOrDefault(config.active_days, selected[0]);
    const attentionDays = positiveIntegerOrDefault(config.attention_days, selected[1]);
    const riskDays = positiveIntegerOrDefault(config.risk_days, selected[2]);
    if (activeDays < attentionDays && attentionDays < riskDays) {
        return { activeDays, attentionDays, riskDays };
    }
    return {
        activeDays: selected[0],
        attentionDays: selected[1],
        riskDays: selected[2],
    };
}
function buildSeedRetentionPolicy(businessData) {
    const retention = retentionDefaultsForBusiness(businessData);
    return {
        schemaVersion: RETENTION_POLICY_SCHEMA_VERSION,
        version: 1,
        activeDays: retention.activeDays,
        attentionDays: retention.attentionDays,
        riskDays: retention.riskDays,
        returningVisits: 2,
        regularVisits: 5,
        loyalVisits: 10,
        vipSpendMzn: 5000,
        advocateVisits: 20,
        advocateSpendMzn: 10000,
    };
}
function validateRetentionPolicy(policy) {
    const integerValues = [
        policy.version,
        policy.activeDays,
        policy.attentionDays,
        policy.riskDays,
        policy.returningVisits,
        policy.regularVisits,
        policy.loyalVisits,
        policy.advocateVisits,
    ];
    if (integerValues.some((value) => !Number.isInteger(value) || value <= 0)) {
        throw new CustomerCoreError(400, 'retention_policy_invalid', 'Retention policy day and visit thresholds must be positive integers.');
    }
    if (!(policy.activeDays < policy.attentionDays &&
        policy.attentionDays < policy.riskDays)) {
        throw new CustomerCoreError(400, 'retention_policy_invalid', 'Retention thresholds must satisfy active_days < attention_days < risk_days.');
    }
    if (!(policy.returningVisits < policy.regularVisits &&
        policy.regularVisits < policy.loyalVisits &&
        policy.loyalVisits < policy.advocateVisits)) {
        throw new CustomerCoreError(400, 'retention_policy_invalid', 'Lifecycle visit thresholds must increase from returning through advocate.');
    }
    if (!Number.isFinite(policy.vipSpendMzn) ||
        policy.vipSpendMzn <= 0 ||
        !Number.isFinite(policy.advocateSpendMzn) ||
        policy.advocateSpendMzn < policy.vipSpendMzn) {
        throw new CustomerCoreError(400, 'retention_policy_invalid', 'Spend thresholds must be positive and advocate spend must be at least VIP spend.');
    }
    return policy;
}
function retentionPolicyFromData(data, expectedVersion) {
    return validateRetentionPolicy({
        schemaVersion: positiveIntegerOrDefault(data.schema_version, RETENTION_POLICY_SCHEMA_VERSION),
        version: positiveIntegerOrDefault(data.version, expectedVersion),
        activeDays: positiveIntegerOrDefault(data.active_days, 30),
        attentionDays: positiveIntegerOrDefault(data.attention_days, 60),
        riskDays: positiveIntegerOrDefault(data.risk_days, 90),
        returningVisits: positiveIntegerOrDefault(data.returning_visits, 2),
        regularVisits: positiveIntegerOrDefault(data.regular_visits, 5),
        loyalVisits: positiveIntegerOrDefault(data.loyal_visits, 10),
        vipSpendMzn: parseNumber(data.vip_spend_mzn) ?? 5000,
        advocateVisits: positiveIntegerOrDefault(data.advocate_visits, 20),
        advocateSpendMzn: parseNumber(data.advocate_spend_mzn) ?? 10000,
    });
}
function retentionPolicyDocumentData(merchantId, policy, source, now, actorId) {
    return {
        id: `v${policy.version}`,
        merchant_id: merchantId,
        schema_version: policy.schemaVersion,
        version: policy.version,
        status: 'ACTIVE',
        active_days: policy.activeDays,
        attention_days: policy.attentionDays,
        risk_days: policy.riskDays,
        returning_visits: policy.returningVisits,
        regular_visits: policy.regularVisits,
        loyal_visits: policy.loyalVisits,
        vip_spend_mzn: policy.vipSpendMzn,
        advocate_visits: policy.advocateVisits,
        advocate_spend_mzn: policy.advocateSpendMzn,
        source,
        effective_at: now,
        created_at: now,
        created_by: actorId ?? 'system',
    };
}
async function resolveActiveRetentionPolicy(merchantId, persistSeed = true) {
    const businessRef = businessDocumentRef(merchantId);
    const businessSnapshot = await businessRef.get();
    if (!businessSnapshot.exists) {
        throw new CustomerCoreError(404, 'retention_business_not_found', 'Business document not found.', { merchant_id: merchantId });
    }
    const businessData = snapshotDataRecord(businessSnapshot);
    const activeVersion = pickNumber(businessData, 'active_retention_policy_version');
    if (activeVersion != null) {
        const policySnapshot = await retentionPolicyDocumentRef(merchantId, activeVersion).get();
        if (!policySnapshot.exists) {
            throw new CustomerCoreError(409, 'retention_active_policy_missing', 'The business active retention policy document is missing.', { merchant_id: merchantId, policy_version: activeVersion });
        }
        return retentionPolicyFromData(snapshotDataRecord(policySnapshot), activeVersion);
    }
    const seed = validateRetentionPolicy(buildSeedRetentionPolicy(businessData));
    if (!persistSeed)
        return seed;
    const now = Date.now();
    return admin.firestore().runTransaction(async (transaction) => {
        const currentBusinessSnapshot = await transaction.get(businessRef);
        if (!currentBusinessSnapshot.exists) {
            throw new CustomerCoreError(404, 'retention_business_not_found', 'Business document not found.', { merchant_id: merchantId });
        }
        const currentBusinessData = snapshotDataRecord(currentBusinessSnapshot);
        const currentVersion = pickNumber(currentBusinessData, 'active_retention_policy_version');
        const version = currentVersion ?? 1;
        const policyRef = retentionPolicyDocumentRef(merchantId, version);
        const policySnapshot = await transaction.get(policyRef);
        if (currentVersion != null && !policySnapshot.exists) {
            throw new CustomerCoreError(409, 'retention_active_policy_missing', 'The business active retention policy document is missing.', { merchant_id: merchantId, policy_version: currentVersion });
        }
        if (policySnapshot.exists) {
            return retentionPolicyFromData(snapshotDataRecord(policySnapshot), version);
        }
        const currentSeed = validateRetentionPolicy(buildSeedRetentionPolicy(currentBusinessData));
        transaction.set(policyRef, retentionPolicyDocumentData(merchantId, currentSeed, 'SEEDED', now));
        transaction.set(businessRef, {
            active_retention_policy_version: currentSeed.version,
            retention_policy_schema_version: RETENTION_POLICY_SCHEMA_VERSION,
            retention_policy_seeded_at: now,
        }, { merge: true });
        return currentSeed;
    });
}
function classifyCustomer(input, policy) {
    const totalVisits = Math.max(0, Math.floor(input.totalVisits));
    const totalSpent = Math.max(0, input.totalSpent);
    let lifecycle;
    let lifecycleReasons;
    if (totalVisits === 0 && input.explicitPreReturnActiveRelationship) {
        lifecycle = 'ACTIVE';
        lifecycleReasons = ['explicit_pre_return_active_relationship=true', 'visits=0'];
    }
    else if (totalVisits <= 1) {
        lifecycle = 'NEW';
        lifecycleReasons = totalVisits === 0
            ? ['visits=0']
            : ['first_confirmed_visit', 'first_confirmed_visit_remains_new'];
    }
    else if (totalVisits >= policy.advocateVisits &&
        totalSpent >= policy.advocateSpendMzn) {
        lifecycle = 'ADVOCATE';
        lifecycleReasons = [
            `visits>=${policy.advocateVisits}`,
            `spend_mzn>=${policy.advocateSpendMzn}`,
        ];
    }
    else if (totalVisits >= policy.regularVisits &&
        totalSpent >= policy.vipSpendMzn) {
        lifecycle = 'VIP';
        lifecycleReasons = [`spend_mzn>=${policy.vipSpendMzn}`];
    }
    else if (totalVisits >= policy.loyalVisits) {
        lifecycle = 'LOYAL';
        lifecycleReasons = [`visits>=${policy.loyalVisits}`];
    }
    else if (totalVisits >= policy.regularVisits) {
        lifecycle = 'REGULAR';
        lifecycleReasons = [`visits>=${policy.regularVisits}`];
    }
    else {
        lifecycle = 'RETURNING';
        lifecycleReasons = [
            `visits>=${policy.returningVisits}`,
            'second_confirmed_visit_is_returning',
        ];
    }
    const nowDate = new Date(input.now);
    const lastDate = input.lastVisitAt == null ? null : new Date(input.lastVisitAt);
    const daysSinceActivity = lastDate == null
        ? null
        : Math.max(0, Math.floor((Date.UTC(nowDate.getUTCFullYear(), nowDate.getUTCMonth(), nowDate.getUTCDate()) -
            Date.UTC(lastDate.getUTCFullYear(), lastDate.getUTCMonth(), lastDate.getUTCDate())) / (24 * 60 * 60 * 1000)));
    let retention;
    let retentionReasons;
    if (daysSinceActivity == null || daysSinceActivity <= policy.activeDays) {
        retention = 'HEALTHY';
        retentionReasons = daysSinceActivity == null
            ? ['no_confirmed_visit_yet']
            : [`days_since_activity<=${policy.activeDays}`];
    }
    else if (daysSinceActivity <= policy.attentionDays) {
        retention = 'AT_RISK';
        retentionReasons = [
            `days_since_activity>${policy.activeDays}`,
            `days_since_activity<=${policy.attentionDays}`,
        ];
    }
    else if (daysSinceActivity <= policy.riskDays) {
        retention = 'INACTIVE';
        retentionReasons = [
            `days_since_activity>${policy.attentionDays}`,
            `days_since_activity<=${policy.riskDays}`,
        ];
    }
    else {
        retention = 'LOST';
        retentionReasons = [`days_since_activity>${policy.riskDays}`];
    }
    return {
        lifecycle,
        retention,
        lifecycleReasons,
        retentionReasons,
        daysSinceActivity,
        explanation: `Lifecycle ${lifecycle} from ${totalVisits} confirmed visits and ${totalSpent} MZN; ` +
            `retention ${retention} from ` +
            (daysSinceActivity == null ? 'no confirmed visit' : `${daysSinceActivity} inactive days`) +
            ` under policy v${policy.version}.`,
    };
}
function nextBestActionFor(classification) {
    if (classification.retention === 'LOST') {
        return {
            actionType: 'WIN_BACK',
            priority: 100,
            explanation: 'Offer a personal win-back incentive and ask what changed.',
            reasons: classification.retentionReasons,
        };
    }
    if (classification.retention === 'INACTIVE') {
        return {
            actionType: 'RECOVERY_OUTREACH',
            priority: 90,
            explanation: 'Contact the customer with a relevant reason to return.',
            reasons: classification.retentionReasons,
        };
    }
    if (classification.retention === 'AT_RISK') {
        return {
            actionType: 'TIMELY_REMINDER',
            priority: 80,
            explanation: 'Send a consent-aware reminder before inactivity deepens.',
            reasons: classification.retentionReasons,
        };
    }
    if (classification.lifecycle === 'ADVOCATE') {
        return {
            actionType: 'REQUEST_REFERRAL',
            priority: 55,
            explanation: 'Thank this advocate and invite a referral.',
            reasons: classification.lifecycleReasons,
        };
    }
    if (classification.lifecycle === 'VIP' || classification.lifecycle === 'LOYAL') {
        return {
            actionType: 'LOYALTY_RECOGNITION',
            priority: 50,
            explanation: 'Recognize loyalty with a relevant benefit or personal thank-you.',
            reasons: classification.lifecycleReasons,
        };
    }
    if (classification.lifecycle === 'NEW') {
        return {
            actionType: 'WELCOME',
            priority: 35,
            explanation: 'Welcome the customer and set an expectation for the first visit.',
            reasons: classification.lifecycleReasons,
        };
    }
    return {
        actionType: 'SUGGEST_NEXT_VISIT',
        priority: 30,
        explanation: 'Suggest the next relevant visit while the relationship is healthy.',
        reasons: classification.lifecycleReasons,
    };
}
async function updateCustomerClassification(params) {
    const policy = await resolveActiveRetentionPolicy(params.merchantId, !params.dryRun);
    const customerRef = businessCustomerRef(params.merchantId, params.customerId);
    const initialSnapshot = await customerRef.get();
    if (!initialSnapshot.exists) {
        throw new CustomerCoreError(404, 'retention_customer_not_found', 'Business customer not found.', { merchant_id: params.merchantId, customer_id: params.customerId });
    }
    const initialData = snapshotDataRecord(initialSnapshot);
    const canonicalCustomerId = maybePayloadString(initialData, 'canonical_customer_id', 'canonicalCustomerId');
    if (!canonicalCustomerId) {
        return {
            merchant_id: params.merchantId,
            customer_id: params.customerId,
            status: 'CANONICAL_LINK_REQUIRED',
            policy_version: policy.version,
        };
    }
    const now = Date.now();
    const preview = classifyCustomer({
        totalVisits: pickNumber(initialData, 'total_visits') ?? 0,
        totalSpent: pickNumber(initialData, 'total_spent') ?? 0,
        lastVisitAt: pickNumber(initialData, 'last_visit_at'),
        explicitPreReturnActiveRelationship: pickBoolean(initialData, 'pre_return_active_relationship') === true,
        now,
    }, policy);
    if (params.dryRun) {
        return {
            merchant_id: params.merchantId,
            customer_id: params.customerId,
            canonical_customer_id: canonicalCustomerId,
            status: 'DRY_RUN',
            policy_version: policy.version,
            lifecycle_stage: preview.lifecycle,
            retention_status: preview.retention,
            lifecycle_reasons: preview.lifecycleReasons,
            retention_reasons: preview.retentionReasons,
            explanation: preview.explanation,
            days_since_activity: preview.daysSinceActivity,
        };
    }
    return admin.firestore().runTransaction(async (transaction) => {
        const customerSnapshot = await transaction.get(customerRef);
        if (!customerSnapshot.exists) {
            throw new CustomerCoreError(404, 'retention_customer_not_found', 'Business customer not found.', { merchant_id: params.merchantId, customer_id: params.customerId });
        }
        const customerData = snapshotDataRecord(customerSnapshot);
        const currentCanonicalCustomerId = maybePayloadString(customerData, 'canonical_customer_id', 'canonicalCustomerId');
        if (!currentCanonicalCustomerId) {
            return {
                merchant_id: params.merchantId,
                customer_id: params.customerId,
                status: 'CANONICAL_LINK_REQUIRED',
                policy_version: policy.version,
            };
        }
        const classification = classifyCustomer({
            totalVisits: pickNumber(customerData, 'total_visits') ?? 0,
            totalSpent: pickNumber(customerData, 'total_spent') ?? 0,
            lastVisitAt: pickNumber(customerData, 'last_visit_at'),
            explicitPreReturnActiveRelationship: pickBoolean(customerData, 'pre_return_active_relationship') === true,
            now,
        }, policy);
        const hasClassificationProjection = pickNumber(customerData, 'classification_schema_version') ===
            CLASSIFICATION_SCHEMA_VERSION;
        const previousLifecycle = hasClassificationProjection
            ? maybePayloadString(customerData, 'lifecycle_stage')
            : null;
        const previousRetention = hasClassificationProjection
            ? maybePayloadString(customerData, 'retention_status')
            : null;
        const transitions = [];
        if (previousLifecycle !== classification.lifecycle) {
            transitions.push({
                dimension: 'LIFECYCLE',
                from: previousLifecycle,
                to: classification.lifecycle,
                reasons: classification.lifecycleReasons,
                eventType: 'CUSTOMER_LIFECYCLE_TRANSITIONED',
            });
        }
        if (previousRetention !== classification.retention) {
            transitions.push({
                dimension: 'RETENTION',
                from: previousRetention,
                to: classification.retention,
                reasons: classification.retentionReasons,
                eventType: 'CUSTOMER_RETENTION_TRANSITIONED',
            });
        }
        const transitionRecords = transitions.map((item) => {
            const id = deterministicDocumentId('trn', [
                params.merchantId,
                params.customerId,
                item.dimension,
                item.from ?? 'NONE',
                item.to,
                `policy-v${policy.version}`,
                params.sourceType,
                params.sourceId,
            ]);
            const genericEvent = buildDomainEvent({
                eventType: item.eventType,
                merchantId: params.merchantId,
                canonicalCustomerId: currentCanonicalCustomerId,
                businessCustomerId: params.customerId,
                sourceType: params.sourceType === 'inactivity_scan' ? 'inactivity_scan' : 'classification',
                sourceId: id,
                correlationId: params.causationId ?? undefined,
                causationId: params.causationId,
                occurredAt: params.occurredAt,
                recordedAt: now,
                payload: {
                    transition_id: id,
                    dimension: item.dimension,
                    from: item.from,
                    to: item.to,
                    reasons: item.reasons,
                    policy_version: policy.version,
                },
            });
            let productEventType = null;
            if (item.from != null &&
                item.dimension === 'LIFECYCLE' &&
                item.to === 'RETURNING') {
                productEventType = 'CUSTOMER_RETURNED';
            }
            else if (item.from != null &&
                item.dimension === 'LIFECYCLE' &&
                ['NEW', 'ACTIVE', 'RETURNING'].includes(item.from) &&
                ['REGULAR', 'LOYAL', 'VIP', 'ADVOCATE'].includes(item.to)) {
                productEventType = 'CUSTOMER_BECAME_REGULAR';
            }
            else if (item.from != null &&
                item.dimension === 'RETENTION' &&
                item.to === 'AT_RISK') {
                productEventType = 'CUSTOMER_BECAME_AT_RISK';
            }
            else if (item.from != null &&
                item.dimension === 'RETENTION' &&
                item.to === 'INACTIVE') {
                productEventType = 'CUSTOMER_BECAME_INACTIVE';
            }
            else if (item.dimension === 'RETENTION' &&
                item.to === 'HEALTHY' &&
                item.from != null &&
                item.from !== 'HEALTHY') {
                productEventType = 'CUSTOMER_REACTIVATED';
            }
            const productEvent = productEventType == null
                ? null
                : buildDomainEvent({
                    eventType: productEventType,
                    merchantId: params.merchantId,
                    canonicalCustomerId: currentCanonicalCustomerId,
                    businessCustomerId: params.customerId,
                    sourceType: params.sourceType === 'inactivity_scan'
                        ? 'inactivity_scan'
                        : 'classification',
                    sourceId: id,
                    correlationId: params.causationId ?? undefined,
                    causationId: genericEvent.event_id,
                    occurredAt: params.occurredAt,
                    recordedAt: now,
                    payload: {
                        transition_id: id,
                        from: item.from,
                        to: item.to,
                        reasons: item.reasons,
                        policy_version: policy.version,
                    },
                });
            return {
                item,
                id,
                transitionRef: customerTransitionDocumentRef(params.merchantId, id),
                genericEvent,
                productEvent,
            };
        });
        const transitionEventRecords = transitionRecords.flatMap((record) => [record.genericEvent, record.productEvent]
            .filter((event) => event != null)
            .map((event) => ({
            event,
            eventRef: domainEventCollectionRef(params.merchantId).doc(event.event_id),
        })));
        const recommendationRef = customerRecommendationDocumentRef(params.merchantId, params.customerId);
        const [recommendationSnapshot, transitionSnapshots, eventSnapshots] = await Promise.all([
            transaction.get(recommendationRef),
            Promise.all(transitionRecords.map((record) => transaction.get(record.transitionRef))),
            Promise.all(transitionEventRecords.map((record) => transaction.get(record.eventRef))),
        ]);
        const customerPatch = {
            lifecycle_stage: classification.lifecycle,
            retention_status: classification.retention,
            lifecycle_reasons: classification.lifecycleReasons,
            retention_reasons: classification.retentionReasons,
            classification_explanation: classification.explanation,
            classification_schema_version: CLASSIFICATION_SCHEMA_VERSION,
            classification_policy_version: policy.version,
            classification_updated_at: now,
            updated_at: now,
        };
        const lastVisitAt = pickNumber(customerData, 'last_visit_at');
        customerPatch.classification_last_activity_at = lastVisitAt == null
            ? admin.firestore.FieldValue.delete()
            : lastVisitAt;
        transaction.set(customerRef, customerPatch, { merge: true });
        transitionRecords.forEach((record, index) => {
            if (!transitionSnapshots[index].exists) {
                transaction.set(record.transitionRef, {
                    id: record.id,
                    merchant_id: params.merchantId,
                    canonical_customer_id: currentCanonicalCustomerId,
                    business_customer_id: params.customerId,
                    dimension: record.item.dimension,
                    from_status: record.item.from,
                    to_status: record.item.to,
                    reasons: record.item.reasons,
                    explanation: classification.explanation,
                    policy_version: policy.version,
                    classification_schema_version: CLASSIFICATION_SCHEMA_VERSION,
                    source: {
                        type: params.sourceType,
                        id: params.sourceId,
                    },
                    correlation_id: params.causationId ?? record.genericEvent.event_id,
                    causation_id: params.causationId ?? null,
                    occurred_at: params.occurredAt,
                    recorded_at: now,
                });
            }
        });
        transitionEventRecords.forEach((record, index) => {
            if (!eventSnapshots[index].exists) {
                transaction.set(record.eventRef, record.event);
            }
        });
        const recommendation = nextBestActionFor(classification);
        const existingRecommendationData = recommendationSnapshot.exists
            ? snapshotDataRecord(recommendationSnapshot)
            : {};
        const recommendationChanged = maybePayloadString(existingRecommendationData, 'action_type') !==
            recommendation.actionType ||
            pickNumber(existingRecommendationData, 'policy_version') !== policy.version ||
            maybePayloadString(existingRecommendationData, 'lifecycle_stage') !==
                classification.lifecycle ||
            maybePayloadString(existingRecommendationData, 'retention_status') !==
                classification.retention;
        if (recommendationChanged) {
            transaction.set(recommendationRef, {
                id: params.customerId,
                merchant_id: params.merchantId,
                canonical_customer_id: currentCanonicalCustomerId,
                business_customer_id: params.customerId,
                action_type: recommendation.actionType,
                priority: recommendation.priority,
                explanation: recommendation.explanation,
                reasons: recommendation.reasons,
                lifecycle_stage: classification.lifecycle,
                retention_status: classification.retention,
                policy_version: policy.version,
                projection_version: 1,
                status: 'ACTIVE',
                generated_at: now,
                updated_at: now,
                ...(recommendationSnapshot.exists ? {} : { created_at: now }),
            }, { merge: true });
        }
        return {
            merchant_id: params.merchantId,
            customer_id: params.customerId,
            canonical_customer_id: currentCanonicalCustomerId,
            status: transitions.length > 0 ? 'TRANSITIONED' : 'CLASSIFIED',
            policy_version: policy.version,
            lifecycle_stage: classification.lifecycle,
            retention_status: classification.retention,
            lifecycle_reasons: classification.lifecycleReasons,
            retention_reasons: classification.retentionReasons,
            explanation: classification.explanation,
            days_since_activity: classification.daysSinceActivity,
            transition_ids: transitionRecords.map((record) => record.id),
            recommendation_action: recommendation.actionType,
        };
    });
}
async function handleRetentionPolicyUpsertRequest(req, body) {
    const payload = requireBodyObject(body);
    const merchantId = await resolveCustomerCoreMerchantId(req, payload);
    if (!isOwnerOrAdminRequest(req)) {
        throw new CustomerCoreError(403, 'retention_policy_owner_required', 'Only a business owner or admin can activate retention policies.', { merchant_id: merchantId });
    }
    const rawPolicy = payload.policy;
    const policyPayload = rawPolicy != null && typeof rawPolicy === 'object'
        ? rawPolicy
        : payload;
    const expectedCurrentVersion = parseNumber(payload.expected_current_version ?? payload.expectedCurrentVersion);
    const now = Date.now();
    return admin.firestore().runTransaction(async (transaction) => {
        const businessRef = businessDocumentRef(merchantId);
        const businessSnapshot = await transaction.get(businessRef);
        if (!businessSnapshot.exists) {
            throw new CustomerCoreError(404, 'retention_business_not_found', 'Business document not found.', { merchant_id: merchantId });
        }
        const businessData = snapshotDataRecord(businessSnapshot);
        const currentVersion = pickNumber(businessData, 'active_retention_policy_version') ?? 0;
        if (expectedCurrentVersion != null &&
            expectedCurrentVersion !== currentVersion) {
            throw new CustomerCoreError(409, 'retention_policy_version_conflict', 'The active retention policy changed; reload before saving.', {
                merchant_id: merchantId,
                expected_version: expectedCurrentVersion,
                active_version: currentVersion,
            });
        }
        const seeded = buildSeedRetentionPolicy(businessData);
        const nextVersion = currentVersion + 1;
        const policy = validateRetentionPolicy({
            schemaVersion: RETENTION_POLICY_SCHEMA_VERSION,
            version: nextVersion,
            activeDays: positiveIntegerOrDefault(policyPayload.active_days ?? policyPayload.activeDays, seeded.activeDays),
            attentionDays: positiveIntegerOrDefault(policyPayload.attention_days ?? policyPayload.attentionDays, seeded.attentionDays),
            riskDays: positiveIntegerOrDefault(policyPayload.risk_days ?? policyPayload.riskDays, seeded.riskDays),
            returningVisits: positiveIntegerOrDefault(policyPayload.returning_visits ?? policyPayload.returningVisits, seeded.returningVisits),
            regularVisits: positiveIntegerOrDefault(policyPayload.regular_visits ?? policyPayload.regularVisits, seeded.regularVisits),
            loyalVisits: positiveIntegerOrDefault(policyPayload.loyal_visits ?? policyPayload.loyalVisits, seeded.loyalVisits),
            vipSpendMzn: parseNumber(policyPayload.vip_spend_mzn ?? policyPayload.vipSpendMzn) ??
                seeded.vipSpendMzn,
            advocateVisits: positiveIntegerOrDefault(policyPayload.advocate_visits ?? policyPayload.advocateVisits, seeded.advocateVisits),
            advocateSpendMzn: parseNumber(policyPayload.advocate_spend_mzn ?? policyPayload.advocateSpendMzn) ?? seeded.advocateSpendMzn,
        });
        const policyRef = retentionPolicyDocumentRef(merchantId, nextVersion);
        const existingPolicySnapshot = await transaction.get(policyRef);
        if (existingPolicySnapshot.exists) {
            throw new CustomerCoreError(409, 'retention_policy_version_conflict', 'The next retention policy version already exists.', { merchant_id: merchantId, policy_version: nextVersion });
        }
        transaction.set(policyRef, retentionPolicyDocumentData(merchantId, policy, 'CONFIGURED', now, req.appUserId));
        if (currentVersion > 0) {
            transaction.set(retentionPolicyDocumentRef(merchantId, currentVersion), {
                status: 'SUPERSEDED',
                superseded_at: now,
                superseded_by_version: nextVersion,
            }, { merge: true });
        }
        transaction.set(businessRef, {
            active_retention_policy_version: nextVersion,
            retention_policy_schema_version: RETENTION_POLICY_SCHEMA_VERSION,
            retention_policy_updated_at: now,
        }, { merge: true });
        return {
            merchant_id: merchantId,
            policy_version: nextVersion,
            status: 'ACTIVE',
            effective_at: now,
        };
    });
}
async function handleRetentionClassificationScanRequest(req, body) {
    const payload = requireBodyObject(body);
    const merchantId = await resolveCustomerCoreMerchantId(req, payload);
    const apply = maybePayloadBoolean(payload, 'apply') ?? false;
    if (apply && !isOwnerOrAdminRequest(req)) {
        throw new CustomerCoreError(403, 'retention_scan_owner_required', 'Only a business owner or admin can apply a retention scan.', { merchant_id: merchantId });
    }
    const limit = clampLimit(payload.limit, 50, 200);
    const startAfterCustomerId = maybePayloadString(payload, 'start_after_customer_id', 'startAfterCustomerId');
    let query = businessDocumentRef(merchantId)
        .collection('customers')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);
    if (startAfterCustomerId)
        query = query.startAfter(startAfterCustomerId);
    const snapshot = await query.get();
    const now = Date.now();
    const scanId = `manual:${new Date(now).toISOString().substring(0, 10)}`;
    const results = [];
    for (const doc of snapshot.docs) {
        results.push(await updateCustomerClassification({
            merchantId,
            customerId: doc.id,
            sourceType: 'inactivity_scan',
            sourceId: scanId,
            occurredAt: now,
            dryRun: !apply,
        }));
    }
    const nextCursor = snapshot.docs.length === limit
        ? snapshot.docs[snapshot.docs.length - 1].id
        : null;
    return {
        merchant_id: merchantId,
        mode: apply ? 'apply' : 'dry_run',
        processed: snapshot.size,
        has_more: nextCursor != null,
        next_cursor: nextCursor,
        results,
    };
}
async function recordAdminAuditEvent(client, req, event) {
    const sql = `
    INSERT INTO admin_audit_events (
      id,
      actor_app_user_id,
      actor_firebase_uid,
      actor_role,
      action,
      target_type,
      target_id,
      merchant_id,
      details,
      created_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
  `;
    await client.query(sql, [
        (0, crypto_1.randomUUID)(),
        req.appUserId ?? null,
        req.auth?.uid ?? null,
        req.appUserRole ?? null,
        event.action,
        event.targetType,
        event.targetId ?? null,
        event.merchantId ?? null,
        event.details ?? null,
        Date.now(),
    ]);
}
function pickNumber(payload, key) {
    const value = payload[key];
    if (typeof value === 'number' && Number.isFinite(value))
        return value;
    if (isNonEmptyString(value)) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}
async function upsertCustomer(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const name = pickString(payload, 'name');
    const phone = pickString(payload, 'phone');
    const totalPoints = pickNumber(payload, 'total_points') ?? pickNumber(payload, 'totalPoints') ?? 0;
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? pickNumber(payload, 'updatedAt') ?? createdAt;
    if (!name || !phone) {
        throw new Error('Missing customer fields');
    }
    const sql = `
    INSERT INTO customers (
      id,
      merchant_id,
      name,
      phone,
      total_points,
      created_at,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      name = EXCLUDED.name,
      phone = EXCLUDED.phone,
      total_points = EXCLUDED.total_points,
      created_at = LEAST(customers.created_at, EXCLUDED.created_at),
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [id, merchantId, name, phone, totalPoints, createdAt, updatedAt]);
}
async function upsertSale(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const amount = pickNumber(payload, 'amount');
    const points = pickNumber(payload, 'points');
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const deviceId = pickString(payload, 'device_id') ?? pickString(payload, 'deviceId');
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ?? pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ?? pickString(payload, 'updatedByAppUserId');
    if (!customerId || amount == null || points == null) {
        throw new Error('Missing sale fields');
    }
    const sql = `
    INSERT INTO sales (
      id,
      merchant_id,
      customer_id,
      amount,
      points,
      created_at,
      device_id,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      amount = EXCLUDED.amount,
      points = EXCLUDED.points,
      created_at = EXCLUDED.created_at,
      device_id = EXCLUDED.device_id,
      created_by_app_user_id = COALESCE(EXCLUDED.created_by_app_user_id, sales.created_by_app_user_id),
      updated_by_app_user_id = COALESCE(EXCLUDED.updated_by_app_user_id, sales.updated_by_app_user_id)
  `;
    await pool.query(sql, [
        id,
        merchantId,
        customerId,
        amount,
        points,
        createdAt,
        deviceId,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertMerchantItem(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const name = pickString(payload, 'name');
    const type = pickString(payload, 'type');
    const defaultPrice = pickNumber(payload, 'default_price') ?? pickNumber(payload, 'defaultPrice');
    const isActive = pickBoolean(payload, 'is_active') ?? pickBoolean(payload, 'isActive') ?? true;
    const displayOrder = pickNumber(payload, 'display_order') ?? pickNumber(payload, 'displayOrder') ?? 0;
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? pickNumber(payload, 'updatedAt') ?? createdAt;
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ?? pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ?? pickString(payload, 'updatedByAppUserId');
    if (!name || !type) {
        throw new Error('Missing merchant item fields');
    }
    const sql = `
    INSERT INTO merchant_items (
      id,
      merchant_id,
      name,
      type,
      default_price,
      is_active,
      display_order,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      name = EXCLUDED.name,
      type = EXCLUDED.type,
      default_price = EXCLUDED.default_price,
      is_active = EXCLUDED.is_active,
      display_order = EXCLUDED.display_order,
      created_at = LEAST(merchant_items.created_at, EXCLUDED.created_at),
      updated_at = EXCLUDED.updated_at,
      created_by_app_user_id = COALESCE(EXCLUDED.created_by_app_user_id, merchant_items.created_by_app_user_id),
      updated_by_app_user_id = COALESCE(EXCLUDED.updated_by_app_user_id, merchant_items.updated_by_app_user_id)
  `;
    await pool.query(sql, [
        id,
        merchantId,
        name,
        type,
        defaultPrice,
        isActive,
        displayOrder,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertSaleItem(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const saleId = pickString(payload, 'sale_id') ?? pickString(payload, 'saleId');
    const merchantItemId = pickString(payload, 'merchant_item_id') ?? pickString(payload, 'merchantItemId');
    const nameSnapshot = pickString(payload, 'name_snapshot') ?? pickString(payload, 'nameSnapshot');
    const typeSnapshot = pickString(payload, 'type_snapshot') ?? pickString(payload, 'typeSnapshot');
    const quantity = pickNumber(payload, 'quantity') ?? 1;
    const unitPrice = pickNumber(payload, 'unit_price') ?? pickNumber(payload, 'unitPrice');
    const subtotal = pickNumber(payload, 'subtotal');
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? pickNumber(payload, 'updatedAt') ?? createdAt;
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ?? pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ?? pickString(payload, 'updatedByAppUserId');
    if (!saleId || !merchantItemId || !nameSnapshot || !typeSnapshot) {
        throw new Error('Missing sale item fields');
    }
    const parentSale = await pool.query('SELECT id FROM sales WHERE merchant_id = $1 AND id = $2 LIMIT 1', [merchantId, saleId]);
    if (parentSale.rowCount === 0) {
        throw new Error('Missing parent sale');
    }
    const sql = `
    INSERT INTO sale_items (
      id,
      merchant_id,
      sale_id,
      merchant_item_id,
      name_snapshot,
      type_snapshot,
      quantity,
      unit_price,
      subtotal,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      sale_id = EXCLUDED.sale_id,
      merchant_item_id = EXCLUDED.merchant_item_id,
      name_snapshot = EXCLUDED.name_snapshot,
      type_snapshot = EXCLUDED.type_snapshot,
      quantity = EXCLUDED.quantity,
      unit_price = EXCLUDED.unit_price,
      subtotal = EXCLUDED.subtotal,
      created_at = LEAST(sale_items.created_at, EXCLUDED.created_at),
      updated_at = EXCLUDED.updated_at,
      created_by_app_user_id = COALESCE(EXCLUDED.created_by_app_user_id, sale_items.created_by_app_user_id),
      updated_by_app_user_id = COALESCE(EXCLUDED.updated_by_app_user_id, sale_items.updated_by_app_user_id)
  `;
    await pool.query(sql, [
        id,
        merchantId,
        saleId,
        merchantItemId,
        nameSnapshot,
        typeSnapshot,
        quantity,
        unitPrice,
        subtotal,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertReward(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const name = pickString(payload, 'name');
    const pointsRequired = pickNumber(payload, 'points_required') ?? pickNumber(payload, 'pointsRequired');
    const description = pickString(payload, 'description');
    const active = pickBoolean(payload, 'active') ?? true;
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? pickNumber(payload, 'updatedAt') ?? createdAt;
    if (!name || pointsRequired == null) {
        throw new Error('Missing reward fields');
    }
    const sql = `
    INSERT INTO rewards (
      id,
      merchant_id,
      name,
      points_required,
      description,
      active,
      created_at,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      name = EXCLUDED.name,
      points_required = EXCLUDED.points_required,
      description = EXCLUDED.description,
      active = EXCLUDED.active,
      created_at = LEAST(rewards.created_at, EXCLUDED.created_at),
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        name,
        pointsRequired,
        description,
        active,
        createdAt,
        updatedAt,
    ]);
}
async function upsertRedemption(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const rewardId = pickString(payload, 'reward_id') ?? pickString(payload, 'rewardId');
    const pointsSpent = pickNumber(payload, 'points_spent') ?? pickNumber(payload, 'pointsSpent');
    const redeemedAt = pickNumber(payload, 'redeemed_at') ?? pickNumber(payload, 'redeemedAt') ?? Date.now();
    if (!customerId || !rewardId || pointsSpent == null) {
        throw new Error('Missing redemption fields');
    }
    const sql = `
    INSERT INTO redemptions (
      id,
      merchant_id,
      customer_id,
      reward_id,
      points_spent,
      redeemed_at
    ) VALUES ($1,$2,$3,$4,$5,$6)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      reward_id = EXCLUDED.reward_id,
      points_spent = EXCLUDED.points_spent,
      redeemed_at = EXCLUDED.redeemed_at
  `;
    await pool.query(sql, [id, merchantId, customerId, rewardId, pointsSpent, redeemedAt]);
}
async function upsertAppointment(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const scheduledDate = pickNumber(payload, 'scheduled_date') ?? pickNumber(payload, 'scheduledDate');
    const status = pickString(payload, 'status') ?? 'scheduled';
    const source = pickString(payload, 'source') ?? 'app';
    const reminderSent = pickBoolean(payload, 'reminder_sent') ?? pickBoolean(payload, 'reminderSent') ?? false;
    const merchantItemId = pickString(payload, 'merchant_item_id') ?? pickString(payload, 'merchantItemId');
    const staffAppUserId = pickString(payload, 'staff_app_user_id') ?? pickString(payload, 'staffAppUserId');
    const durationMinutes = pickNumber(payload, 'duration_minutes') ?? pickNumber(payload, 'durationMinutes');
    const notes = pickString(payload, 'notes');
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? pickNumber(payload, 'updatedAt') ?? createdAt;
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ?? pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ?? pickString(payload, 'updatedByAppUserId');
    if (!customerId || scheduledDate == null) {
        throw new Error('Missing appointment fields');
    }
    const sql = `
    INSERT INTO appointments (
      id,
      merchant_id,
      customer_id,
      scheduled_date,
      status,
      source,
      reminder_sent,
      merchant_item_id,
      staff_app_user_id,
      duration_minutes,
      notes,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      scheduled_date = EXCLUDED.scheduled_date,
      status = EXCLUDED.status,
      source = EXCLUDED.source,
      reminder_sent = EXCLUDED.reminder_sent,
      merchant_item_id = EXCLUDED.merchant_item_id,
      staff_app_user_id = EXCLUDED.staff_app_user_id,
      duration_minutes = EXCLUDED.duration_minutes,
      notes = EXCLUDED.notes,
      created_at = LEAST(appointments.created_at, EXCLUDED.created_at),
      updated_at = EXCLUDED.updated_at,
      created_by_app_user_id = COALESCE(EXCLUDED.created_by_app_user_id, appointments.created_by_app_user_id),
      updated_by_app_user_id = COALESCE(EXCLUDED.updated_by_app_user_id, appointments.updated_by_app_user_id)
  `;
    await pool.query(sql, [
        id,
        merchantId,
        customerId,
        scheduledDate,
        status,
        source,
        reminderSent,
        merchantItemId,
        staffAppUserId,
        durationMinutes,
        notes,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertRetentionMetric(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const lastVisitAt = pickNumber(payload, 'last_visit_at') ?? pickNumber(payload, 'lastVisitAt');
    const daysInactive = pickNumber(payload, 'days_inactive') ?? pickNumber(payload, 'daysInactive') ?? 0;
    const riskLevel = pickString(payload, 'risk_level') ?? pickString(payload, 'riskLevel') ?? 'active';
    const totalVisits = pickNumber(payload, 'total_visits') ?? pickNumber(payload, 'totalVisits') ?? 0;
    const averageVisitInterval = pickNumber(payload, 'average_visit_interval') ?? pickNumber(payload, 'averageVisitInterval') ?? 0;
    const totalSpent = pickNumber(payload, 'total_spent') ?? pickNumber(payload, 'totalSpent') ?? 0;
    const isRecurring = pickBoolean(payload, 'is_recurring') ?? pickBoolean(payload, 'isRecurring') ?? false;
    const recovered = pickBoolean(payload, 'recovered') ?? false;
    const updatedAt = pickNumber(payload, 'updated_at') ?? pickNumber(payload, 'updatedAt') ?? Date.now();
    if (!customerId) {
        throw new Error('Missing retention metric fields');
    }
    const sql = `
    INSERT INTO retention_metrics (
      id,
      merchant_id,
      customer_id,
      last_visit_at,
      days_inactive,
      risk_level,
      total_visits,
      average_visit_interval,
      total_spent,
      is_recurring,
      recovered,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      last_visit_at = EXCLUDED.last_visit_at,
      days_inactive = EXCLUDED.days_inactive,
      risk_level = EXCLUDED.risk_level,
      total_visits = EXCLUDED.total_visits,
      average_visit_interval = EXCLUDED.average_visit_interval,
      total_spent = EXCLUDED.total_spent,
      is_recurring = EXCLUDED.is_recurring,
      recovered = EXCLUDED.recovered,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        customerId,
        lastVisitAt,
        daysInactive,
        riskLevel,
        totalVisits,
        averageVisitInterval,
        totalSpent,
        isRecurring,
        recovered,
        updatedAt,
    ]);
}
async function upsertSubscriptionState(merchantId, payload) {
    const planCode = pickString(payload, 'plan_code') ?? pickString(payload, 'planCode');
    const planNameInput = pickString(payload, 'plan_name') ?? pickString(payload, 'planName');
    const status = pickString(payload, 'status') ??
        pickString(payload, 'subscription_status') ??
        'TRIAL';
    if (!planCode) {
        throw new Error('Missing plan data');
    }
    const planVersionInput = pickNumber(payload, 'plan_version') ??
        pickNumber(payload, 'planVersion') ??
        null;
    const pricingVersionInput = pickNumber(payload, 'pricing_version') ??
        pickNumber(payload, 'pricingVersion') ??
        null;
    const trialEndsAt = pickNumber(payload, 'trial_ends_at') ?? pickNumber(payload, 'trialEndsAt');
    const graceEndsAt = pickNumber(payload, 'grace_ends_at') ?? pickNumber(payload, 'graceEndsAt');
    const periodStart = pickNumber(payload, 'period_start') ?? pickNumber(payload, 'periodStart');
    const periodEnd = pickNumber(payload, 'period_end') ?? pickNumber(payload, 'periodEnd');
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const resolved = await resolvePlanAndPricing(merchantId, planCode, planNameInput, planVersionInput, pricingVersionInput);
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
async function upsertAppUser(merchantId, payload, entityId) {
    const id = pickString(payload, 'id') ?? entityId;
    const phone = pickString(payload, 'phone');
    if (!phone) {
        throw new Error('Missing app user phone');
    }
    const roleInput = pickString(payload, 'role') ?? 'STAFF';
    const role = roleInput.trim().toUpperCase() === 'OWNER' ? 'OWNER' : 'STAFF';
    const statusInput = pickString(payload, 'status') ?? 'ACTIVE';
    const statusNormalized = statusInput.trim().toUpperCase();
    const status = statusNormalized === 'INVITED'
        ? 'INVITED'
        : statusNormalized === 'INACTIVE'
            ? 'INACTIVE'
            : 'ACTIVE';
    const invitedAt = pickNumber(payload, 'invited_at') ?? pickNumber(payload, 'invitedAt');
    const acceptedAt = pickNumber(payload, 'accepted_at') ?? pickNumber(payload, 'acceptedAt');
    const invitedByAppUserId = pickString(payload, 'invited_by_app_user_id') ??
        pickString(payload, 'invitedByAppUserId');
    const deactivatedAt = pickNumber(payload, 'deactivated_at') ?? pickNumber(payload, 'deactivatedAt');
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const lastLoginAt = pickNumber(payload, 'last_login_at') ?? pickNumber(payload, 'lastLoginAt');
    const sql = `
    INSERT INTO app_users (
      id,
      merchant_id,
      phone,
      role,
      status,
      invited_at,
      accepted_at,
      invited_by_app_user_id,
      deactivated_at,
      created_at,
      updated_at,
      last_login_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      phone = EXCLUDED.phone,
      role = EXCLUDED.role,
      status = EXCLUDED.status,
      invited_at = EXCLUDED.invited_at,
      accepted_at = EXCLUDED.accepted_at,
      invited_by_app_user_id = EXCLUDED.invited_by_app_user_id,
      deactivated_at = EXCLUDED.deactivated_at,
      updated_at = EXCLUDED.updated_at,
      last_login_at = EXCLUDED.last_login_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        phone,
        role,
        status,
        invitedAt,
        acceptedAt,
        invitedByAppUserId,
        deactivatedAt,
        createdAt,
        updatedAt,
        lastLoginAt,
    ]);
}
async function upsertCustomerRiskScore(merchantId, payload, entityId) {
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    if (!customerId) {
        throw new Error('Missing customer_id');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const daysSinceVisit = pickNumber(payload, 'days_since_visit') ??
        pickNumber(payload, 'daysSinceVisit') ??
        0;
    const riskLevel = pickString(payload, 'risk_level') ?? 'green';
    const priority = pickNumber(payload, 'priority') ?? 0;
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const sql = `
    INSERT INTO customer_risk_scores (
      id,
      merchant_id,
      customer_id,
      days_since_visit,
      risk_level,
      priority,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      days_since_visit = EXCLUDED.days_since_visit,
      risk_level = EXCLUDED.risk_level,
      priority = EXCLUDED.priority,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        customerId,
        daysSinceVisit,
        riskLevel,
        priority,
        updatedAt,
    ]);
    if (normalizeRiskLevel(riskLevel) === 'red') {
        await ensureRecoveryTaskForRedCustomer(merchantId, customerId, updatedAt);
    }
    await maybeQueueNearRewardReminder(merchantId, customerId, updatedAt);
}
function normalizeRiskLevel(riskLevel) {
    const normalized = (riskLevel ?? '').trim().toLowerCase();
    if (normalized === 'yellow')
        return 'yellow';
    if (normalized === 'orange')
        return 'orange';
    if (normalized === 'red')
        return 'red';
    return 'green';
}
async function ensureRecoveryTaskForRedCustomer(merchantId, customerId, now) {
    const sql = `
    INSERT INTO recovery_tasks (
      id,
      merchant_id,
      customer_id,
      priority,
      status,
      due_at,
      notes,
      created_at,
      updated_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
    ON CONFLICT (merchant_id, customer_id, open_slot) DO NOTHING
  `;
    await pool.query(sql, [
        (0, crypto_1.randomUUID)(),
        merchantId,
        customerId,
        'high',
        'open',
        now,
        'Auto-created because customer moved to RED risk level',
        now,
        now,
    ]);
}
async function maybeQueueNearRewardReminder(merchantId, customerId, now) {
    const customerSql = `
    SELECT total_points
    FROM customers
    WHERE merchant_id = $1 AND id = $2
    LIMIT 1
  `;
    const customerResult = await pool.query(customerSql, [merchantId, customerId]);
    if (!customerResult.rows[0])
        return;
    const totalPoints = Number(customerResult.rows[0].total_points ?? 0);
    if (!Number.isFinite(totalPoints))
        return;
    const rewardSql = `
    SELECT points_required, name
    FROM rewards
    WHERE merchant_id = $1
      AND active = true
      AND points_required > $2
    ORDER BY points_required ASC
    LIMIT 1
  `;
    const rewardResult = await pool.query(rewardSql, [merchantId, totalPoints]);
    const nextReward = rewardResult.rows[0] ?? null;
    if (!nextReward)
        return;
    const requiredPoints = Number(nextReward.points_required ?? 0);
    const delta = requiredPoints - totalPoints;
    if (!Number.isFinite(requiredPoints) || delta < 0 || delta > 20) {
        return;
    }
    const duplicateSql = `
    SELECT 1
    FROM recovery_actions
    WHERE merchant_id = $1
      AND customer_id = $2
      AND action_type = 'NEAR_REWARD_REMINDER'
      AND created_at >= $3
    LIMIT 1
  `;
    const duplicateResult = await pool.query(duplicateSql, [merchantId, customerId, now - 24 * 60 * 60 * 1000]);
    if (duplicateResult.rows.length > 0) {
        return;
    }
    const actionSql = `
    INSERT INTO recovery_actions (
      id,
      merchant_id,
      customer_id,
      task_id,
      action_type,
      payload,
      created_at,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
  `;
    const payload = {
        points_remaining: delta,
        total_points: totalPoints,
        reward_name: String(nextReward.name ?? 'recompensa'),
    };
    await pool.query(actionSql, [
        (0, crypto_1.randomUUID)(),
        merchantId,
        customerId,
        null,
        'NEAR_REWARD_REMINDER',
        payload,
        now,
        now,
    ]);
    await admin
        .firestore()
        .collection('businesses')
        .doc(merchantId)
        .collection('notification_queue')
        .add({
        merchant_id: merchantId,
        channel: 'whatsapp',
        payload: {
            type: 'near_reward_reminder',
            customer_id: customerId,
            points_remaining: delta,
            reward_name: String(nextReward.name ?? 'recompensa'),
        },
        scheduled_at: now,
        status: 'queued',
        created_at: now,
    });
}
async function runSurveyCompletedAutomation(merchantId, surveyId, customerId, answers, responseId, now) {
    const numericAnswers = answers
        .map((row) => pickNumber(row, 'answer_numeric') ?? pickNumber(row, 'answerNumeric'))
        .filter((value) => value != null && Number.isFinite(value));
    const avgScore = numericAnswers.length === 0
        ? null
        : numericAnswers.reduce((sum, value) => sum + value, 0) / numericAnswers.length;
    const actionPayload = {
        survey_id: surveyId,
        response_id: responseId,
        answers_count: answers.length,
        avg_score: avgScore,
    };
    await pool.query(`
    INSERT INTO recovery_actions (
      id,
      merchant_id,
      customer_id,
      task_id,
      action_type,
      payload,
      created_at,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
    `, [
        (0, crypto_1.randomUUID)(),
        merchantId,
        customerId,
        null,
        'SURVEY_COMPLETED',
        actionPayload,
        now,
        now,
    ]);
    if (!customerId || avgScore == null) {
        return;
    }
    const customerRiskSql = `
    SELECT risk_level
    FROM customer_risk_scores
    WHERE merchant_id = $1 AND customer_id = $2
    LIMIT 1
  `;
    const riskResult = await pool.query(customerRiskSql, [merchantId, customerId]);
    if (!riskResult.rows[0]) {
        return;
    }
    const current = normalizeRiskLevel(String(riskResult.rows[0].risk_level ?? 'green'));
    let next = current;
    if (avgScore >= 4) {
        if (current === 'red')
            next = 'orange';
        else if (current === 'orange')
            next = 'yellow';
        else if (current === 'yellow')
            next = 'green';
    }
    else if (avgScore <= 2) {
        if (current === 'green')
            next = 'yellow';
        else if (current === 'yellow')
            next = 'orange';
        else if (current === 'orange')
            next = 'red';
    }
    if (next === current) {
        return;
    }
    await pool.query(`
    UPDATE customer_risk_scores
    SET risk_level = $3,
        updated_at = $4
    WHERE merchant_id = $1
      AND customer_id = $2
    `, [merchantId, customerId, next, now]);
    if (next === 'red') {
        await ensureRecoveryTaskForRedCustomer(merchantId, customerId, now);
    }
}
async function upsertRecoveryTask(merchantId, payload, entityId) {
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    if (!customerId) {
        throw new Error('Missing customer_id');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const priority = pickString(payload, 'priority') ?? 'medium';
    const status = pickString(payload, 'status') ?? 'open';
    const dueAt = pickNumber(payload, 'due_at') ?? pickNumber(payload, 'dueAt');
    const notes = pickString(payload, 'notes');
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO recovery_tasks (
      id,
      merchant_id,
      customer_id,
      priority,
      status,
      due_at,
      notes,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      priority = EXCLUDED.priority,
      status = EXCLUDED.status,
      due_at = EXCLUDED.due_at,
      notes = EXCLUDED.notes,
      created_by_app_user_id = COALESCE(recovery_tasks.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        customerId,
        priority,
        status,
        dueAt,
        notes,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertRecoveryAction(merchantId, payload, entityId) {
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const actionType = pickString(payload, 'action_type') ?? pickString(payload, 'actionType');
    if (!customerId || !actionType) {
        throw new Error('Missing recovery action data');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const taskId = pickString(payload, 'task_id') ?? pickString(payload, 'taskId');
    const payloadValue = payload['payload'] && typeof payload['payload'] === 'object'
        ? payload['payload']
        : null;
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO recovery_actions (
      id,
      merchant_id,
      customer_id,
      task_id,
      action_type,
      payload,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      customer_id = EXCLUDED.customer_id,
      task_id = EXCLUDED.task_id,
      action_type = EXCLUDED.action_type,
      payload = EXCLUDED.payload,
      created_by_app_user_id = COALESCE(recovery_actions.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        customerId,
        taskId,
        actionType,
        payloadValue,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertVisitReport(merchantId, payload, entityId) {
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const resultValue = pickString(payload, 'result');
    if (!customerId || !resultValue) {
        throw new Error('Missing visit report data');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const taskId = pickString(payload, 'task_id') ?? pickString(payload, 'taskId');
    const notes = pickString(payload, 'notes');
    const visitedAt = pickNumber(payload, 'visited_at') ?? pickNumber(payload, 'visitedAt') ?? Date.now();
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO visit_reports (
      id,
      merchant_id,
      task_id,
      customer_id,
      result,
      notes,
      visited_at,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      task_id = EXCLUDED.task_id,
      customer_id = EXCLUDED.customer_id,
      result = EXCLUDED.result,
      notes = EXCLUDED.notes,
      visited_at = EXCLUDED.visited_at,
      created_by_app_user_id = COALESCE(visit_reports.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        taskId,
        customerId,
        resultValue,
        notes,
        visitedAt,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertSurvey(merchantId, payload, entityId) {
    const title = pickString(payload, 'title');
    if (!title) {
        throw new Error('Missing survey title');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const description = pickString(payload, 'description');
    const isActive = pickBoolean(payload, 'is_active') ?? pickBoolean(payload, 'isActive') ?? true;
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO surveys (
      id,
      merchant_id,
      title,
      description,
      is_active,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      title = EXCLUDED.title,
      description = EXCLUDED.description,
      is_active = EXCLUDED.is_active,
      created_by_app_user_id = COALESCE(surveys.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        title,
        description,
        isActive,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertSurveyQuestion(merchantId, payload, entityId) {
    const surveyId = pickString(payload, 'survey_id') ?? pickString(payload, 'surveyId');
    const questionText = pickString(payload, 'question_text') ?? pickString(payload, 'questionText');
    if (!surveyId || !questionText) {
        throw new Error('Missing survey question data');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const questionType = pickString(payload, 'question_type') ?? pickString(payload, 'questionType') ?? 'SHORT_TEXT';
    const sortOrder = pickNumber(payload, 'sort_order') ?? pickNumber(payload, 'sortOrder') ?? 0;
    const isRequired = pickBoolean(payload, 'is_required') ?? pickBoolean(payload, 'isRequired') ?? false;
    const optionsPayload = Array.isArray(payload.options_payload)
        ? payload.options_payload
        : Array.isArray(payload.options)
            ? payload.options
            : [];
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO survey_questions (
      id,
      merchant_id,
      survey_id,
      question_text,
      question_type,
      sort_order,
      is_required,
      options_payload,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      survey_id = EXCLUDED.survey_id,
      question_text = EXCLUDED.question_text,
      question_type = EXCLUDED.question_type,
      sort_order = EXCLUDED.sort_order,
      is_required = EXCLUDED.is_required,
      options_payload = EXCLUDED.options_payload,
      created_by_app_user_id = COALESCE(survey_questions.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        surveyId,
        questionText,
        questionType,
        sortOrder,
        isRequired,
        optionsPayload,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function upsertSurveyResponse(merchantId, payload, entityId) {
    const surveyId = pickString(payload, 'survey_id') ?? pickString(payload, 'surveyId');
    if (!surveyId) {
        throw new Error('Missing survey_id');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const customerId = pickString(payload, 'customer_id') ?? pickString(payload, 'customerId');
    const channel = pickString(payload, 'channel');
    const submittedAt = pickNumber(payload, 'submitted_at') ?? pickNumber(payload, 'submittedAt') ?? Date.now();
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO survey_responses (
      id,
      merchant_id,
      survey_id,
      customer_id,
      submitted_at,
      channel,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      survey_id = EXCLUDED.survey_id,
      customer_id = EXCLUDED.customer_id,
      submitted_at = EXCLUDED.submitted_at,
      channel = EXCLUDED.channel,
      created_by_app_user_id = COALESCE(survey_responses.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        surveyId,
        customerId,
        submittedAt,
        channel,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
    const answers = Array.isArray(payload.answers) ? payload.answers : [];
    for (const [index, answer] of answers.entries()) {
        const row = answer;
        const questionId = pickString(row, 'question_id') ?? pickString(row, 'questionId') ?? '';
        const answerId = pickString(row, 'id') ??
            deterministicDocumentId('sra', [merchantId, id, questionId, String(index)]);
        await upsertSurveyResponseAnswer(merchantId, {
            ...row,
            response_id: id,
        }, answerId);
    }
}
async function upsertSurveyResponseAnswer(merchantId, payload, entityId) {
    const responseId = pickString(payload, 'response_id') ?? pickString(payload, 'responseId');
    const questionId = pickString(payload, 'question_id') ?? pickString(payload, 'questionId');
    if (!responseId || !questionId) {
        throw new Error('Missing survey answer data');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const answerText = pickString(payload, 'answer_text') ?? pickString(payload, 'answerText');
    const answerNumeric = pickNumber(payload, 'answer_numeric') ?? pickNumber(payload, 'answerNumeric');
    const answerBool = pickBoolean(payload, 'answer_bool') ?? pickBoolean(payload, 'answerBool');
    const createdAt = pickNumber(payload, 'created_at') ?? pickNumber(payload, 'createdAt') ?? Date.now();
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const createdByAppUserId = pickString(payload, 'created_by_app_user_id') ??
        pickString(payload, 'createdByAppUserId');
    const updatedByAppUserId = pickString(payload, 'updated_by_app_user_id') ??
        pickString(payload, 'updatedByAppUserId');
    const sql = `
    INSERT INTO survey_response_answers (
      id,
      merchant_id,
      response_id,
      question_id,
      answer_text,
      answer_numeric,
      answer_bool,
      created_at,
      updated_at,
      created_by_app_user_id,
      updated_by_app_user_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (id) DO UPDATE SET
      merchant_id = EXCLUDED.merchant_id,
      response_id = EXCLUDED.response_id,
      question_id = EXCLUDED.question_id,
      answer_text = EXCLUDED.answer_text,
      answer_numeric = EXCLUDED.answer_numeric,
      answer_bool = EXCLUDED.answer_bool,
      created_by_app_user_id = COALESCE(survey_response_answers.created_by_app_user_id, EXCLUDED.created_by_app_user_id),
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = EXCLUDED.updated_at
  `;
    await pool.query(sql, [
        id,
        merchantId,
        responseId,
        questionId,
        answerText,
        answerNumeric,
        answerBool,
        createdAt,
        updatedAt,
        createdByAppUserId,
        updatedByAppUserId,
    ]);
}
async function resolvePlanAndPricing(merchantId, planCode, planNameInput, planVersionInput, pricingVersionInput) {
    const existing = await fetchSubscriptionState(merchantId);
    const samePlan = existing?.plan_code === planCode;
    const activePlan = await fetchActivePlan(planCode);
    const activePricingVersion = await fetchActivePricingVersion(planCode);
    const planVersion = planVersionInput ??
        (samePlan ? existing?.plan_version : null) ??
        activePlan?.version ??
        1;
    const pricingVersion = pricingVersionInput ??
        (samePlan ? existing?.pricing_version : null) ??
        activePricingVersion ??
        1;
    const planName = planNameInput ??
        (samePlan ? existing?.plan_name : null) ??
        activePlan?.name ??
        planCode;
    return { planName, planVersion, pricingVersion };
}
async function fetchSubscriptionState(merchantId) {
    const sql = `
    SELECT plan_code, plan_name, plan_version, pricing_version
    FROM subscription_state
    WHERE merchant_id = $1
    LIMIT 1
  `;
    const result = await pool.query(sql, [merchantId]);
    return result.rows[0] ?? null;
}
async function fetchActivePlan(planCode) {
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
async function fetchActivePricingVersion(planCode) {
    const sql = `
    SELECT pricing_version
    FROM plan_prices
    WHERE plan_code = $1 AND is_active = true
    ORDER BY pricing_version DESC
    LIMIT 1
  `;
    const result = await pool.query(sql, [planCode]);
    if (!result.rows[0])
        return null;
    return Number(result.rows[0].pricing_version) || null;
}
async function upsertEntitlement(merchantId, payload, entityId) {
    const featureKey = pickString(payload, 'feature_key') ?? pickString(payload, 'featureKey');
    if (!featureKey) {
        throw new Error('Missing feature key');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const isEnabled = pickBoolean(payload, 'is_enabled') ??
        pickBoolean(payload, 'isEnabled') ??
        true;
    const limitValue = pickNumber(payload, 'limit_value') ?? pickNumber(payload, 'limitValue');
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
async function upsertFeatureFlag(merchantId, payload, entityId) {
    const flagKey = pickString(payload, 'flag_key') ?? pickString(payload, 'flagKey');
    if (!flagKey) {
        throw new Error('Missing flag key');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const isEnabled = pickBoolean(payload, 'is_enabled') ??
        pickBoolean(payload, 'isEnabled') ??
        true;
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const payloadValue = payload['payload'] && typeof payload['payload'] === 'object'
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
async function upsertRemoteConfig(merchantId, payload, entityId) {
    const configKey = pickString(payload, 'config_key') ?? pickString(payload, 'configKey');
    if (!configKey) {
        throw new Error('Missing config key');
    }
    const id = pickString(payload, 'id') ?? entityId;
    const updatedAt = pickNumber(payload, 'updated_at') ?? Date.now();
    const payloadValue = payload['payload'] && typeof payload['payload'] === 'object'
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
async function insertUsageEvent(merchantId, payload, entityId) {
    const metricKey = pickString(payload, 'metric_key') ?? pickString(payload, 'metricKey');
    if (!metricKey) {
        throw new Error('Missing metric key');
    }
    const quantity = pickNumber(payload, 'quantity') ?? 1;
    const occurredAt = pickNumber(payload, 'occurred_at') ?? pickNumber(payload, 'occurredAt') ??
        Date.now();
    const source = pickString(payload, 'source');
    const metadata = payload['metadata'] && typeof payload['metadata'] === 'object'
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
    }
    catch (error) {
        await client.query('ROLLBACK');
        throw error;
    }
    finally {
        client.release();
    }
}
async function deleteById(table, entityId, merchantId) {
    const sql = `DELETE FROM ${table} WHERE id = $1 AND merchant_id = $2`;
    await pool.query(sql, [entityId, merchantId]);
}
function monthlyWindow(occurredAtMs) {
    const date = new Date(occurredAtMs);
    const start = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1, 0, 0, 0);
    const next = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1, 0, 0, 0);
    const end = next - 1;
    return { start, end };
}
function isNonEmptyString(value) {
    return typeof value === 'string' && value.trim().length > 0;
}
exports.retentionInactivityScanDaily = (0, scheduler_1.onSchedule)({
    schedule: 'every day 01:45',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '512MiB',
}, async () => {
    const configuredLimit = parseInt(process.env.RETENTION_SCAN_LIMIT ?? `${DEFAULT_RETENTION_SCAN_LIMIT}`, 10);
    const limit = Number.isFinite(configuredLimit)
        ? Math.min(500, Math.max(1, configuredLimit))
        : DEFAULT_RETENTION_SCAN_LIMIT;
    const configuredMaxPages = parseInt(process.env.RETENTION_SCAN_MAX_PAGES ?? '20', 10);
    const maxPages = Number.isFinite(configuredMaxPages)
        ? Math.min(50, Math.max(1, configuredMaxPages))
        : 20;
    const configuredTimeBudgetMs = parseInt(process.env.RETENTION_SCAN_TIME_BUDGET_MS ?? '480000', 10);
    const timeBudgetMs = Number.isFinite(configuredTimeBudgetMs)
        ? Math.min(500000, Math.max(30000, configuredTimeBudgetMs))
        : 480000;
    const startedAt = Date.now();
    const checkpointRef = admin.firestore()
        .collection('system_jobs')
        .doc('retention_inactivity_scan');
    const checkpointSnapshot = await checkpointRef.get();
    let cursorPath = checkpointSnapshot.exists
        ? maybePayloadString(snapshotDataRecord(checkpointSnapshot), 'cursor_path')
        : null;
    const scanId = `scheduled:${new Date(startedAt).toISOString().substring(0, 10)}`;
    let processed = 0;
    let pagesProcessed = 0;
    let completedCycle = false;
    while (pagesProcessed < maxPages &&
        Date.now() - startedAt < timeBudgetMs) {
        let query = admin.firestore()
            .collectionGroup('customers')
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(limit);
        if (cursorPath)
            query = query.startAfter(cursorPath);
        const snapshot = await query.get();
        if (snapshot.empty) {
            cursorPath = null;
            completedCycle = true;
            await checkpointRef.set({
                job: 'retention_inactivity_scan',
                cursor_path: null,
                processed_in_invocation: processed,
                pages_in_invocation: pagesProcessed,
                page_size: 0,
                completed_cycle: true,
                stopped_for_time_budget: false,
                updated_at: Date.now(),
            }, { merge: true });
            break;
        }
        const occurredAt = Date.now();
        for (const doc of snapshot.docs) {
            const pathParts = doc.ref.path.split('/');
            if (pathParts.length === 4 &&
                pathParts[0] === 'businesses' &&
                pathParts[2] === 'customers') {
                await updateCustomerClassification({
                    merchantId: pathParts[1],
                    customerId: pathParts[3],
                    sourceType: 'inactivity_scan',
                    sourceId: scanId,
                    occurredAt,
                    dryRun: false,
                });
                processed += 1;
            }
        }
        pagesProcessed += 1;
        completedCycle = snapshot.size < limit;
        cursorPath = completedCycle
            ? null
            : snapshot.docs[snapshot.docs.length - 1].ref.path;
        await checkpointRef.set({
            job: 'retention_inactivity_scan',
            cursor_path: cursorPath,
            processed_in_invocation: processed,
            pages_in_invocation: pagesProcessed,
            page_size: snapshot.size,
            completed_cycle: completedCycle,
            stopped_for_time_budget: false,
            time_budget_ms: timeBudgetMs,
            max_pages: maxPages,
            updated_at: Date.now(),
        }, { merge: true });
        if (completedCycle)
            break;
    }
    if (!completedCycle) {
        await checkpointRef.set({
            job: 'retention_inactivity_scan',
            cursor_path: cursorPath,
            processed_in_invocation: processed,
            pages_in_invocation: pagesProcessed,
            completed_cycle: false,
            stopped_for_time_budget: Date.now() - startedAt >= timeBudgetMs,
            stopped_for_page_limit: pagesProcessed >= maxPages,
            time_budget_ms: timeBudgetMs,
            max_pages: maxPages,
            updated_at: Date.now(),
        }, { merge: true });
    }
});
exports.usageBackfillDaily = (0, scheduler_1.onSchedule)({ schedule: 'every day 02:30', timeZone: 'UTC' }, async () => {
    const lookbackDays = parseInt(process.env.AGGREGATION_LOOKBACK_DAYS ?? '7', 10);
    const metrics = parseMetrics(process.env.AGGREGATION_METRICS);
    await aggregateUsageEvents(Date.now(), lookbackDays, metrics);
});
exports.usageReconcileWeekly = (0, scheduler_1.onSchedule)({ schedule: 'every monday 03:15', timeZone: 'UTC' }, async () => {
    const monthsBack = parseInt(process.env.RECONCILE_MONTHS_BACK ?? '2', 10);
    const metrics = parseMetrics(process.env.AGGREGATION_METRICS);
    await reconcileUsageBalances(Date.now(), monthsBack, metrics);
});
function parseMetrics(raw) {
    if (!raw || !raw.trim())
        return ['whatsapp_messages'];
    return raw
        .split(',')
        .map((metric) => metric.trim())
        .filter((metric) => metric.length > 0);
}
async function aggregateUsageEvents(nowMs, lookbackDays, metrics) {
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
async function reconcileUsageBalances(nowMs, monthsBack, metrics) {
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
