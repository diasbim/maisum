"use strict";
/**
 * Response contracts for the `/admin/*` API.
 *
 * These endpoints previously returned `data: result.rows` — raw PostgreSQL
 * rows. Nothing described or checked their shape, so every client mirrored a
 * SQL SELECT list by hand and a renamed column broke them silently at runtime.
 *
 * Two things this normalizes at the boundary, which callers previously had to
 * guess at:
 *
 *  - `node-pg` returns `BIGINT` columns as **strings** (it will not risk
 *    precision loss on int8). Every timestamp column in this schema is
 *    `BIGINT` epoch-millis, so `created_at` arrived as `"1730000000000"`.
 *    Here it is always a `number | null`.
 *  - Absent columns and SQL `NULL` both become `null`, never `undefined`, so
 *    JSON serialization keeps the key.
 *
 * Widening a field is safe for the existing Flutter client: its readers already
 * accept both strings and numbers. Renaming or removing one is not.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.readNullableString = readNullableString;
exports.readString = readString;
exports.readNullableNumber = readNullableNumber;
exports.readCount = readCount;
exports.readBoolean = readBoolean;
exports.readJsonObject = readJsonObject;
exports.toAdminMerchantSummary = toAdminMerchantSummary;
exports.toAdminMerchantDetail = toAdminMerchantDetail;
exports.toAdminAuditEvent = toAdminAuditEvent;
exports.toAdminPlanPrice = toAdminPlanPrice;
exports.toAdminPlanFeature = toAdminPlanFeature;
exports.toAdminPlan = toAdminPlan;
exports.toAdminOperationsSummary = toAdminOperationsSummary;
exports.toAdminPaging = toAdminPaging;
exports.toAdminEntitlement = toAdminEntitlement;
exports.toAdminStaffUser = toAdminStaffUser;
exports.toAdminNfcCard = toAdminNfcCard;
// --- Readers -----------------------------------------------------------------
function asRecord(value) {
    return value != null && typeof value === 'object' && !Array.isArray(value)
        ? value
        : {};
}
/** Trimmed string, or `null` when absent, blank, or not a string. */
function readNullableString(row, key) {
    const value = row[key];
    if (typeof value !== 'string')
        return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
}
/** Trimmed string, falling back to `fallback` when absent or blank. */
function readString(row, key, fallback = '') {
    return readNullableString(row, key) ?? fallback;
}
/**
 * Numeric column as a `number`, tolerating the string form that `node-pg`
 * returns for `BIGINT`. Non-finite and unparseable values become `null`.
 */
function readNullableNumber(row, key) {
    const value = row[key];
    if (typeof value === 'number')
        return Number.isFinite(value) ? value : null;
    if (typeof value === 'bigint')
        return Number(value);
    if (typeof value === 'string') {
        const trimmed = value.trim();
        if (trimmed.length === 0)
            return null;
        const parsed = Number(trimmed);
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}
/** Counter column, defaulting to `0` rather than `null`. */
function readCount(row, key) {
    return readNullableNumber(row, key) ?? 0;
}
/** Boolean column, tolerating the `'t'`/`'f'` and `0`/`1` spellings. */
function readBoolean(row, key, fallback = false) {
    const value = row[key];
    if (typeof value === 'boolean')
        return value;
    if (typeof value === 'number')
        return value !== 0;
    if (typeof value === 'string') {
        const normalized = value.trim().toLowerCase();
        if (['true', 't', 'yes', 'y', '1'].includes(normalized))
            return true;
        if (['false', 'f', 'no', 'n', '0'].includes(normalized))
            return false;
    }
    return fallback;
}
/** `jsonb` column as an object, tolerating a JSON string. */
function readJsonObject(row, key) {
    const value = row[key];
    if (typeof value === 'string') {
        try {
            return asRecord(JSON.parse(value));
        }
        catch {
            return {};
        }
    }
    return asRecord(value);
}
function readArray(row, key) {
    const value = row[key];
    if (Array.isArray(value))
        return value;
    if (typeof value === 'string') {
        try {
            const parsed = JSON.parse(value);
            return Array.isArray(parsed) ? parsed : [];
        }
        catch {
            return [];
        }
    }
    return [];
}
// --- Mappers -----------------------------------------------------------------
function toAdminMerchantSummary(raw) {
    const row = asRecord(raw);
    return {
        id: readString(row, 'id'),
        name: readString(row, 'name'),
        phone: readNullableString(row, 'phone'),
        created_at: readNullableNumber(row, 'created_at'),
        updated_at: readNullableNumber(row, 'updated_at'),
        plan_code: readNullableString(row, 'plan_code'),
        plan_name: readNullableString(row, 'plan_name'),
        subscription_status: readNullableString(row, 'subscription_status'),
        staff_count: readCount(row, 'staff_count'),
        active_staff_count: readCount(row, 'active_staff_count'),
        usage_balance_count: readCount(row, 'usage_balance_count'),
        last_operational_update_at: readNullableNumber(row, 'last_operational_update_at'),
    };
}
function toAdminMerchantDetail(raw) {
    const row = asRecord(raw);
    return {
        ...toAdminMerchantSummary(row),
        plan_version: readNullableNumber(row, 'plan_version'),
        pricing_version: readNullableNumber(row, 'pricing_version'),
        trial_ends_at: readNullableNumber(row, 'trial_ends_at'),
        grace_ends_at: readNullableNumber(row, 'grace_ends_at'),
        period_start: readNullableNumber(row, 'period_start'),
        period_end: readNullableNumber(row, 'period_end'),
        subscription_updated_at: readNullableNumber(row, 'subscription_updated_at'),
        last_staff_login_at: readNullableNumber(row, 'last_staff_login_at'),
        usage_used_total: readCount(row, 'usage_used_total'),
        usage_updated_at: readNullableNumber(row, 'usage_updated_at'),
        usage_event_count: readCount(row, 'usage_event_count'),
        last_usage_event_at: readNullableNumber(row, 'last_usage_event_at'),
        entitlement_count: readCount(row, 'entitlement_count'),
        feature_flag_count: readCount(row, 'feature_flag_count'),
        remote_config_count: readCount(row, 'remote_config_count'),
    };
}
function toAdminAuditEvent(raw) {
    const row = asRecord(raw);
    return {
        id: readString(row, 'id'),
        action: readString(row, 'action', 'admin.event'),
        target_type: readString(row, 'target_type', 'unknown'),
        target_id: readNullableString(row, 'target_id'),
        merchant_id: readNullableString(row, 'merchant_id'),
        actor_app_user_id: readNullableString(row, 'actor_app_user_id'),
        actor_firebase_uid: readNullableString(row, 'actor_firebase_uid'),
        actor_role: readNullableString(row, 'actor_role'),
        details: readJsonObject(row, 'details'),
        created_at: readNullableNumber(row, 'created_at'),
    };
}
function toAdminPlanPrice(raw) {
    const row = asRecord(raw);
    return {
        pricing_version: readNullableNumber(row, 'pricing_version'),
        currency: readNullableString(row, 'currency'),
        amount: readNullableNumber(row, 'amount'),
        billing_period: readNullableString(row, 'billing_period'),
        is_active: readBoolean(row, 'is_active'),
        created_at: readNullableNumber(row, 'created_at'),
        updated_at: readNullableNumber(row, 'updated_at'),
    };
}
function toAdminPlanFeature(raw) {
    const row = asRecord(raw);
    return {
        feature_key: readString(row, 'feature_key'),
        is_enabled: readBoolean(row, 'is_enabled'),
        limit_value: readNullableNumber(row, 'limit_value'),
        unit: readNullableString(row, 'unit'),
        updated_at: readNullableNumber(row, 'updated_at'),
    };
}
function toAdminPlan(raw) {
    const row = asRecord(raw);
    return {
        plan_code: readString(row, 'plan_code'),
        version: readNullableNumber(row, 'version'),
        name: readNullableString(row, 'name'),
        is_active: readBoolean(row, 'is_active'),
        created_at: readNullableNumber(row, 'created_at'),
        updated_at: readNullableNumber(row, 'updated_at'),
        prices: readArray(row, 'prices').map(toAdminPlanPrice),
        features: readArray(row, 'features')
            .map(toAdminPlanFeature)
            // `jsonb_agg(... ) FILTER` can still emit a null-keyed object for plans
            // with no features; drop entries that carry no key.
            .filter((feature) => feature.feature_key.length > 0),
    };
}
function toAdminOperationsSummary(raw) {
    const row = asRecord(raw);
    return {
        merchant_count: readCount(row, 'merchant_count'),
        active_subscription_count: readCount(row, 'active_subscription_count'),
        trial_subscription_count: readCount(row, 'trial_subscription_count'),
        attention_subscription_count: readCount(row, 'attention_subscription_count'),
        active_staff_count: readCount(row, 'active_staff_count'),
        usage_events_24h: readCount(row, 'usage_events_24h'),
        open_recovery_task_count: readCount(row, 'open_recovery_task_count'),
        visit_reports_24h: readCount(row, 'visit_reports_24h'),
        survey_responses_24h: readCount(row, 'survey_responses_24h'),
        admin_audit_events_24h: readCount(row, 'admin_audit_events_24h'),
        last_admin_audit_at: readNullableNumber(row, 'last_admin_audit_at'),
        last_usage_event_at: readNullableNumber(row, 'last_usage_event_at'),
    };
}
/** Builds the paging envelope shared by the admin list endpoints. */
function toAdminPaging(limit, offset, returnedRows) {
    return {
        limit,
        offset,
        has_more: returnedRows === limit,
    };
}
function toAdminEntitlement(raw) {
    const row = asRecord(raw);
    return {
        id: readString(row, 'id'),
        merchant_id: readString(row, 'merchant_id'),
        feature_key: readString(row, 'feature_key'),
        is_enabled: readBoolean(row, 'is_enabled'),
        limit_value: readNullableNumber(row, 'limit_value'),
        unit: readNullableString(row, 'unit'),
        updated_at: readNullableNumber(row, 'updated_at'),
    };
}
function toAdminStaffUser(raw) {
    const row = asRecord(raw);
    return {
        id: readString(row, 'id'),
        merchant_id: readString(row, 'merchant_id'),
        merchant_name: readNullableString(row, 'merchant_name'),
        phone: readString(row, 'phone'),
        role: readString(row, 'role', 'UNKNOWN'),
        status: readString(row, 'status', 'UNKNOWN'),
        invited_at: readNullableNumber(row, 'invited_at'),
        accepted_at: readNullableNumber(row, 'accepted_at'),
        deactivated_at: readNullableNumber(row, 'deactivated_at'),
        last_login_at: readNullableNumber(row, 'last_login_at'),
        created_at: readNullableNumber(row, 'created_at'),
        updated_at: readNullableNumber(row, 'updated_at'),
    };
}
function toAdminNfcCard(cardUid, raw) {
    const row = asRecord(raw);
    const uid = readString(row, 'card_uid', cardUid);
    return {
        card_uid_last4: uid.length <= 4 ? uid : uid.slice(-4),
        canonical_customer_id: readNullableString(row, 'canonical_customer_id'),
        status: readString(row, 'status', 'UNKNOWN'),
        source: readNullableString(row, 'source'),
        linked_by: readNullableString(row, 'linked_by'),
        linked_by_merchant_id: readNullableString(row, 'linked_by_merchant_id'),
        created_at: readNullableNumber(row, 'created_at'),
        updated_at: readNullableNumber(row, 'updated_at'),
    };
}
