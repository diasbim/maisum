import assert from 'node:assert/strict';
import test from 'node:test';

import {
  asBool,
  asEpoch,
  asNumber,
  asString,
  capDocuments,
  fold,
  paginate,
  sortSales,
  toSale,
  selectCatalog,
  selectCustomers,
  selectRewards,
  selectStaff,
  toCatalogItem,
  toCustomer,
  toReward,
  renderSurveyAnswer,
  toStaff,
  toSurveyQuestion,
  toSurveyResponse,
  type CatalogItemRecord,
  type CustomerRecord,
  type RewardRecord,
  type StaffRecord,
} from './merchant_records';

const PAGE = { limit: 50, offset: 0 };

/* -------------------------------------------------------------- normalisers */

test('the app stores flags as 0 and 1', () => {
  assert.equal(asBool({ is_active: 1 }, 'is_active'), true);
  assert.equal(asBool({ is_active: 0 }, 'is_active'), false);
  assert.equal(asBool({ is_active: true }, 'is_active'), true);
  assert.equal(asBool({ is_active: 'false' }, 'is_active'), false);
});

test('an absent flag is unknown, not disabled', () => {
  // The difference matters: `false` prints "Inativo" on the catalogue, and a
  // document written before the field existed is not an inactive item.
  assert.equal(asBool({}, 'is_active'), null);
  assert.equal(asBool({ is_active: 'sim' }, 'is_active'), null);
});

test('flag keys are tried in order', () => {
  assert.equal(asBool({ active: 0, is_active: 1 }, 'active', 'is_active'), false);
});

test('numbers arrive as numbers or as strings', () => {
  assert.equal(asNumber({ total: 12 }, 'total'), 12);
  assert.equal(asNumber({ total: '12.5' }, 'total'), 12.5);
  assert.equal(asNumber({ total: '' }, 'total'), null);
  assert.equal(asNumber({ total: Number.NaN }, 'total'), null);
});

test('zero is not a timestamp', () => {
  // The app writes 0 for "never happened"; 1970 on screen would be a lie.
  assert.equal(asEpoch({ last_visit_at: 0 }, 'last_visit_at'), null);
  assert.equal(asEpoch({ last_visit_at: 1788307006310 }, 'last_visit_at'), 1788307006310);
});

test('blank strings are absent', () => {
  assert.equal(asString({ name: '   ' }, 'name'), null);
  assert.equal(asString({ name: '  Ana ' }, 'name'), 'Ana');
});

/* ------------------------------------------------------------------ shaping */

test('a customer keeps the document id when the field is missing', () => {
  const customer = toCustomer('c-1', { name: 'Ana', total_points: 40 });
  assert.equal(customer.id, 'c-1');
  assert.equal(customer.total_points, 40);
  assert.equal(customer.total_visits, 0);
  assert.equal(customer.last_visit_at, null);
});

test('a reward reads either spelling of its flag', () => {
  assert.equal(toReward('r-1', { active: 0 }).is_active, false);
  assert.equal(toReward('r-1', { is_active: 1 }).is_active, true);
});

test('a catalogue item without an order sorts as zero', () => {
  assert.equal(toCatalogItem('i-1', {}).display_order, 0);
});

test('staff shape survives the seeded document', () => {
  const staff = toStaff('u1', {
    id: 'u1',
    phone: '+25884000011',
    role: 'OWNER',
    status: 'ACTIVE',
    created_at: 1788307006310,
    last_login_at: 1788307006310,
  });
  assert.equal(staff.role, 'OWNER');
  assert.equal(staff.last_login_at, 1788307006310);
});

/* -------------------------------------------------------------------- sales */

test('a sale keeps both status fields', () => {
  const sale = toSale('s-1', {
    amount: 350,
    points: 35,
    created_at: 1788288217358,
    cancellation_status: 'CANCELLED',
    confirmation_status: 'CONFIRMED',
  });
  assert.equal(sale.cancellation_status, 'CANCELLED');
  assert.equal(sale.confirmation_status, 'CONFIRMED');
});

test('a sale amount written as a string is still an amount', () => {
  // The app writes numbers, but a correction posted by hand or by an older
  // build can arrive as a string, and a null amount prints as a dash on the
  // customer's history — a visit that appears to have cost nothing.
  const sale = toSale('s-1', { amount: '350.5', points: '35' });
  assert.equal(sale.amount, 350.5);
  assert.equal(sale.points, 35);
});

test('sales sort newest first, undated last', () => {
  const sorted = sortSales([
    toSale('a', { created_at: 100 }),
    toSale('b', {}),
    toSale('c', { created_at: 900 }),
  ]);
  assert.deepEqual(
    sorted.map((row) => row.id),
    ['c', 'a', 'b'],
  );
});

/* ------------------------------------------------------------- the read cap */

test('a collection sitting exactly on the cap is not truncated', () => {
  // The reader asks for cap + 1 precisely so this case is distinguishable. Off
  // by one here tells a business its list is incomplete when it is whole.
  const capped = capDocuments([1, 2, 3], 3);
  assert.equal(capped.truncated, false);
  assert.deepEqual(capped.docs, [1, 2, 3]);
});

test('one document past the cap is truncated, and the extra is dropped', () => {
  const capped = capDocuments([1, 2, 3, 4], 3);
  assert.equal(capped.truncated, true);
  assert.deepEqual(capped.docs, [1, 2, 3]);
});

/* ---------------------------------------------------------------- searching */

test('search ignores accents and case', () => {
  assert.equal(fold('João'), 'joao');
  assert.equal(fold('  ÁGUA '), 'agua');
});

const customers: CustomerRecord[] = [
  {
    ...toCustomer('c-1', { name: 'João Matola', phone: '+258840000001' }),
    last_visit_at: 300,
  },
  {
    ...toCustomer('c-2', { name: 'Ana Sitoe', phone: '+258840000002' }),
    last_visit_at: 900,
  },
  {
    ...toCustomer('c-3', { name: 'Bento Cossa', phone: '+258840000003' }),
    relationship_status: 'BLOCKED',
  },
  { ...toCustomer('c-4', { name: 'Zita Nhaca' }) },
];

test('customers list by most recent visit, never-visited last by name', () => {
  const page = selectCustomers(customers, PAGE);
  assert.deepEqual(
    page.items.map((row) => row.id),
    ['c-2', 'c-1', 'c-3', 'c-4'],
  );
});

test('a customer is found by an unaccented spelling of their name', () => {
  const page = selectCustomers(customers, { ...PAGE, search: 'joao' });
  assert.deepEqual(page.items.map((row) => row.id), ['c-1']);
});

test('a customer is found by the tail of their phone', () => {
  const page = selectCustomers(customers, { ...PAGE, search: '0000002' });
  assert.deepEqual(page.items.map((row) => row.id), ['c-2']);
});

test('status filters against the app default, not against absence', () => {
  const active = selectCustomers(customers, { ...PAGE, status: 'ACTIVE' });
  assert.deepEqual(active.items.map((row) => row.id), ['c-2', 'c-1', 'c-4']);

  const blocked = selectCustomers(customers, { ...PAGE, status: 'blocked' });
  assert.deepEqual(blocked.items.map((row) => row.id), ['c-3']);
});

/* ------------------------------------------------------------------- paging */

test('paging reports whether anything is left', () => {
  const first = selectCustomers(customers, { limit: 2, offset: 0 });
  assert.equal(first.items.length, 2);
  assert.equal(first.hasMore, true);
  assert.equal(first.total, 4);

  const last = selectCustomers(customers, { limit: 2, offset: 2 });
  assert.equal(last.hasMore, false);
});

test('an offset past the end is an empty page, not an error', () => {
  const page = paginate([1, 2, 3], { limit: 10, offset: 99 });
  assert.deepEqual(page.items, []);
  assert.equal(page.hasMore, false);
  assert.equal(page.total, 3);
});

test('a nonsense limit still returns something', () => {
  assert.equal(paginate([1, 2, 3], { limit: 0, offset: -5 }).items.length, 1);
});

/* ---------------------------------------------------- catalogue and rewards */

const catalog: CatalogItemRecord[] = [
  toCatalogItem('i-1', { name: 'Corte', type: 'SERVICE', display_order: 2, is_active: 1 }),
  toCatalogItem('i-2', { name: 'Gel', type: 'PRODUCT', display_order: 1, is_active: 0 }),
  toCatalogItem('i-3', { name: 'Barba', type: 'SERVICE' }),
];

test('the catalogue keeps the order the till shows', () => {
  assert.deepEqual(
    selectCatalog(catalog, PAGE).items.map((row) => row.id),
    ['i-3', 'i-2', 'i-1'],
  );
});

test('filtering by type and by state are separate questions', () => {
  assert.deepEqual(
    selectCatalog(catalog, { ...PAGE, status: 'SERVICE' }).items.map((r) => r.id),
    ['i-3', 'i-1'],
  );
  assert.deepEqual(
    selectCatalog(catalog, { ...PAGE, status: 'INACTIVE' }).items.map((r) => r.id),
    ['i-2'],
  );
});

test('an item with no flag counts as active', () => {
  const ids = selectCatalog(catalog, { ...PAGE, status: 'ACTIVE' }).items.map(
    (row) => row.id,
  );
  assert.ok(ids.includes('i-3'));
});

const rewards: RewardRecord[] = [
  toReward('r-1', { name: 'Café grátis', points_required: 100, active: 1 }),
  toReward('r-2', { name: 'Desconto', points_required: 30, active: 0 }),
];

test('rewards list cheapest first', () => {
  assert.deepEqual(
    selectRewards(rewards, PAGE).items.map((row) => row.id),
    ['r-2', 'r-1'],
  );
});

/* -------------------------------------------------------------------- staff */

const staff: StaffRecord[] = [
  toStaff('u-1', { role: 'STAFF', status: 'ACTIVE', last_login_at: 900 }),
  toStaff('u-2', { role: 'OWNER', status: 'ACTIVE', last_login_at: 100 }),
  toStaff('u-3', { role: 'MANAGER', status: 'INACTIVE', last_login_at: 500 }),
];

test('the owner leads the team list regardless of last sign-in', () => {
  assert.deepEqual(
    selectStaff(staff, PAGE).items.map((row) => row.id),
    ['u-2', 'u-3', 'u-1'],
  );
});

test('team status filter is exact', () => {
  assert.deepEqual(
    selectStaff(staff, { ...PAGE, status: 'INACTIVE' }).items.map((r) => r.id),
    ['u-3'],
  );
});

/* ------------------------------------------------- survey responses */

test('an answer is rendered from whichever column carries it', () => {
  assert.equal(renderSurveyAnswer({ answer_text: 'Preço' }), 'Preço');
  assert.equal(renderSurveyAnswer({ answer_numeric: 4 }), '4');
  assert.equal(renderSurveyAnswer({ answer_bool: true }), 'Sim');
  assert.equal(renderSurveyAnswer({ answer_bool: false }), 'Não');
});

test('a boolean answer is never printed as true or false', () => {
  // "true" is not an answer anybody gave.
  for (const value of [true, false, 1, 0]) {
    const rendered = renderSurveyAnswer({ answer_bool: value });
    assert.ok(rendered === 'Sim' || rendered === 'Não', `got ${rendered}`);
  }
});

test('a rating of zero is an answer, not an absent one', () => {
  assert.equal(renderSurveyAnswer({ answer_numeric: 0 }), '0');
});

test('an empty text answer falls through rather than printing blank', () => {
  assert.equal(renderSurveyAnswer({ answer_text: '   ', answer_numeric: 3 }), '3');
  assert.equal(renderSurveyAnswer({}), null);
});

test('a response keeps its document id and leaves the joins to the caller', () => {
  const response = toSurveyResponse('resp-1', {
    survey_id: 'survey-1',
    customer_id: 'cust-1',
    channel: 'whatsapp',
    created_at: 1788307006310,
  });

  assert.equal(response.id, 'resp-1');
  assert.equal(response.survey_id, 'survey-1');
  assert.equal(response.channel, 'whatsapp');
  assert.equal(response.submitted_at, 1788307006310);
  // Both are joined in the collection layer, never stored on the row.
  assert.equal(response.customer_name, null);
  assert.equal(response.survey_title, null);
  assert.deepEqual(response.answers, []);
});

test('an anonymous response has no customer, which is not an error', () => {
  const response = toSurveyResponse('resp-1', { survey_id: 'survey-1' });
  assert.equal(response.customer_id, null);
  assert.equal(response.customer_name, null);
});

test('a question carries the order the merchant put it in', () => {
  const question = toSurveyQuestion('q-1', {
    survey_id: 'survey-1',
    question_text: 'Porque não voltou?',
    question_type: 'MULTIPLE_CHOICE',
    sort_order: 2,
  });

  assert.equal(question.question_text, 'Porque não voltou?');
  assert.equal(question.question_type, 'MULTIPLE_CHOICE');
  assert.equal(question.sort_order, 2);
});

test('a question with no stored order sorts first rather than crashing', () => {
  assert.equal(toSurveyQuestion('q-1', {}).sort_order, 0);
});
