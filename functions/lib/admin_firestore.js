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
Object.defineProperty(exports, "__esModule", { value: true });
exports.SCAN_CAP = void 0;
exports.listMerchants = listMerchants;
exports.getMerchantDetail = getMerchantDetail;
exports.listEntitlements = listEntitlements;
exports.merchantExists = merchantExists;
exports.upsertEntitlement = upsertEntitlement;
exports.listStaff = listStaff;
exports.listPlans = listPlans;
exports.upsertPlan = upsertPlan;
exports.upsertPlanPrice = upsertPlanPrice;
exports.setPlanFeature = setPlanFeature;
exports.getOperationsSummary = getOperationsSummary;
const admin = __importStar(require("firebase-admin"));
const admin_firestore_join_js_1 = require("./admin_firestore_join.js");
const admin_audit_js_1 = require("./admin_audit.js");
/**
 * The admin console's data layer, over Firestore.
 *
 * Everything the console reads lives in Firestore already — the same paths the
 * mobile app syncs to, listed in FirestoreSyncService._collectionMap. The
 * PostgreSQL schema mirrored these tables but was never connected in
 * production, so reading Firestore is not a workaround; it is reading the
 * source.
 *
 * Two constraints shape this file:
 *
 *  - **There are no joins.** Listing businesses with their subscription and
 *    staff means one collection group query per subcollection, joined in
 *    memory. Three reads for a page instead of three per business.
 *  - **Filtered collection group queries need declared indexes.** Unfiltered
 *    ones do not. So the paths that must always work avoid filters, and the
 *    ones that cannot degrade to an explicit "unavailable" rather than failing
 *    the whole screen.
 */
const db = () => admin.firestore();
/**
 * How many documents a collection group scan will pull before giving up.
 *
 * A console over a pilot's worth of businesses is far inside this. Past it the
 * answer would be wrong, so callers are told rather than served a partial join
 * presented as complete.
 */
exports.SCAN_CAP = 5000;
/** Reads a whole collection group, tagged with the owning business. */
async function scanOwned(collectionId) {
    const snapshot = await db()
        .collectionGroup(collectionId)
        .limit(exports.SCAN_CAP + 1)
        .get();
    const truncated = snapshot.size > exports.SCAN_CAP;
    const docs = truncated ? snapshot.docs.slice(0, exports.SCAN_CAP) : snapshot.docs;
    return {
        items: docs.map((doc) => ({
            // businesses/{merchantId}/{collectionId}/{docId} — the grandparent is
            // the business document.
            merchantId: doc.ref.parent.parent?.id ?? '',
            data: doc.data(),
        })),
        truncated,
    };
}
async function listMerchants(query) {
    const [businesses, subscriptions, staff, usage] = await Promise.all([
        db().collection('businesses').limit(exports.SCAN_CAP + 1).get(),
        scanOwned('subscription_state'),
        scanOwned('app_users'),
        scanOwned('usage_balances'),
    ]);
    const businessTruncated = businesses.size > exports.SCAN_CAP;
    const businessDocs = businessTruncated
        ? businesses.docs.slice(0, exports.SCAN_CAP)
        : businesses.docs;
    const subscriptionsBy = (0, admin_firestore_join_js_1.groupByMerchant)(subscriptions.items);
    const staffBy = (0, admin_firestore_join_js_1.groupByMerchant)(staff.items);
    const usageBy = (0, admin_firestore_join_js_1.groupByMerchant)(usage.items);
    const summaries = businessDocs.map((doc) => (0, admin_firestore_join_js_1.buildMerchantSummary)({ id: doc.id, data: doc.data() }, subscriptionsBy.get(doc.id) ?? [], staffBy.get(doc.id) ?? [], usageBy.get(doc.id) ?? []));
    return {
        ...(0, admin_firestore_join_js_1.selectMerchants)(summaries, query),
        truncated: businessTruncated ||
            subscriptions.truncated ||
            staff.truncated ||
            usage.truncated,
    };
}
/** Every document in one business subcollection. */
async function subcollection(merchantId, collectionId, limit = 500) {
    const snapshot = await db()
        .collection('businesses')
        .doc(merchantId)
        .collection(collectionId)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => doc.data());
}
function pickString(data, ...keys) {
    if (!data)
        return null;
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'string' && value.trim().length > 0) {
            return value.trim();
        }
    }
    return null;
}
function pickNumber(data, ...keys) {
    if (!data)
        return null;
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'number' && Number.isFinite(value))
            return value;
    }
    return null;
}
function latest(records) {
    return [...records].sort((a, b) => (pickNumber(b, 'updated_at') ?? 0) - (pickNumber(a, 'updated_at') ?? 0))[0];
}
async function getMerchantDetail(merchantId) {
    const businessDoc = await db().collection('businesses').doc(merchantId).get();
    if (!businessDoc.exists)
        return null;
    const [subscriptions, staff, usageBalances, usageEvents, entitlements, featureFlags, remoteConfig,] = await Promise.all([
        subcollection(merchantId, 'subscription_state', 20),
        subcollection(merchantId, 'app_users', 200),
        subcollection(merchantId, 'usage_balances', 200),
        subcollection(merchantId, 'usage_events', 500),
        subcollection(merchantId, 'entitlements', 200),
        subcollection(merchantId, 'feature_flags', 200),
        subcollection(merchantId, 'remote_config', 200),
    ]);
    const data = businessDoc.data();
    const summary = (0, admin_firestore_join_js_1.buildMerchantSummary)({ id: merchantId, data }, subscriptions, staff, usageBalances);
    const current = latest(subscriptions);
    const lastStaffLogin = staff.reduce((newest, member) => Math.max(newest, pickNumber(member, 'last_login_at') ?? 0), 0);
    const lastUsageEvent = usageEvents.reduce((newest, event) => Math.max(newest, pickNumber(event, 'created_at', 'occurred_at') ?? 0), 0);
    return {
        ...summary,
        plan_version: pickNumber(current, 'plan_version'),
        pricing_version: pickNumber(current, 'pricing_version'),
        trial_ends_at: pickNumber(current, 'trial_ends_at'),
        grace_ends_at: pickNumber(current, 'grace_ends_at'),
        period_start: pickNumber(current, 'period_start'),
        period_end: pickNumber(current, 'period_end'),
        subscription_updated_at: pickNumber(current, 'updated_at'),
        last_staff_login_at: lastStaffLogin > 0 ? lastStaffLogin : null,
        usage_used_total: usageBalances.reduce((total, balance) => total + (pickNumber(balance, 'used') ?? 0), 0),
        usage_updated_at: pickNumber(latest(usageBalances), 'updated_at'),
        // Capped by the subcollection read, so a very busy business reports the
        // cap rather than a wrong total. The detail page is a summary, not a
        // billing record.
        usage_event_count: usageEvents.length,
        last_usage_event_at: lastUsageEvent > 0 ? lastUsageEvent : null,
        entitlement_count: entitlements.length,
        feature_flag_count: featureFlags.length,
        remote_config_count: remoteConfig.length,
    };
}
async function listEntitlements(merchantId) {
    const snapshot = await db()
        .collection('businesses')
        .doc(merchantId)
        .collection('entitlements')
        .get();
    return snapshot.docs
        .map((doc) => ({
        id: doc.id,
        ...doc.data(),
    }))
        .sort((a, b) => String(a.feature_key ?? '').localeCompare(String(b.feature_key ?? '')));
}
async function merchantExists(merchantId) {
    const doc = await db().collection('businesses').doc(merchantId).get();
    return doc.exists;
}
/**
 * Writes an entitlement override.
 *
 * Keyed by feature so a second override of the same feature replaces the
 * first instead of accumulating rows that contradict each other. Returns the
 * previous state so the audit entry can record what changed.
 */
async function upsertEntitlement(input) {
    const ref = db()
        .collection('businesses')
        .doc(input.merchantId)
        .collection('entitlements')
        .doc(input.featureKey);
    const existing = await ref.get();
    const now = Date.now();
    const after = {
        id: `${input.merchantId}_${input.featureKey}`,
        merchant_id: input.merchantId,
        feature_key: input.featureKey,
        is_enabled: input.isEnabled,
        limit_value: input.limitValue,
        unit: input.unit,
        updated_at: now,
    };
    await ref.set(after, { merge: true });
    return {
        before: existing.exists
            ? existing.data()
            : null,
        after,
    };
}
async function listStaff(query) {
    const [staff, businesses] = await Promise.all([
        query.merchantId
            ? subcollection(query.merchantId, 'app_users', exports.SCAN_CAP).then((items) => ({
                items: items.map((data) => ({
                    merchantId: query.merchantId,
                    data,
                })),
                truncated: false,
            }))
            : scanOwned('app_users'),
        db().collection('businesses').limit(exports.SCAN_CAP).get(),
    ]);
    const names = new Map();
    for (const doc of businesses.docs) {
        const data = doc.data();
        const name = pickString(data, 'merchant_name', 'name');
        if (name)
            names.set(doc.id, name);
    }
    const search = (query.search ?? '').trim().toLowerCase();
    const status = (query.status ?? '').trim().toUpperCase();
    const role = (query.role ?? '').trim().toUpperCase();
    const rows = staff.items
        .map((record) => ({
        ...record.data,
        merchant_id: record.merchantId,
        merchant_name: names.get(record.merchantId) ?? null,
    }))
        .filter((row) => {
        if (search.length > 0) {
            const haystack = `${row.phone ?? ''}${row.id ?? ''}`.toLowerCase();
            if (!haystack.includes(search))
                return false;
        }
        if (status.length > 0) {
            if (String(row.status ?? '').toUpperCase() !== status)
                return false;
        }
        if (role.length > 0) {
            if (String(row.role ?? '').toUpperCase() !== role)
                return false;
        }
        return true;
    })
        .sort((a, b) => (b.updated_at ?? 0) - (a.updated_at ?? 0));
    const items = rows.slice(query.offset, query.offset + query.limit);
    return {
        items,
        hasMore: query.offset + items.length < rows.length,
        truncated: staff.truncated,
    };
}
/**
 * The plan catalogue.
 *
 * Firestore stores one flat document per plan — a single price on the document
 * and `features` as an array of keys. The console's contract was shaped by the
 * SQL model, which split those into plans, plan_prices and plan_features. The
 * flat document is mapped up into that shape rather than the other way round,
 * because the reconciliation screen compares feature keys and the mobile app
 * already reads this collection as it stands.
 */
async function listPlans() {
    const snapshot = await db().collection('plans').get();
    return snapshot.docs
        .map((doc) => {
        const data = doc.data();
        const planCode = pickString(data, 'plan_code', 'code', 'planCode') ?? doc.id;
        const amount = pickNumber(data, 'price_cents', 'priceCents', 'amount_cents', 'price');
        const rawFeatures = Array.isArray(data.features) ? data.features : [];
        const isActive = data.is_active !== false && data.active !== false;
        return {
            plan_code: planCode,
            version: pickNumber(data, 'version', 'plan_version') ?? 1,
            name: pickString(data, 'display_name', 'name', 'plan_name', 'displayName') ??
                planCode,
            is_active: isActive,
            created_at: pickNumber(data, 'created_at'),
            updated_at: pickNumber(data, 'updated_at'),
            sort_order: pickNumber(data, 'sort_order', 'order', 'position') ?? 999,
            prices: amount == null
                ? []
                : [
                    {
                        pricing_version: pickNumber(data, 'pricing_version') ?? 1,
                        currency: pickString(data, 'currency') ?? 'MZN',
                        amount,
                        billing_period: pickString(data, 'billing_interval', 'billingInterval') ??
                            'monthly',
                        is_active: isActive,
                        created_at: pickNumber(data, 'created_at'),
                        updated_at: pickNumber(data, 'updated_at'),
                    },
                ],
            features: rawFeatures
                .filter((key) => typeof key === 'string')
                .map((key) => ({
                feature_key: key,
                is_enabled: true,
                limit_value: key === 'whatsapp'
                    ? pickNumber(data, 'whatsapp_monthly_limit', 'whatsappMonthlyLimit')
                    : null,
                unit: key === 'whatsapp' ? 'por mes' : null,
                updated_at: pickNumber(data, 'updated_at'),
            })),
        };
    })
        .sort((a, b) => a.sort_order - b.sort_order ||
        String(a.plan_code).localeCompare(String(b.plan_code)));
}
/**
 * Writes a plan document.
 *
 * Merged, not replaced: the mobile app reads fields from this collection that
 * the console does not show, and overwriting the document would silently drop
 * them.
 */
async function upsertPlan(input) {
    const now = Date.now();
    await db()
        .collection('plans')
        .doc(input.planCode)
        .set({
        plan_code: input.planCode,
        display_name: input.name,
        is_active: input.isActive,
        version: input.version,
        updated_at: now,
        created_at: now,
    }, { merge: true });
}
async function upsertPlanPrice(input) {
    await db()
        .collection('plans')
        .doc(input.planCode)
        .set({
        price_cents: input.amount,
        currency: input.currency,
        billing_interval: input.billingPeriod,
        pricing_version: input.pricingVersion,
        updated_at: Date.now(),
    }, { merge: true });
}
/**
 * Adds or removes a feature key on a plan.
 *
 * The Firestore model has no per-plan feature row to disable, only membership
 * of the `features` array, so disabling means removing the key. Read-modify-
 * write inside a transaction: two operators editing different features of the
 * same plan would otherwise overwrite each other's array.
 */
async function setPlanFeature(input) {
    const ref = db().collection('plans').doc(input.planCode);
    return db().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            return { exists: false, features: [] };
        const data = snapshot.data();
        const current = new Set((Array.isArray(data.features) ? data.features : []).filter((key) => typeof key === 'string'));
        if (input.isEnabled) {
            current.add(input.featureKey);
        }
        else {
            current.delete(input.featureKey);
        }
        const patch = {
            features: [...current].sort(),
            updated_at: Date.now(),
        };
        if (input.featureKey === 'whatsapp' && input.limitValue != null) {
            patch.whatsapp_monthly_limit = input.limitValue;
        }
        transaction.set(ref, patch, { merge: true });
        return { exists: true, features: [...current].sort() };
    });
}
/**
 * A count that is allowed to be unavailable.
 *
 * Filtered collection group queries need a declared composite index. Until one
 * is deployed the query fails, and a whole dashboard failing because one tile
 * needs an index is a worse outcome than the tile saying it cannot be
 * computed. The caller reports which ones are missing.
 */
async function safeCount(label, run) {
    try {
        return { value: await run(), available: true, label };
    }
    catch (error) {
        console.warn('admin_summary_metric_unavailable', {
            metric: label,
            message: error instanceof Error ? error.message : String(error),
        });
        return { value: 0, available: false, label };
    }
}
async function countSince(collectionId, field, since) {
    const snapshot = await db()
        .collectionGroup(collectionId)
        .where(field, '>=', since)
        .count()
        .get();
    return snapshot.data().count;
}
/**
 * The overview figures.
 *
 * Subscription and staff counts come from the same unfiltered collection group
 * scans the merchant list uses, so they need no index and are always
 * available. The time-windowed ones are aggregation queries that do need one,
 * and degrade individually.
 */
async function getOperationsSummary() {
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const [businesses, subscriptions, staff, recovery] = await Promise.all([
        db().collection('businesses').count().get(),
        scanOwned('subscription_state'),
        scanOwned('app_users'),
        scanOwned('recovery_tasks'),
    ]);
    // One business can hold several subscription documents; only the newest
    // describes it today, so the statuses are counted per business, not per row.
    const currentByMerchant = new Map();
    for (const record of subscriptions.items) {
        const existing = currentByMerchant.get(record.merchantId);
        if (!existing ||
            (pickNumber(record.data, 'updated_at') ?? 0) >
                (pickNumber(existing, 'updated_at') ?? 0)) {
            currentByMerchant.set(record.merchantId, record.data);
        }
    }
    let active = 0;
    let trial = 0;
    let attention = 0;
    for (const subscription of currentByMerchant.values()) {
        const status = (pickString(subscription, 'status') ?? '').toUpperCase();
        if (status === 'ACTIVE')
            active += 1;
        else if (status === 'TRIAL')
            trial += 1;
        else if (status.length > 0)
            attention += 1;
    }
    const activeStaff = staff.items.filter((record) => (pickString(record.data, 'status') ?? '').toUpperCase() === 'ACTIVE').length;
    const openRecovery = recovery.items.filter((record) => {
        const status = (pickString(record.data, 'status') ?? '').toUpperCase();
        return status !== 'DONE' && status !== 'CANCELLED' && status !== 'CLOSED';
    }).length;
    const [usage24h, visits24h, surveys24h, audit24h] = await Promise.all([
        safeCount('usage_events_24h', () => countSince('usage_events', 'created_at', dayAgo)),
        safeCount('visit_reports_24h', () => countSince('visit_reports', 'created_at', dayAgo)),
        safeCount('survey_responses_24h', () => countSince('survey_responses', 'created_at', dayAgo)),
        safeCount('admin_audit_events_24h', async () => {
            const snapshot = await db()
                .collection(admin_audit_js_1.ADMIN_AUDIT_COLLECTION)
                .where('created_at', '>=', dayAgo)
                .count()
                .get();
            return snapshot.data().count;
        }),
    ]);
    const lastAudit = await db()
        .collection(admin_audit_js_1.ADMIN_AUDIT_COLLECTION)
        .orderBy('created_at', 'desc')
        .limit(1)
        .get()
        .then((snapshot) => snapshot.empty
        ? null
        : pickNumber(snapshot.docs[0].data(), 'created_at'))
        .catch(() => null);
    const metrics = [usage24h, visits24h, surveys24h, audit24h];
    return {
        merchant_count: businesses.data().count,
        active_subscription_count: active,
        trial_subscription_count: trial,
        attention_subscription_count: attention,
        active_staff_count: activeStaff,
        usage_events_24h: usage24h.value,
        open_recovery_task_count: openRecovery,
        visit_reports_24h: visits24h.value,
        survey_responses_24h: surveys24h.value,
        admin_audit_events_24h: audit24h.value,
        last_admin_audit_at: lastAudit,
        // Reading every usage event to find the newest is not worth one timestamp;
        // the merchant detail page shows it per business, where it is cheap.
        last_usage_event_at: null,
        unavailable_metrics: metrics
            .filter((metric) => !metric.available)
            .map((metric) => metric.label),
    };
}
