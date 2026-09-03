import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildListQuery,
  MERCHANT_PAGE_SIZE,
  toMerchantList,
} from './merchant-list';

/* ------------------------------------------------------------- the query URL */

test('an unfiltered page asks only for a page size', () => {
  assert.equal(buildListQuery({}), `?limit=${MERCHANT_PAGE_SIZE}`);
});

test('the first page carries no offset', () => {
  // `offset=0` and no offset mean the same thing, and only one of them makes a
  // link worth pasting into a message.
  assert.equal(buildListQuery({ offset: 0 }), `?limit=${MERCHANT_PAGE_SIZE}`);
  assert.equal(
    buildListQuery({ offset: 25 }),
    `?limit=${MERCHANT_PAGE_SIZE}&offset=25`,
  );
});

test('blank filters are left out rather than sent empty', () => {
  assert.equal(
    buildListQuery({ search: '   ', status: '' }),
    `?limit=${MERCHANT_PAGE_SIZE}`,
  );
});

test('a search is trimmed and escaped', () => {
  assert.equal(
    buildListQuery({ search: '  João Matola ' }),
    `?search=Jo%C3%A3o+Matola&limit=${MERCHANT_PAGE_SIZE}`,
  );
});

test('a phone number survives the query string intact', () => {
  // `+` is the one character that would come back as a space if it were not
  // encoded, and every phone in this product starts with one.
  const query = buildListQuery({ search: '+258840000101' });
  assert.ok(query.includes('search=%2B258840000101'));
  assert.equal(
    new URLSearchParams(query.slice(1)).get('search'),
    '+258840000101',
  );
});

test('filters and paging travel together', () => {
  const query = buildListQuery({
    search: 'ana',
    status: 'BLOCKED',
    limit: 10,
    offset: 30,
  });
  const params = new URLSearchParams(query.slice(1));
  assert.equal(params.get('search'), 'ana');
  assert.equal(params.get('status'), 'BLOCKED');
  assert.equal(params.get('limit'), '10');
  assert.equal(params.get('offset'), '30');
});

/* -------------------------------------------------------------- the envelope */

test('a full envelope arrives as the screen expects it', () => {
  const list = toMerchantList({
    data: [{ id: 'c-1' }, { id: 'c-2' }],
    paging: { limit: 25, offset: 0, has_more: true },
    total: 40,
    truncated: false,
  });
  assert.equal(list.items.length, 2);
  assert.equal(list.hasMore, true);
  assert.equal(list.total, 40);
  assert.equal(list.truncated, false);
});

test('an envelope with no rows is an empty list, not a crash', () => {
  const list = toMerchantList({});
  assert.deepEqual(list.items, []);
  assert.equal(list.hasMore, false);
  assert.equal(list.total, 0);
  assert.equal(list.truncated, false);
});

test('a missing total falls back to what actually arrived', () => {
  // Zero would print "Nenhum cliente" above a full table — worse than a count
  // that is merely conservative.
  const list = toMerchantList({ data: [{ id: 'c-1' }, { id: 'c-2' }] });
  assert.equal(list.total, 2);
});

test('a missing has_more shows one page rather than breaking the table', () => {
  const list = toMerchantList({ data: [{ id: 'c-1' }], total: 1 });
  assert.equal(list.hasMore, false);
});

test('truncation is carried through, because the screen says it out loud', () => {
  assert.equal(toMerchantList({ data: [], truncated: true }).truncated, true);
});
