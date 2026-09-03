"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const merchant_records_1 = require("./merchant_records");
const PAGE = { limit: 50, offset: 0 };
/* -------------------------------------------------------------- normalisers */
(0, node_test_1.default)('the app stores flags as 0 and 1', () => {
    strict_1.default.equal((0, merchant_records_1.asBool)({ is_active: 1 }, 'is_active'), true);
    strict_1.default.equal((0, merchant_records_1.asBool)({ is_active: 0 }, 'is_active'), false);
    strict_1.default.equal((0, merchant_records_1.asBool)({ is_active: true }, 'is_active'), true);
    strict_1.default.equal((0, merchant_records_1.asBool)({ is_active: 'false' }, 'is_active'), false);
});
(0, node_test_1.default)('an absent flag is unknown, not disabled', () => {
    // The difference matters: `false` prints "Inativo" on the catalogue, and a
    // document written before the field existed is not an inactive item.
    strict_1.default.equal((0, merchant_records_1.asBool)({}, 'is_active'), null);
    strict_1.default.equal((0, merchant_records_1.asBool)({ is_active: 'sim' }, 'is_active'), null);
});
(0, node_test_1.default)('flag keys are tried in order', () => {
    strict_1.default.equal((0, merchant_records_1.asBool)({ active: 0, is_active: 1 }, 'active', 'is_active'), false);
});
(0, node_test_1.default)('numbers arrive as numbers or as strings', () => {
    strict_1.default.equal((0, merchant_records_1.asNumber)({ total: 12 }, 'total'), 12);
    strict_1.default.equal((0, merchant_records_1.asNumber)({ total: '12.5' }, 'total'), 12.5);
    strict_1.default.equal((0, merchant_records_1.asNumber)({ total: '' }, 'total'), null);
    strict_1.default.equal((0, merchant_records_1.asNumber)({ total: Number.NaN }, 'total'), null);
});
(0, node_test_1.default)('zero is not a timestamp', () => {
    // The app writes 0 for "never happened"; 1970 on screen would be a lie.
    strict_1.default.equal((0, merchant_records_1.asEpoch)({ last_visit_at: 0 }, 'last_visit_at'), null);
    strict_1.default.equal((0, merchant_records_1.asEpoch)({ last_visit_at: 1788307006310 }, 'last_visit_at'), 1788307006310);
});
(0, node_test_1.default)('blank strings are absent', () => {
    strict_1.default.equal((0, merchant_records_1.asString)({ name: '   ' }, 'name'), null);
    strict_1.default.equal((0, merchant_records_1.asString)({ name: '  Ana ' }, 'name'), 'Ana');
});
/* ------------------------------------------------------------------ shaping */
(0, node_test_1.default)('a customer keeps the document id when the field is missing', () => {
    const customer = (0, merchant_records_1.toCustomer)('c-1', { name: 'Ana', total_points: 40 });
    strict_1.default.equal(customer.id, 'c-1');
    strict_1.default.equal(customer.total_points, 40);
    strict_1.default.equal(customer.total_visits, 0);
    strict_1.default.equal(customer.last_visit_at, null);
});
(0, node_test_1.default)('a reward reads either spelling of its flag', () => {
    strict_1.default.equal((0, merchant_records_1.toReward)('r-1', { active: 0 }).is_active, false);
    strict_1.default.equal((0, merchant_records_1.toReward)('r-1', { is_active: 1 }).is_active, true);
});
(0, node_test_1.default)('a catalogue item without an order sorts as zero', () => {
    strict_1.default.equal((0, merchant_records_1.toCatalogItem)('i-1', {}).display_order, 0);
});
(0, node_test_1.default)('staff shape survives the seeded document', () => {
    const staff = (0, merchant_records_1.toStaff)('u1', {
        id: 'u1',
        phone: '+25884000011',
        role: 'OWNER',
        status: 'ACTIVE',
        created_at: 1788307006310,
        last_login_at: 1788307006310,
    });
    strict_1.default.equal(staff.role, 'OWNER');
    strict_1.default.equal(staff.last_login_at, 1788307006310);
});
/* -------------------------------------------------------------------- sales */
(0, node_test_1.default)('a sale keeps both status fields', () => {
    const sale = (0, merchant_records_1.toSale)('s-1', {
        amount: 350,
        points: 35,
        created_at: 1788288217358,
        cancellation_status: 'CANCELLED',
        confirmation_status: 'CONFIRMED',
    });
    strict_1.default.equal(sale.cancellation_status, 'CANCELLED');
    strict_1.default.equal(sale.confirmation_status, 'CONFIRMED');
});
(0, node_test_1.default)('a sale amount written as a string is still an amount', () => {
    // The app writes numbers, but a correction posted by hand or by an older
    // build can arrive as a string, and a null amount prints as a dash on the
    // customer's history — a visit that appears to have cost nothing.
    const sale = (0, merchant_records_1.toSale)('s-1', { amount: '350.5', points: '35' });
    strict_1.default.equal(sale.amount, 350.5);
    strict_1.default.equal(sale.points, 35);
});
(0, node_test_1.default)('sales sort newest first, undated last', () => {
    const sorted = (0, merchant_records_1.sortSales)([
        (0, merchant_records_1.toSale)('a', { created_at: 100 }),
        (0, merchant_records_1.toSale)('b', {}),
        (0, merchant_records_1.toSale)('c', { created_at: 900 }),
    ]);
    strict_1.default.deepEqual(sorted.map((row) => row.id), ['c', 'a', 'b']);
});
/* ------------------------------------------------------------- the read cap */
(0, node_test_1.default)('a collection sitting exactly on the cap is not truncated', () => {
    // The reader asks for cap + 1 precisely so this case is distinguishable. Off
    // by one here tells a business its list is incomplete when it is whole.
    const capped = (0, merchant_records_1.capDocuments)([1, 2, 3], 3);
    strict_1.default.equal(capped.truncated, false);
    strict_1.default.deepEqual(capped.docs, [1, 2, 3]);
});
(0, node_test_1.default)('one document past the cap is truncated, and the extra is dropped', () => {
    const capped = (0, merchant_records_1.capDocuments)([1, 2, 3, 4], 3);
    strict_1.default.equal(capped.truncated, true);
    strict_1.default.deepEqual(capped.docs, [1, 2, 3]);
});
/* ---------------------------------------------------------------- searching */
(0, node_test_1.default)('search ignores accents and case', () => {
    strict_1.default.equal((0, merchant_records_1.fold)('João'), 'joao');
    strict_1.default.equal((0, merchant_records_1.fold)('  ÁGUA '), 'agua');
});
const customers = [
    {
        ...(0, merchant_records_1.toCustomer)('c-1', { name: 'João Matola', phone: '+258840000001' }),
        last_visit_at: 300,
    },
    {
        ...(0, merchant_records_1.toCustomer)('c-2', { name: 'Ana Sitoe', phone: '+258840000002' }),
        last_visit_at: 900,
    },
    {
        ...(0, merchant_records_1.toCustomer)('c-3', { name: 'Bento Cossa', phone: '+258840000003' }),
        relationship_status: 'BLOCKED',
    },
    { ...(0, merchant_records_1.toCustomer)('c-4', { name: 'Zita Nhaca' }) },
];
(0, node_test_1.default)('customers list by most recent visit, never-visited last by name', () => {
    const page = (0, merchant_records_1.selectCustomers)(customers, PAGE);
    strict_1.default.deepEqual(page.items.map((row) => row.id), ['c-2', 'c-1', 'c-3', 'c-4']);
});
(0, node_test_1.default)('a customer is found by an unaccented spelling of their name', () => {
    const page = (0, merchant_records_1.selectCustomers)(customers, { ...PAGE, search: 'joao' });
    strict_1.default.deepEqual(page.items.map((row) => row.id), ['c-1']);
});
(0, node_test_1.default)('a customer is found by the tail of their phone', () => {
    const page = (0, merchant_records_1.selectCustomers)(customers, { ...PAGE, search: '0000002' });
    strict_1.default.deepEqual(page.items.map((row) => row.id), ['c-2']);
});
(0, node_test_1.default)('status filters against the app default, not against absence', () => {
    const active = (0, merchant_records_1.selectCustomers)(customers, { ...PAGE, status: 'ACTIVE' });
    strict_1.default.deepEqual(active.items.map((row) => row.id), ['c-2', 'c-1', 'c-4']);
    const blocked = (0, merchant_records_1.selectCustomers)(customers, { ...PAGE, status: 'blocked' });
    strict_1.default.deepEqual(blocked.items.map((row) => row.id), ['c-3']);
});
/* ------------------------------------------------------------------- paging */
(0, node_test_1.default)('paging reports whether anything is left', () => {
    const first = (0, merchant_records_1.selectCustomers)(customers, { limit: 2, offset: 0 });
    strict_1.default.equal(first.items.length, 2);
    strict_1.default.equal(first.hasMore, true);
    strict_1.default.equal(first.total, 4);
    const last = (0, merchant_records_1.selectCustomers)(customers, { limit: 2, offset: 2 });
    strict_1.default.equal(last.hasMore, false);
});
(0, node_test_1.default)('an offset past the end is an empty page, not an error', () => {
    const page = (0, merchant_records_1.paginate)([1, 2, 3], { limit: 10, offset: 99 });
    strict_1.default.deepEqual(page.items, []);
    strict_1.default.equal(page.hasMore, false);
    strict_1.default.equal(page.total, 3);
});
(0, node_test_1.default)('a nonsense limit still returns something', () => {
    strict_1.default.equal((0, merchant_records_1.paginate)([1, 2, 3], { limit: 0, offset: -5 }).items.length, 1);
});
/* ---------------------------------------------------- catalogue and rewards */
const catalog = [
    (0, merchant_records_1.toCatalogItem)('i-1', { name: 'Corte', type: 'SERVICE', display_order: 2, is_active: 1 }),
    (0, merchant_records_1.toCatalogItem)('i-2', { name: 'Gel', type: 'PRODUCT', display_order: 1, is_active: 0 }),
    (0, merchant_records_1.toCatalogItem)('i-3', { name: 'Barba', type: 'SERVICE' }),
];
(0, node_test_1.default)('the catalogue keeps the order the till shows', () => {
    strict_1.default.deepEqual((0, merchant_records_1.selectCatalog)(catalog, PAGE).items.map((row) => row.id), ['i-3', 'i-2', 'i-1']);
});
(0, node_test_1.default)('filtering by type and by state are separate questions', () => {
    strict_1.default.deepEqual((0, merchant_records_1.selectCatalog)(catalog, { ...PAGE, status: 'SERVICE' }).items.map((r) => r.id), ['i-3', 'i-1']);
    strict_1.default.deepEqual((0, merchant_records_1.selectCatalog)(catalog, { ...PAGE, status: 'INACTIVE' }).items.map((r) => r.id), ['i-2']);
});
(0, node_test_1.default)('an item with no flag counts as active', () => {
    const ids = (0, merchant_records_1.selectCatalog)(catalog, { ...PAGE, status: 'ACTIVE' }).items.map((row) => row.id);
    strict_1.default.ok(ids.includes('i-3'));
});
const rewards = [
    (0, merchant_records_1.toReward)('r-1', { name: 'Café grátis', points_required: 100, active: 1 }),
    (0, merchant_records_1.toReward)('r-2', { name: 'Desconto', points_required: 30, active: 0 }),
];
(0, node_test_1.default)('rewards list cheapest first', () => {
    strict_1.default.deepEqual((0, merchant_records_1.selectRewards)(rewards, PAGE).items.map((row) => row.id), ['r-2', 'r-1']);
});
/* -------------------------------------------------------------------- staff */
const staff = [
    (0, merchant_records_1.toStaff)('u-1', { role: 'STAFF', status: 'ACTIVE', last_login_at: 900 }),
    (0, merchant_records_1.toStaff)('u-2', { role: 'OWNER', status: 'ACTIVE', last_login_at: 100 }),
    (0, merchant_records_1.toStaff)('u-3', { role: 'MANAGER', status: 'INACTIVE', last_login_at: 500 }),
];
(0, node_test_1.default)('the owner leads the team list regardless of last sign-in', () => {
    strict_1.default.deepEqual((0, merchant_records_1.selectStaff)(staff, PAGE).items.map((row) => row.id), ['u-2', 'u-3', 'u-1']);
});
(0, node_test_1.default)('team status filter is exact', () => {
    strict_1.default.deepEqual((0, merchant_records_1.selectStaff)(staff, { ...PAGE, status: 'INACTIVE' }).items.map((r) => r.id), ['u-3']);
});
