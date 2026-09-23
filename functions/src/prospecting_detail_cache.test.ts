import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DetailCache,
  DEFAULT_CACHE_TTL_DAYS,
  EMPTY_CACHE,
} from './prospecting_detail_cache.js';

const DAY_MS = 24 * 60 * 60 * 1000;

/** A clock the test moves, so a month can pass in a microsecond. */
function clock(start = 1_700_000_000_000) {
  let at = start;
  return { now: () => at, advanceDays: (days: number) => (at += days * DAY_MS) };
}

test('a cache hit means the paid call is never made', () => {
  const cache = new DetailCache();
  let calls = 0;
  const fetchDetail = (placeId: string) => {
    const cached = cache.get(placeId);
    if (cached !== null) return cached;
    calls++;
    const detail = { phone: '+258845509796' };
    cache.put(placeId, detail, '+258845509796');
    return detail;
  };

  fetchDetail('p-gentleman');
  fetchDetail('p-gentleman');
  fetchDetail('p-gentleman');

  assert.equal(calls, 1, 'três pedidos, uma só chamada paga');
  assert.equal(cache.hits, 2);
});

test('a miss on an unknown place is not an error', () => {
  assert.equal(new DetailCache().get('nunca-visto'), null);
});

test('a null place id is never a hit', () => {
  // A provider that returned no reference gives nothing to key on, and
  // treating that as "one unnamed entry" would serve one shop's phone number
  // for another's.
  const cache = new DetailCache();
  cache.put(null, { phone: '+258840000000' }, '+258840000000');
  assert.equal(cache.get(null), null);
});

test('an entry older than the TTL is not served', () => {
  const time = clock();
  const cache = new DetailCache(EMPTY_CACHE, { now: time.now });
  cache.put('p-kubila', { phone: '+258845242789' }, '+258845242789');

  time.advanceDays(DEFAULT_CACHE_TTL_DAYS - 1);
  assert.notEqual(cache.get('p-kubila'), null, 'dentro do prazo, ainda serve');

  time.advanceDays(2);
  assert.equal(cache.get('p-kubila'), null, 'passado o prazo, paga-se de novo');
});

test('the TTL is configurable', () => {
  const time = clock();
  const cache = new DetailCache(EMPTY_CACHE, { ttlDays: 1, now: time.now });
  cache.put('p-tsemeta', { phone: '+258878187409' }, '+258878187409');
  time.advanceDays(2);
  assert.equal(cache.get('p-tsemeta'), null);
});

test('an expired entry does not count as a hit', () => {
  const time = clock();
  const cache = new DetailCache(EMPTY_CACHE, { ttlDays: 1, now: time.now });
  cache.put('p-x', { phone: null }, null);
  time.advanceDays(2);
  cache.get('p-x');
  assert.equal(cache.hits, 0, 'uma entrada expirada não poupou chamada nenhuma');
});

test('a phone leads back to the place it belongs to', () => {
  // So a chain listing every branch under one central number is recognised
  // before the second branch is paid for.
  const cache = new DetailCache();
  cache.put('p-gentleman', { phone: '+258845509796' }, '+258845509796');
  assert.equal(cache.placeForPhone('+258845509796'), 'p-gentleman');
  assert.equal(cache.placeForPhone('+258870000000'), null);
  assert.equal(cache.placeForPhone(null), null);
});

test('a detail with no phone is still cached', () => {
  const cache = new DetailCache();
  cache.put('p-sem-telefone', { phone: null }, null);
  assert.notEqual(cache.get('p-sem-telefone'), null);
});

test('what survives a restart is what was cached', () => {
  const first = new DetailCache();
  first.put('p-kubila', { phone: '+258845242789' }, '+258845242789');

  const second = new DetailCache(first.snapshot());
  assert.notEqual(second.get('p-kubila'), null);
  assert.equal(second.placeForPhone('+258845242789'), 'p-kubila');
});

test('holding the snapshot does not let a caller mutate the cache', () => {
  const cache = new DetailCache();
  cache.put('p-a', { phone: null }, null);
  const taken = cache.snapshot();
  delete taken.byPlaceId['p-a'];
  assert.notEqual(cache.get('p-a'), null);
});
