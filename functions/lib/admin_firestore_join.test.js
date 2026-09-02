"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const admin_firestore_join_js_1 = require("./admin_firestore_join.js");
const business = (id, data = {}) => ({
    id,
    data,
});
(0, node_test_1.default)('groups subcollection documents by the business that owns them', () => {
    const grouped = (0, admin_firestore_join_js_1.groupByMerchant)([
        { merchantId: 'm1', data: { id: 'a' } },
        { merchantId: 'm2', data: { id: 'b' } },
        { merchantId: 'm1', data: { id: 'c' } },
        { merchantId: '', data: { id: 'orphan' } },
    ]);
    strict_1.default.equal(grouped.get('m1')?.length, 2);
    strict_1.default.equal(grouped.get('m2')?.length, 1);
    // A document with no resolvable parent is dropped rather than bucketed under
    // an empty key, where it would join onto nothing and inflate counts.
    strict_1.default.equal(grouped.has(''), false);
});
(0, node_test_1.default)('reads the name from either spelling', () => {
    const firestoreEra = (0, admin_firestore_join_js_1.buildMerchantSummary)(business('m1', { merchant_name: 'Cafe Central' }), [], [], []);
    const sqlEra = (0, admin_firestore_join_js_1.buildMerchantSummary)(business('m2', { name: 'Antigo' }), [], [], []);
    strict_1.default.equal(firestoreEra.name, 'Cafe Central');
    strict_1.default.equal(sqlEra.name, 'Antigo');
});
(0, node_test_1.default)('picks the most recently updated subscription, not an arbitrary one', () => {
    // A business accumulates subscription_state documents over its life. Picking
    // whichever arrived first would make the plan column change between loads.
    const summary = (0, admin_firestore_join_js_1.buildMerchantSummary)(business('m1'), [
        { plan_code: 'free', status: 'CANCELLED', updated_at: 100 },
        { plan_code: 'pro', status: 'ACTIVE', updated_at: 300 },
        { plan_code: 'starter', status: 'TRIAL', updated_at: 200 },
    ], [], []);
    strict_1.default.equal(summary.plan_code, 'pro');
    strict_1.default.equal(summary.subscription_status, 'ACTIVE');
});
(0, node_test_1.default)('counts staff and active staff separately', () => {
    const summary = (0, admin_firestore_join_js_1.buildMerchantSummary)(business('m1'), [], [
        { status: 'ACTIVE' },
        { status: 'active' },
        { status: 'INACTIVE' },
        {},
    ], []);
    strict_1.default.equal(summary.staff_count, 4);
    strict_1.default.equal(summary.active_staff_count, 2);
});
(0, node_test_1.default)('last operational update is the latest activity anywhere on the business', () => {
    const summary = (0, admin_firestore_join_js_1.buildMerchantSummary)(business('m1', { updated_at: 100 }), [{ updated_at: 500 }], [{ updated_at: 300 }], [{ updated_at: 200 }]);
    // The profile was edited at 100, but the subscription changed at 500. The
    // list orders by this, so it has to reflect the business being alive.
    strict_1.default.equal(summary.last_operational_update_at, 500);
});
(0, node_test_1.default)('a business with no activity at all reports null, not zero', () => {
    const summary = (0, admin_firestore_join_js_1.buildMerchantSummary)(business('m1'), [], [], []);
    strict_1.default.equal(summary.last_operational_update_at, null);
    strict_1.default.equal(summary.subscription_status, null);
    strict_1.default.equal(summary.staff_count, 0);
});
const sample = () => [
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
(0, node_test_1.default)('orders by latest activity, newest first', () => {
    const page = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { limit: 10, offset: 0 });
    strict_1.default.deepEqual(page.items.map((m) => m.id), ['m2', 'm3', 'm1']);
    strict_1.default.equal(page.total, 3);
    strict_1.default.equal(page.hasMore, false);
});
(0, node_test_1.default)('search matches a substring of id, name or phone, case-insensitively', () => {
    // Firestore cannot express this server-side. Prefix-only matching would mean
    // searching for part of a phone number returns nothing.
    const byName = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { search: 'bela', limit: 10, offset: 0 });
    strict_1.default.deepEqual(byName.items.map((m) => m.id), ['m2']);
    const byPhoneFragment = (0, admin_firestore_join_js_1.selectMerchants)(sample(), {
        search: '0000001',
        limit: 10,
        offset: 0,
    });
    strict_1.default.deepEqual(byPhoneFragment.items.map((m) => m.id), ['m1']);
    const byId = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { search: 'M3', limit: 10, offset: 0 });
    strict_1.default.deepEqual(byId.items.map((m) => m.id), ['m3']);
});
(0, node_test_1.default)('a merchant with no phone does not break the search', () => {
    const page = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { search: 'sul', limit: 10, offset: 0 });
    strict_1.default.deepEqual(page.items.map((m) => m.id), ['m3']);
});
(0, node_test_1.default)('filters by status and by plan', () => {
    const active = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { status: 'active', limit: 10, offset: 0 });
    strict_1.default.deepEqual(active.items.map((m) => m.id), ['m3', 'm1']);
    const pro = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { planCode: 'pro', limit: 10, offset: 0 });
    strict_1.default.deepEqual(pro.items.map((m) => m.id), ['m3', 'm1']);
    const none = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { status: 'NAO_EXISTE', limit: 10, offset: 0 });
    strict_1.default.equal(none.items.length, 0);
    strict_1.default.equal(none.total, 0);
});
(0, node_test_1.default)('combines search and status rather than letting one win', () => {
    const page = (0, admin_firestore_join_js_1.selectMerchants)(sample(), {
        search: 'a',
        status: 'ACTIVE',
        limit: 10,
        offset: 0,
    });
    strict_1.default.deepEqual(page.items.map((m) => m.id), ['m3', 'm1']);
});
(0, node_test_1.default)('pages without repeating or skipping a row', () => {
    const first = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { limit: 2, offset: 0 });
    const second = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { limit: 2, offset: 2 });
    strict_1.default.deepEqual(first.items.map((m) => m.id), ['m2', 'm3']);
    strict_1.default.equal(first.hasMore, true);
    strict_1.default.deepEqual(second.items.map((m) => m.id), ['m1']);
    strict_1.default.equal(second.hasMore, false);
    const seen = [...first.items, ...second.items].map((m) => m.id);
    strict_1.default.equal(new Set(seen).size, seen.length);
});
(0, node_test_1.default)('an offset past the end is empty rather than an error', () => {
    const page = (0, admin_firestore_join_js_1.selectMerchants)(sample(), { limit: 10, offset: 999 });
    strict_1.default.deepEqual(page.items, []);
    strict_1.default.equal(page.hasMore, false);
    strict_1.default.equal(page.total, 3);
});
(0, node_test_1.default)('ties break on id so ordering is stable across requests', () => {
    const tied = sample().map((m) => ({
        ...m,
        last_operational_update_at: 100,
    }));
    const once = (0, admin_firestore_join_js_1.selectMerchants)(tied, { limit: 10, offset: 0 });
    const twice = (0, admin_firestore_join_js_1.selectMerchants)([...tied].reverse(), { limit: 10, offset: 0 });
    strict_1.default.deepEqual(once.items.map((m) => m.id), twice.items.map((m) => m.id));
});
