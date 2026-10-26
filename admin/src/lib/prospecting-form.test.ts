import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildLeadQuery,
  formatUsd,
  formatUsdRange,
  leadListHref,
  LEAD_PAGE_SIZE,
  parseSearchForm,
  readIndustries,
} from './prospecting-form';

/** A stand-in for FormData, which `node --test` has no DOM to provide. */
function form(entries: Array<[string, string]>) {
  return {
    get: (name: string) => entries.find(([key]) => key === name)?.[1],
    getAll: (name: string) =>
      entries.filter(([key]) => key === name).map(([, value]) => value),
  };
}

/* ------------------------------------------------------------ industries */

test('every ticked industry is read, not just the first', () => {
  // A multi-select of checkboxes arrives as repeated entries under one name.
  // Reading only the first would make the form look multi-select and behave
  // single-select, and a search would silently return a third of what it
  // should.
  assert.deepEqual(
    readIndustries(form([
      ['industries', 'barbershop'],
      ['industries', 'salon'],
      ['industries', 'spa'],
    ])),
    ['barbershop', 'salon', 'spa'],
  );
});

test('a repeated industry is counted once, and case is folded', () => {
  assert.deepEqual(
    readIndustries(form([
      ['industries', 'Barbershop'],
      ['industries', 'barbershop'],
      ['industries', '  '],
    ])),
    ['barbershop'],
  );
});

test('ticking nothing is legal and means every ICP industry', () => {
  const parsed = parseSearchForm(form([['maxLeads', '50'], ['minScore', '60']]));
  assert.equal(parsed.ok, true);
  assert.deepEqual(parsed.ok === true && parsed.values.industries, []);
});

/* ---------------------------------------------------------- the search */

test('a complete form parses', () => {
  const parsed = parseSearchForm(form([
    ['industries', 'barbershop'],
    ['city', ' Maputo '],
    ['size', '6-20'],
    ['maxLeads', '100'],
    ['minScore', '60'],
  ]));

  assert.equal(parsed.ok, true);
  assert.deepEqual(parsed.ok === true && parsed.values, {
    industries: ['barbershop'],
    city: 'Maputo',
    maxLeads: 100,
    minScore: 60,
    size: '6-20',
  });
});

test('a value outside the offered options is an error against its own field', () => {
  const parsed = parseSearchForm(form([
    ['maxLeads', '37'],
    ['minScore', '55'],
    ['size', 'enormous'],
  ]));

  assert.equal(parsed.ok, false);
  const fields = parsed.ok === false ? parsed.errors.map((e) => e.field) : [];
  assert.deepEqual([...fields].sort(), ['maxLeads', 'minScore', 'size']);
});

test('a missing choice never silently becomes a default', () => {
  // A max-leads that quietly became 25 when the operator chose 500 produces a
  // screen that looks like it worked.
  const parsed = parseSearchForm(form([['minScore', '60']]));
  assert.equal(parsed.ok, false);
  assert.ok(parsed.ok === false && parsed.errors.some((e) => e.field === 'maxLeads'));
});

test('an omitted size is legal and means any size', () => {
  const parsed = parseSearchForm(form([['maxLeads', '50'], ['minScore', '60']]));
  assert.equal(parsed.ok === true && parsed.values.size, null);
});

test('a blank city is null rather than an empty string', () => {
  const parsed = parseSearchForm(form([
    ['city', '   '],
    ['maxLeads', '50'],
    ['minScore', '60'],
  ]));
  assert.equal(parsed.ok === true && parsed.values.city, null);
});

test('an absurdly long location is refused', () => {
  const parsed = parseSearchForm(form([
    ['city', 'x'.repeat(200)],
    ['maxLeads', '50'],
    ['minScore', '60'],
  ]));
  assert.equal(parsed.ok, false);
  assert.ok(parsed.ok === false && parsed.errors.some((e) => e.field === 'city'));
});

/* -------------------------------------------------------------- the list */

test('an unfiltered page asks only for a page size', () => {
  assert.equal(buildLeadQuery({}), `?limit=${LEAD_PAGE_SIZE}`);
});

test('the first page carries no offset', () => {
  assert.equal(buildLeadQuery({ offset: 0 }), `?limit=${LEAD_PAGE_SIZE}`);
  assert.equal(buildLeadQuery({ offset: 25 }), `?limit=${LEAD_PAGE_SIZE}&offset=25`);
});

test('blank filters are left out rather than sent empty', () => {
  assert.equal(
    buildLeadQuery({ status: '   ', city: '', search: undefined }),
    `?limit=${LEAD_PAGE_SIZE}`,
  );
});

test('the default sort is not sent', () => {
  assert.equal(buildLeadQuery({ sort: 'score' }), `?limit=${LEAD_PAGE_SIZE}`);
  assert.equal(buildLeadQuery({ sort: 'newest' }), `?sort=newest&limit=${LEAD_PAGE_SIZE}`);
});

test('a filtered view is a URL that can be pasted into a conversation', () => {
  assert.equal(
    leadListHref({ status: 'SCORED', city: 'Maputo' }),
    '/admin/prospecao?status=SCORED&city=Maputo',
  );
  assert.equal(leadListHref({}), '/admin/prospecao');
});

test('a filtered view keeps its page', () => {
  assert.equal(
    leadListHref({ status: 'SCORED', offset: 50 }),
    '/admin/prospecao?status=SCORED&offset=50',
  );
});

/* ------------------------------------------------------------------ money */

test('amounts are shown to the cent, because the calls are cents', () => {
  // Rounded to the dollar, every provider call would read as $0.
  assert.equal(formatUsd(0.05), '$0.05');
  assert.equal(formatUsd(12.5), '$12.50');
  assert.equal(formatUsd(null), '—');
});

test('an estimate is marked as one', () => {
  // A number presented without a tilde will be planned against.
  assert.equal(formatUsd(12.5, true), '~$12.50');
});

test('a range collapses when both ends agree', () => {
  assert.equal(formatUsdRange(2, 20), '$2.00 – $20.00');
  assert.equal(formatUsdRange(0, 0), '$0.00');
});
