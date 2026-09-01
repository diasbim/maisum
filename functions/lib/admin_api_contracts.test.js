"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const admin_api_contracts_js_1 = require("./admin_api_contracts.js");
// node-pg returns BIGINT as a string to avoid precision loss. Every timestamp
// column in this schema is BIGINT epoch-millis, so this is the normal case for
// these endpoints, not an edge case.
const PG_BIGINT = '1730000000000';
const PG_BIGINT_NUMBER = 1730000000000;
(0, node_test_1.default)('BIGINT columns arriving as strings become numbers', () => {
    const summary = (0, admin_api_contracts_js_1.toAdminMerchantSummary)({
        id: 'm1',
        name: 'Loja',
        created_at: PG_BIGINT,
        updated_at: PG_BIGINT,
        last_operational_update_at: PG_BIGINT,
    });
    strict_1.default.equal(summary.created_at, PG_BIGINT_NUMBER);
    strict_1.default.equal(summary.updated_at, PG_BIGINT_NUMBER);
    strict_1.default.equal(summary.last_operational_update_at, PG_BIGINT_NUMBER);
});
(0, node_test_1.default)('numeric readers accept number, string and bigint forms', () => {
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: 42 }, 'v'), 42);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: '42' }, 'v'), 42);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: ' 42 ' }, 'v'), 42);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: BigInt(42) }, 'v'), 42);
});
(0, node_test_1.default)('numeric readers reject values that are not numbers', () => {
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: null }, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({}, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: '' }, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: 'abc' }, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: Number.NaN }, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: Infinity }, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableNumber)({ v: {} }, 'v'), null);
});
(0, node_test_1.default)('counters default to zero rather than null', () => {
    strict_1.default.equal((0, admin_api_contracts_js_1.readCount)({}, 'v'), 0);
    strict_1.default.equal((0, admin_api_contracts_js_1.readCount)({ v: null }, 'v'), 0);
    strict_1.default.equal((0, admin_api_contracts_js_1.readCount)({ v: '7' }, 'v'), 7);
});
(0, node_test_1.default)('blank strings are normalized to null, not empty strings', () => {
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableString)({ v: '  ' }, 'v'), null);
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableString)({ v: ' Loja ' }, 'v'), 'Loja');
    strict_1.default.equal((0, admin_api_contracts_js_1.readNullableString)({ v: 7 }, 'v'), null);
});
(0, node_test_1.default)('booleans tolerate the postgres t/f spellings', () => {
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({ v: true }, 'v'), true);
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({ v: 't' }, 'v'), true);
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({ v: 'TRUE' }, 'v'), true);
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({ v: 1 }, 'v'), true);
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({ v: 'f' }, 'v'), false);
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({ v: 0 }, 'v'), false);
    strict_1.default.equal((0, admin_api_contracts_js_1.readBoolean)({}, 'v'), false);
});
(0, node_test_1.default)('jsonb columns are objects whether parsed or still a string', () => {
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.readJsonObject)({ d: { a: 1 } }, 'd'), { a: 1 });
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.readJsonObject)({ d: '{"a":1}' }, 'd'), { a: 1 });
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.readJsonObject)({ d: 'not json' }, 'd'), {});
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.readJsonObject)({ d: null }, 'd'), {});
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.readJsonObject)({ d: [1, 2] }, 'd'), {});
});
// --- Merchants ---------------------------------------------------------------
(0, node_test_1.default)('merchant summary keeps every key even when the row is empty', () => {
    const summary = (0, admin_api_contracts_js_1.toAdminMerchantSummary)({});
    strict_1.default.deepEqual(summary, {
        id: '',
        name: '',
        phone: null,
        created_at: null,
        updated_at: null,
        plan_code: null,
        plan_name: null,
        subscription_status: null,
        staff_count: 0,
        active_staff_count: 0,
        usage_balance_count: 0,
        last_operational_update_at: null,
    });
});
(0, node_test_1.default)('merchant summary tolerates a malformed row instead of throwing', () => {
    strict_1.default.equal((0, admin_api_contracts_js_1.toAdminMerchantSummary)(null).id, '');
    strict_1.default.equal((0, admin_api_contracts_js_1.toAdminMerchantSummary)(undefined).id, '');
    strict_1.default.equal((0, admin_api_contracts_js_1.toAdminMerchantSummary)('nope').id, '');
    strict_1.default.equal((0, admin_api_contracts_js_1.toAdminMerchantSummary)([]).id, '');
});
(0, node_test_1.default)('merchant detail carries the subscription and usage fields', () => {
    const detail = (0, admin_api_contracts_js_1.toAdminMerchantDetail)({
        id: 'm1',
        name: 'Loja',
        phone: '+258840000000',
        plan_code: 'pro',
        subscription_status: 'ACTIVE',
        plan_version: '1',
        pricing_version: '1',
        trial_ends_at: PG_BIGINT,
        usage_used_total: '12',
        entitlement_count: 3,
    });
    strict_1.default.equal(detail.id, 'm1');
    strict_1.default.equal(detail.plan_version, 1);
    strict_1.default.equal(detail.trial_ends_at, PG_BIGINT_NUMBER);
    strict_1.default.equal(detail.usage_used_total, 12);
    strict_1.default.equal(detail.entitlement_count, 3);
    // Inherited from the summary shape.
    strict_1.default.equal(detail.phone, '+258840000000');
    strict_1.default.equal(detail.staff_count, 0);
});
// --- Audit events ------------------------------------------------------------
(0, node_test_1.default)('audit events fall back to safe labels, matching the Flutter client', () => {
    const event = (0, admin_api_contracts_js_1.toAdminAuditEvent)({ id: 'e1' });
    strict_1.default.equal(event.action, 'admin.event');
    strict_1.default.equal(event.target_type, 'unknown');
    strict_1.default.deepEqual(event.details, {});
    strict_1.default.equal(event.created_at, null);
});
(0, node_test_1.default)('audit event details survive as an object', () => {
    const event = (0, admin_api_contracts_js_1.toAdminAuditEvent)({
        id: 'e1',
        action: 'entitlement.override',
        target_type: 'merchant',
        target_id: 'm1',
        details: '{"feature_key":"analytics","is_enabled":true}',
        created_at: PG_BIGINT,
    });
    strict_1.default.deepEqual(event.details, {
        feature_key: 'analytics',
        is_enabled: true,
    });
    strict_1.default.equal(event.created_at, PG_BIGINT_NUMBER);
});
// --- Plans -------------------------------------------------------------------
(0, node_test_1.default)('plan aggregates parse nested prices and features', () => {
    const plan = (0, admin_api_contracts_js_1.toAdminPlan)({
        plan_code: 'pro',
        version: 1,
        name: 'Pro',
        is_active: true,
        prices: [
            {
                pricing_version: 1,
                currency: 'MZN',
                amount: 3500,
                billing_period: 'monthly',
                is_active: true,
            },
        ],
        features: [
            { feature_key: 'analytics', is_enabled: true, limit_value: null },
            { feature_key: 'multi_device', is_enabled: false, limit_value: null },
        ],
    });
    strict_1.default.equal(plan.prices.length, 1);
    strict_1.default.equal(plan.prices[0].amount, 3500);
    strict_1.default.equal(plan.prices[0].currency, 'MZN');
    strict_1.default.equal(plan.features.length, 2);
    strict_1.default.equal(plan.features[0].feature_key, 'analytics');
    strict_1.default.equal(plan.features[0].is_enabled, true);
    strict_1.default.equal(plan.features[1].is_enabled, false);
});
(0, node_test_1.default)('plan aggregates arriving as JSON strings are parsed', () => {
    const plan = (0, admin_api_contracts_js_1.toAdminPlan)({
        plan_code: 'free',
        prices: '[{"currency":"MZN","amount":0,"is_active":true}]',
        features: '[{"feature_key":"analytics","is_enabled":false}]',
    });
    strict_1.default.equal(plan.prices.length, 1);
    strict_1.default.equal(plan.prices[0].amount, 0);
    strict_1.default.equal(plan.features.length, 1);
});
(0, node_test_1.default)('plans with no features yield empty arrays, never null', () => {
    const plan = (0, admin_api_contracts_js_1.toAdminPlan)({ plan_code: 'free' });
    strict_1.default.deepEqual(plan.prices, []);
    strict_1.default.deepEqual(plan.features, []);
});
(0, node_test_1.default)('feature entries without a key are dropped', () => {
    // jsonb_agg(...) FILTER can emit a null-keyed object for a plan with no rows.
    const plan = (0, admin_api_contracts_js_1.toAdminPlan)({
        plan_code: 'free',
        features: [{ feature_key: null, is_enabled: null }, { feature_key: 'analytics', is_enabled: true }],
    });
    strict_1.default.equal(plan.features.length, 1);
    strict_1.default.equal(plan.features[0].feature_key, 'analytics');
});
// --- Operations summary ------------------------------------------------------
(0, node_test_1.default)('operations summary defaults every counter to zero', () => {
    const summary = (0, admin_api_contracts_js_1.toAdminOperationsSummary)(undefined);
    strict_1.default.equal(summary.merchant_count, 0);
    strict_1.default.equal(summary.active_subscription_count, 0);
    strict_1.default.equal(summary.admin_audit_events_24h, 0);
    strict_1.default.equal(summary.last_admin_audit_at, null);
    strict_1.default.equal(summary.last_usage_event_at, null);
});
(0, node_test_1.default)('operations summary normalizes counts and timestamps', () => {
    const summary = (0, admin_api_contracts_js_1.toAdminOperationsSummary)({
        merchant_count: 12,
        active_subscription_count: '8',
        last_admin_audit_at: PG_BIGINT,
    });
    strict_1.default.equal(summary.merchant_count, 12);
    strict_1.default.equal(summary.active_subscription_count, 8);
    strict_1.default.equal(summary.last_admin_audit_at, PG_BIGINT_NUMBER);
});
// --- Paging ------------------------------------------------------------------
(0, node_test_1.default)('has_more is true only when the page came back full', () => {
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.toAdminPaging)(50, 0, 50), {
        limit: 50,
        offset: 0,
        has_more: true,
    });
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.toAdminPaging)(50, 50, 12), {
        limit: 50,
        offset: 50,
        has_more: false,
    });
    strict_1.default.deepEqual((0, admin_api_contracts_js_1.toAdminPaging)(50, 0, 0), {
        limit: 50,
        offset: 0,
        has_more: false,
    });
});
// --- Entitlements, staff and cards -------------------------------------------
(0, node_test_1.default)('entitlement keeps a null limit distinct from a zero limit', () => {
    const unmetered = (0, admin_api_contracts_js_1.toAdminEntitlement)({
        id: 'm1_analytics',
        merchant_id: 'm1',
        feature_key: 'analytics',
        is_enabled: 't',
        limit_value: null,
        unit: null,
        updated_at: PG_BIGINT,
    });
    const denied = (0, admin_api_contracts_js_1.toAdminEntitlement)({
        id: 'm1_campaigns',
        merchant_id: 'm1',
        feature_key: 'campaigns',
        is_enabled: 'f',
        limit_value: 0,
        unit: 'por mes',
        updated_at: PG_BIGINT,
    });
    // The whole point of the nullable column: null is unmetered, 0 is cut off.
    // Collapsing them would misreport a suspended merchant as unrestricted.
    strict_1.default.equal(unmetered.limit_value, null);
    strict_1.default.equal(denied.limit_value, 0);
    strict_1.default.equal(unmetered.is_enabled, true);
    strict_1.default.equal(denied.is_enabled, false);
    strict_1.default.equal(unmetered.updated_at, Number(PG_BIGINT));
});
(0, node_test_1.default)('entitlement tolerates a missing row shape', () => {
    const entitlement = (0, admin_api_contracts_js_1.toAdminEntitlement)(null);
    strict_1.default.equal(entitlement.feature_key, '');
    strict_1.default.equal(entitlement.is_enabled, false);
    strict_1.default.equal(entitlement.limit_value, null);
    strict_1.default.equal(entitlement.updated_at, null);
});
(0, node_test_1.default)('staff user normalizes bigint timestamps and defaults unknown state', () => {
    const staff = (0, admin_api_contracts_js_1.toAdminStaffUser)({
        id: 'u1',
        merchant_id: 'm1',
        merchant_name: '  Cafe Central  ',
        phone: '+258840000000',
        role: 'STAFF',
        status: 'ACTIVE',
        invited_at: PG_BIGINT,
        accepted_at: null,
        deactivated_at: null,
        last_login_at: PG_BIGINT,
        created_at: PG_BIGINT,
        updated_at: PG_BIGINT,
    });
    strict_1.default.equal(staff.merchant_name, 'Cafe Central');
    strict_1.default.equal(staff.invited_at, Number(PG_BIGINT));
    strict_1.default.equal(staff.accepted_at, null);
    const unknown = (0, admin_api_contracts_js_1.toAdminStaffUser)({ id: 'u2', merchant_id: 'm1' });
    strict_1.default.equal(unknown.role, 'UNKNOWN');
    strict_1.default.equal(unknown.status, 'UNKNOWN');
    strict_1.default.equal(unknown.merchant_name, null);
});
(0, node_test_1.default)('nfc card never carries the full uid off the server', () => {
    const uid = '04A224B2C15E80';
    const card = (0, admin_api_contracts_js_1.toAdminNfcCard)(uid, {
        card_uid: uid,
        canonical_customer_id: 'canon-1',
        status: 'ACTIVE',
        source: 'merchant_pos',
        linked_by: 'staff',
        linked_by_merchant_id: 'm1',
        created_at: PG_BIGINT,
        updated_at: PG_BIGINT,
    });
    // A UID is what a reader presents to identify a customer. Serialising it in
    // full would make the support console a source of working card identifiers.
    strict_1.default.equal(card.card_uid_last4, '5E80');
    strict_1.default.equal(JSON.stringify(card).includes(uid), false);
    strict_1.default.equal(card.status, 'ACTIVE');
});
(0, node_test_1.default)('nfc card falls back to the document id when the row has no uid', () => {
    const card = (0, admin_api_contracts_js_1.toAdminNfcCard)('04A224B2C15E80', {});
    strict_1.default.equal(card.card_uid_last4, '5E80');
    strict_1.default.equal(card.canonical_customer_id, null);
    strict_1.default.equal(card.status, 'UNKNOWN');
});
(0, node_test_1.default)('nfc card handles a uid shorter than four characters', () => {
    const card = (0, admin_api_contracts_js_1.toAdminNfcCard)('AB', { card_uid: 'AB' });
    strict_1.default.equal(card.card_uid_last4, 'AB');
});
