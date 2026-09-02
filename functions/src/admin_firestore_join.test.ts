import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildMerchantSummary,
  groupByMerchant,
  selectMerchants,
  type MerchantSummary,
} from './admin_firestore_join.js';

const business = (id: string, data: Record<string, unknown> = {}) => ({
  id,
  data,
});

test('groups subcollection documents by the business that owns them', () => {
  const grouped = groupByMerchant([
    { merchantId: 'm1', data: { id: 'a' } },
    { merchantId: 'm2', data: { id: 'b' } },
    { merchantId: 'm1', data: { id: 'c' } },
    { merchantId: '', data: { id: 'orphan' } },
  ]);

  assert.equal(grouped.get('m1')?.length, 2);
  assert.equal(grouped.get('m2')?.length, 1);
  // A document with no resolvable parent is dropped rather than bucketed under
  // an empty key, where it would join onto nothing and inflate counts.
  assert.equal(grouped.has(''), false);
});

test('reads the name from either spelling', () => {
  const firestoreEra = buildMerchantSummary(
    business('m1', { merchant_name: 'Cafe Central' }),
    [],
    [],
    [],
  );
  const sqlEra = buildMerchantSummary(business('m2', { name: 'Antigo' }), [], [], []);

  assert.equal(firestoreEra.name, 'Cafe Central');
  assert.equal(sqlEra.name, 'Antigo');
});

test('picks the most recently updated subscription, not an arbitrary one', () => {
  // A business accumulates subscription_state documents over its life. Picking
  // whichever arrived first would make the plan column change between loads.
  const summary = buildMerchantSummary(
    business('m1'),
    [
      { plan_code: 'free', status: 'CANCELLED', updated_at: 100 },
      { plan_code: 'pro', status: 'ACTIVE', updated_at: 300 },
      { plan_code: 'starter', status: 'TRIAL', updated_at: 200 },
    ],
    [],
    [],
  );

  assert.equal(summary.plan_code, 'pro');
  assert.equal(summary.subscription_status, 'ACTIVE');
});

test('counts staff and active staff separately', () => {
  const summary = buildMerchantSummary(
    business('m1'),
    [],
    [
      { status: 'ACTIVE' },
      { status: 'active' },
      { status: 'INACTIVE' },
      {},
    ],
    [],
  );

  assert.equal(summary.staff_count, 4);
  assert.equal(summary.active_staff_count, 2);
});

test('last operational update is the latest activity anywhere on the business', () => {
  const summary = buildMerchantSummary(
    business('m1', { updated_at: 100 }),
    [{ updated_at: 500 }],
    [{ updated_at: 300 }],
    [{ updated_at: 200 }],
  );

  // The profile was edited at 100, but the subscription changed at 500. The
  // list orders by this, so it has to reflect the business being alive.
  assert.equal(summary.last_operational_update_at, 500);
});

test('a business with no activity at all reports null, not zero', () => {
  const summary = buildMerchantSummary(business('m1'), [], [], []);
  assert.equal(summary.last_operational_update_at, null);
  assert.equal(summary.subscription_status, null);
  assert.equal(summary.staff_count, 0);
});

const sample = (): MerchantSummary[] => [
  {
    id: 'm1',
    name: 'Cafe Central',
    phone: '+258840000001',
    created_at: 1,
    updated_at: 1,
    plan_code: 'pro',
    plan_name: 'Pro',
    subscription_status: 'ACTIVE',
    staff_count: 2,
    active_staff_count: 2,
    usage_balance_count: 1,
    last_operational_update_at: 300,
  },
  {
    id: 'm2',
    name: 'Salao Bela',
    phone: '+258840000002',
    created_at: 1,
    updated_at: 1,
    plan_code: 'free',
    plan_name: 'Free',
    subscription_status: 'TRIAL',
    staff_count: 1,
    active_staff_count: 0,
    usage_balance_count: 0,
    last_operational_update_at: 500,
  },
  {
    id: 'm3',
    name: 'Barbearia Sul',
    phone: null,
    created_at: 1,
    updated_at: 1,
    plan_code: 'pro',
    plan_name: 'Pro',
    subscription_status: 'ACTIVE',
    staff_count: 0,
    active_staff_count: 0,
    usage_balance_count: 0,
    last_operational_update_at: 400,
  },
];

test('orders by latest activity, newest first', () => {
  const page = selectMerchants(sample(), { limit: 10, offset: 0 });
  assert.deepEqual(
    page.items.map((m) => m.id),
    ['m2', 'm3', 'm1'],
  );
  assert.equal(page.total, 3);
  assert.equal(page.hasMore, false);
});

test('search matches a substring of id, name or phone, case-insensitively', () => {
  // Firestore cannot express this server-side. Prefix-only matching would mean
  // searching for part of a phone number returns nothing.
  const byName = selectMerchants(sample(), { search: 'bela', limit: 10, offset: 0 });
  assert.deepEqual(byName.items.map((m) => m.id), ['m2']);

  const byPhoneFragment = selectMerchants(sample(), {
    search: '0000001',
    limit: 10,
    offset: 0,
  });
  assert.deepEqual(byPhoneFragment.items.map((m) => m.id), ['m1']);

  const byId = selectMerchants(sample(), { search: 'M3', limit: 10, offset: 0 });
  assert.deepEqual(byId.items.map((m) => m.id), ['m3']);
});

test('a merchant with no phone does not break the search', () => {
  const page = selectMerchants(sample(), { search: 'sul', limit: 10, offset: 0 });
  assert.deepEqual(page.items.map((m) => m.id), ['m3']);
});

test('filters by status and by plan', () => {
  const active = selectMerchants(sample(), { status: 'active', limit: 10, offset: 0 });
  assert.deepEqual(active.items.map((m) => m.id), ['m3', 'm1']);

  const pro = selectMerchants(sample(), { planCode: 'pro', limit: 10, offset: 0 });
  assert.deepEqual(pro.items.map((m) => m.id), ['m3', 'm1']);

  const none = selectMerchants(sample(), { status: 'NAO_EXISTE', limit: 10, offset: 0 });
  assert.equal(none.items.length, 0);
  assert.equal(none.total, 0);
});

test('combines search and status rather than letting one win', () => {
  const page = selectMerchants(sample(), {
    search: 'a',
    status: 'ACTIVE',
    limit: 10,
    offset: 0,
  });
  assert.deepEqual(page.items.map((m) => m.id), ['m3', 'm1']);
});

test('pages without repeating or skipping a row', () => {
  const first = selectMerchants(sample(), { limit: 2, offset: 0 });
  const second = selectMerchants(sample(), { limit: 2, offset: 2 });

  assert.deepEqual(first.items.map((m) => m.id), ['m2', 'm3']);
  assert.equal(first.hasMore, true);
  assert.deepEqual(second.items.map((m) => m.id), ['m1']);
  assert.equal(second.hasMore, false);

  const seen = [...first.items, ...second.items].map((m) => m.id);
  assert.equal(new Set(seen).size, seen.length);
});

test('an offset past the end is empty rather than an error', () => {
  const page = selectMerchants(sample(), { limit: 10, offset: 999 });
  assert.deepEqual(page.items, []);
  assert.equal(page.hasMore, false);
  assert.equal(page.total, 3);
});

test('ties break on id so ordering is stable across requests', () => {
  const tied: MerchantSummary[] = sample().map((m) => ({
    ...m,
    last_operational_update_at: 100,
  }));
  const once = selectMerchants(tied, { limit: 10, offset: 0 });
  const twice = selectMerchants([...tied].reverse(), { limit: 10, offset: 0 });
  assert.deepEqual(
    once.items.map((m) => m.id),
    twice.items.map((m) => m.id),
  );
});
