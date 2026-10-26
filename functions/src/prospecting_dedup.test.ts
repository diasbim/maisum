/**
 * Deduplication, tested against the run that paid for it.
 *
 * The fixture lives in `prospecting_dedup_fixture.ts`: a real search that cost
 * $0.17, of which $0.06 bought the same phone number three times. These tests
 * assert that the same twenty listings now cost less and reach more
 * businesses.
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  dedupeCandidates,
  distanceMetres,
  matchName,
  SeenContacts,
  DEFAULT_DEDUP_RADIUS_METRES,
} from './prospecting_dedup.js';
import { normalizeMatchName } from './prospecting_normalization.js';
import { MAPUTO_RUN } from './prospecting_dedup_fixture.js';

const CURLY = String.fromCharCode(0x2019);

type Point = { latitude: number; longitude: number };

/**
 * A point a given distance due east. Rough, and rough is enough: every
 * assertion is well inside or well outside the radius, never on it.
 */
const at = (point: Point, metresEast: number): Point => ({
  latitude: point.latitude,
  longitude:
    point.longitude + metresEast / (111_320 * Math.cos((point.latitude * Math.PI) / 180)),
});

const GENTLEMANS: Point = {
  latitude: MAPUTO_RUN[0].latitude as number,
  longitude: MAPUTO_RUN[0].longitude as number,
};

/* ------------------------------------------------------------ the folding */

test('the three apostrophes are one business', () => {
  const names = MAPUTO_RUN.slice(0, 3).map((row) => matchName(row.name));
  assert.equal(new Set(names).size, 1, 'as três variantes deviam dobrar no mesmo texto');
});

test('the trade word does not distinguish a business', () => {
  // "Barber Shop" and "Barbershop" are the same word written two ways, and
  // the run contained both spellings.
  assert.equal(matchName('Tsemeta Barbershop'), matchName('Tsemeta Barber Shop'));
});

test('a name that is nothing but trade words keeps a key of its own', () => {
  // Otherwise every generically named shop in the city merges into one lead
  // and the operator never learns the others existed.
  assert.equal(normalizeMatchName('Barber Shop'), '');
  assert.notEqual(matchName('Barber Shop'), '');
  assert.notEqual(matchName('Barber Shop'), matchName('Hair Studio'));
});

test('the stored name is untouched — folding is for comparing', () => {
  const original = 'Gentleman' + CURLY + 's Barber Shop';
  matchName(original);
  assert.equal(original, 'Gentleman' + CURLY + 's Barber Shop');
});

/* ----------------------------------------------------------- the distance */

test('distance is metres, and the radius separates a doorway from a district', () => {
  assert.ok(distanceMetres(GENTLEMANS, at(GENTLEMANS, 12)) < DEFAULT_DEDUP_RADIUS_METRES);
  assert.ok(distanceMetres(GENTLEMANS, at(GENTLEMANS, 900)) > DEFAULT_DEDUP_RADIUS_METRES);
});

/* -------------------------------------------------------------- the dedup */

test('the run collapses from twenty listings to eighteen businesses', () => {
  const { kept, duplicates } = dedupeCandidates(MAPUTO_RUN);
  assert.equal(kept.length, 18);
  assert.equal(duplicates.length, 2);
});

test('the surviving Gentleman is the best-evidenced one, not the first', () => {
  const { kept, duplicates } = dedupeCandidates(MAPUTO_RUN);
  const gentlemanKey = matchName(MAPUTO_RUN[0].name);
  const gentlemen = kept.filter((row) => matchName(row.name) === gentlemanKey);
  assert.equal(gentlemen.length, 1);
  assert.equal(gentlemen[0].reviewCount, 56);
  // Every discarded copy names the one it was merged into, so the report can
  // show the operator the arithmetic rather than a shorter list.
  for (const duplicate of duplicates) {
    assert.equal(matchName(duplicate.duplicateOf.name), matchName(duplicate.candidate.name));
    assert.equal(duplicate.reason, 'SAME_NAME_NEARBY');
  }
});

test('an identical source reference is decisive on its own', () => {
  const twice = [MAPUTO_RUN[5], { ...MAPUTO_RUN[5], name: 'Outro Nome Completamente' }];
  const { kept, duplicates } = dedupeCandidates(twice);
  assert.equal(kept.length, 1);
  assert.equal(duplicates[0].reason, 'SAME_SOURCE_REFERENCE');
});

test('the same name far apart is two businesses, not one', () => {
  const far = [
    { ...MAPUTO_RUN[0], sourceReference: 'a' },
    { ...MAPUTO_RUN[0], sourceReference: 'b', ...at(GENTLEMANS, 4_000) },
  ];
  assert.equal(dedupeCandidates(far).kept.length, 2);
});

test('without coordinates the match is weaker, and says so', () => {
  const blind = [
    { ...MAPUTO_RUN[0], latitude: null, longitude: null },
    { ...MAPUTO_RUN[2], latitude: null, longitude: null },
  ];
  const { kept, duplicates } = dedupeCandidates(blind);
  assert.equal(kept.length, 1);
  assert.equal(duplicates[0].reason, 'SAME_NAME_NO_LOCATION');
});

test('a null review count loses to a stated one', () => {
  // Null means the source said nothing, not that the shop has no reviews —
  // so the listing that carries evidence is the one worth keeping.
  const pair = [
    { ...MAPUTO_RUN[0], sourceReference: 'a', reviewCount: null },
    { ...MAPUTO_RUN[0], sourceReference: 'b', reviewCount: 4 },
  ];
  assert.equal(dedupeCandidates(pair).kept[0].reviewCount, 4);
});

/* ------------------------------------------------- the pass after payment */

test('a repeated phone is caught even when the names differ', () => {
  const seen = new SeenContacts();
  assert.equal(seen.observe({ phone: '+258845509796', domain: null }).duplicate, false);
  const second = seen.observe({ phone: '+258845509796', domain: 'outro.co.mz' });
  assert.equal(second.duplicate, true);
  assert.equal(second.by, 'phone');
});

test('a repeated domain is caught too', () => {
  const seen = new SeenContacts();
  seen.observe({ phone: '+258840000001', domain: 'gentlemans.co.mz' });
  const second = seen.observe({ phone: '+258840000002', domain: 'gentlemans.co.mz' });
  assert.equal(second.duplicate, true);
  assert.equal(second.by, 'domain');
});

test('a third copy is caught, because a second sighting is still recorded', () => {
  const seen = new SeenContacts();
  seen.observe({ phone: '+258845509796', domain: null });
  seen.observe({ phone: '+258845509796', domain: null });
  assert.equal(seen.observe({ phone: '+258845509796', domain: null }).duplicate, true);
});

test('two businesses that share nothing are not duplicates', () => {
  const seen = new SeenContacts();
  seen.observe({ phone: '+258845509796', domain: 'gentlemans.co.mz' });
  assert.equal(
    seen.observe({ phone: '+258878187409', domain: 'tsemeta.co.mz' }).duplicate,
    false,
  );
});

test('nothing known is never a duplicate of nothing known', () => {
  // Two listings with neither phone nor site have not been shown to be the
  // same business; treating them as one would discard a real lead.
  const seen = new SeenContacts();
  seen.observe({ phone: null, domain: null });
  assert.equal(seen.observe({ phone: null, domain: null }).duplicate, false);
});
