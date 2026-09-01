import assert from 'node:assert/strict';
import test from 'node:test';
import {
  readBoolean,
  readCount,
  readJsonObject,
  readNullableNumber,
  readNullableString,
  toAdminAuditEvent,
  toAdminEntitlement,
  toAdminMerchantDetail,
  toAdminMerchantSummary,
  toAdminNfcCard,
  toAdminOperationsSummary,
  toAdminPaging,
  toAdminPlan,
  toAdminStaffUser,
} from './admin_api_contracts.js';

// node-pg returns BIGINT as a string to avoid precision loss. Every timestamp
// column in this schema is BIGINT epoch-millis, so this is the normal case for
// these endpoints, not an edge case.
const PG_BIGINT = '1730000000000';
const PG_BIGINT_NUMBER = 1730000000000;

test('BIGINT columns arriving as strings become numbers', () => {
  const summary = toAdminMerchantSummary({
    id: 'm1',
    name: 'Loja',
    created_at: PG_BIGINT,
    updated_at: PG_BIGINT,
    last_operational_update_at: PG_BIGINT,
  });
  assert.equal(summary.created_at, PG_BIGINT_NUMBER);
  assert.equal(summary.updated_at, PG_BIGINT_NUMBER);
  assert.equal(summary.last_operational_update_at, PG_BIGINT_NUMBER);
});

test('numeric readers accept number, string and bigint forms', () => {
  assert.equal(readNullableNumber({ v: 42 }, 'v'), 42);
  assert.equal(readNullableNumber({ v: '42' }, 'v'), 42);
  assert.equal(readNullableNumber({ v: ' 42 ' }, 'v'), 42);
  assert.equal(readNullableNumber({ v: BigInt(42) }, 'v'), 42);
});

test('numeric readers reject values that are not numbers', () => {
  assert.equal(readNullableNumber({ v: null }, 'v'), null);
  assert.equal(readNullableNumber({}, 'v'), null);
  assert.equal(readNullableNumber({ v: '' }, 'v'), null);
  assert.equal(readNullableNumber({ v: 'abc' }, 'v'), null);
  assert.equal(readNullableNumber({ v: Number.NaN }, 'v'), null);
  assert.equal(readNullableNumber({ v: Infinity }, 'v'), null);
  assert.equal(readNullableNumber({ v: {} }, 'v'), null);
});

test('counters default to zero rather than null', () => {
  assert.equal(readCount({}, 'v'), 0);
  assert.equal(readCount({ v: null }, 'v'), 0);
  assert.equal(readCount({ v: '7' }, 'v'), 7);
});

test('blank strings are normalized to null, not empty strings', () => {
  assert.equal(readNullableString({ v: '  ' }, 'v'), null);
  assert.equal(readNullableString({ v: ' Loja ' }, 'v'), 'Loja');
  assert.equal(readNullableString({ v: 7 }, 'v'), null);
});

test('booleans tolerate the postgres t/f spellings', () => {
  assert.equal(readBoolean({ v: true }, 'v'), true);
  assert.equal(readBoolean({ v: 't' }, 'v'), true);
  assert.equal(readBoolean({ v: 'TRUE' }, 'v'), true);
  assert.equal(readBoolean({ v: 1 }, 'v'), true);
  assert.equal(readBoolean({ v: 'f' }, 'v'), false);
  assert.equal(readBoolean({ v: 0 }, 'v'), false);
  assert.equal(readBoolean({}, 'v'), false);
});

test('jsonb columns are objects whether parsed or still a string', () => {
  assert.deepEqual(readJsonObject({ d: { a: 1 } }, 'd'), { a: 1 });
  assert.deepEqual(readJsonObject({ d: '{"a":1}' }, 'd'), { a: 1 });
  assert.deepEqual(readJsonObject({ d: 'not json' }, 'd'), {});
  assert.deepEqual(readJsonObject({ d: null }, 'd'), {});
  assert.deepEqual(readJsonObject({ d: [1, 2] }, 'd'), {});
});

// --- Merchants ---------------------------------------------------------------

test('merchant summary keeps every key even when the row is empty', () => {
  const summary = toAdminMerchantSummary({});
  assert.deepEqual(summary, {
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

test('merchant summary tolerates a malformed row instead of throwing', () => {
  assert.equal(toAdminMerchantSummary(null).id, '');
  assert.equal(toAdminMerchantSummary(undefined).id, '');
  assert.equal(toAdminMerchantSummary('nope').id, '');
  assert.equal(toAdminMerchantSummary([]).id, '');
});

test('merchant detail carries the subscription and usage fields', () => {
  const detail = toAdminMerchantDetail({
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
  assert.equal(detail.id, 'm1');
  assert.equal(detail.plan_version, 1);
  assert.equal(detail.trial_ends_at, PG_BIGINT_NUMBER);
  assert.equal(detail.usage_used_total, 12);
  assert.equal(detail.entitlement_count, 3);
  // Inherited from the summary shape.
  assert.equal(detail.phone, '+258840000000');
  assert.equal(detail.staff_count, 0);
});

// --- Audit events ------------------------------------------------------------

test('audit events fall back to safe labels, matching the Flutter client', () => {
  const event = toAdminAuditEvent({ id: 'e1' });
  assert.equal(event.action, 'admin.event');
  assert.equal(event.target_type, 'unknown');
  assert.deepEqual(event.details, {});
  assert.equal(event.created_at, null);
});

test('audit event details survive as an object', () => {
  const event = toAdminAuditEvent({
    id: 'e1',
    action: 'entitlement.override',
    target_type: 'merchant',
    target_id: 'm1',
    details: '{"feature_key":"analytics","is_enabled":true}',
    created_at: PG_BIGINT,
  });
  assert.deepEqual(event.details, {
    feature_key: 'analytics',
    is_enabled: true,
  });
  assert.equal(event.created_at, PG_BIGINT_NUMBER);
});

// --- Plans -------------------------------------------------------------------

test('plan aggregates parse nested prices and features', () => {
  const plan = toAdminPlan({
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
  assert.equal(plan.prices.length, 1);
  assert.equal(plan.prices[0].amount, 3500);
  assert.equal(plan.prices[0].currency, 'MZN');
  assert.equal(plan.features.length, 2);
  assert.equal(plan.features[0].feature_key, 'analytics');
  assert.equal(plan.features[0].is_enabled, true);
  assert.equal(plan.features[1].is_enabled, false);
});

test('plan aggregates arriving as JSON strings are parsed', () => {
  const plan = toAdminPlan({
    plan_code: 'free',
    prices: '[{"currency":"MZN","amount":0,"is_active":true}]',
    features: '[{"feature_key":"analytics","is_enabled":false}]',
  });
  assert.equal(plan.prices.length, 1);
  assert.equal(plan.prices[0].amount, 0);
  assert.equal(plan.features.length, 1);
});

test('plans with no features yield empty arrays, never null', () => {
  const plan = toAdminPlan({ plan_code: 'free' });
  assert.deepEqual(plan.prices, []);
  assert.deepEqual(plan.features, []);
});

test('feature entries without a key are dropped', () => {
  // jsonb_agg(...) FILTER can emit a null-keyed object for a plan with no rows.
  const plan = toAdminPlan({
    plan_code: 'free',
    features: [{ feature_key: null, is_enabled: null }, { feature_key: 'analytics', is_enabled: true }],
  });
  assert.equal(plan.features.length, 1);
  assert.equal(plan.features[0].feature_key, 'analytics');
});

// --- Operations summary ------------------------------------------------------

test('operations summary defaults every counter to zero', () => {
  const summary = toAdminOperationsSummary(undefined);
  assert.equal(summary.merchant_count, 0);
  assert.equal(summary.active_subscription_count, 0);
  assert.equal(summary.admin_audit_events_24h, 0);
  assert.equal(summary.last_admin_audit_at, null);
  assert.equal(summary.last_usage_event_at, null);
});

test('operations summary normalizes counts and timestamps', () => {
  const summary = toAdminOperationsSummary({
    merchant_count: 12,
    active_subscription_count: '8',
    last_admin_audit_at: PG_BIGINT,
  });
  assert.equal(summary.merchant_count, 12);
  assert.equal(summary.active_subscription_count, 8);
  assert.equal(summary.last_admin_audit_at, PG_BIGINT_NUMBER);
});

// --- Paging ------------------------------------------------------------------

test('has_more is true only when the page came back full', () => {
  assert.deepEqual(toAdminPaging(50, 0, 50), {
    limit: 50,
    offset: 0,
    has_more: true,
  });
  assert.deepEqual(toAdminPaging(50, 50, 12), {
    limit: 50,
    offset: 50,
    has_more: false,
  });
  assert.deepEqual(toAdminPaging(50, 0, 0), {
    limit: 50,
    offset: 0,
    has_more: false,
  });
});

// --- Entitlements, staff and cards -------------------------------------------

test('entitlement keeps a null limit distinct from a zero limit', () => {
  const unmetered = toAdminEntitlement({
    id: 'm1_analytics',
    merchant_id: 'm1',
    feature_key: 'analytics',
    is_enabled: 't',
    limit_value: null,
    unit: null,
    updated_at: PG_BIGINT,
  });

  const denied = toAdminEntitlement({
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
  assert.equal(unmetered.limit_value, null);
  assert.equal(denied.limit_value, 0);
  assert.equal(unmetered.is_enabled, true);
  assert.equal(denied.is_enabled, false);
  assert.equal(unmetered.updated_at, Number(PG_BIGINT));
});

test('entitlement tolerates a missing row shape', () => {
  const entitlement = toAdminEntitlement(null);
  assert.equal(entitlement.feature_key, '');
  assert.equal(entitlement.is_enabled, false);
  assert.equal(entitlement.limit_value, null);
  assert.equal(entitlement.updated_at, null);
});

test('staff user normalizes bigint timestamps and defaults unknown state', () => {
  const staff = toAdminStaffUser({
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

  assert.equal(staff.merchant_name, 'Cafe Central');
  assert.equal(staff.invited_at, Number(PG_BIGINT));
  assert.equal(staff.accepted_at, null);

  const unknown = toAdminStaffUser({ id: 'u2', merchant_id: 'm1' });
  assert.equal(unknown.role, 'UNKNOWN');
  assert.equal(unknown.status, 'UNKNOWN');
  assert.equal(unknown.merchant_name, null);
});

test('nfc card never carries the full uid off the server', () => {
  const uid = '04A224B2C15E80';
  const card = toAdminNfcCard(uid, {
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
  assert.equal(card.card_uid_last4, '5E80');
  assert.equal(JSON.stringify(card).includes(uid), false);
  assert.equal(card.status, 'ACTIVE');
});

test('nfc card falls back to the document id when the row has no uid', () => {
  const card = toAdminNfcCard('04A224B2C15E80', {});
  assert.equal(card.card_uid_last4, '5E80');
  assert.equal(card.canonical_customer_id, null);
  assert.equal(card.status, 'UNKNOWN');
});

test('nfc card handles a uid shorter than four characters', () => {
  const card = toAdminNfcCard('AB', { card_uid: 'AB' });
  assert.equal(card.card_uid_last4, 'AB');
});
