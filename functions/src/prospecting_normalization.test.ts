import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildMatchKeys,
  matchKeyDocId,
  normalizeCity,
  normalizeCompanyName,
  normalizeDomain,
  normalizePhone,
  normalizeSocialUrl,
} from './prospecting_normalization.js';

const MZ = '+258';

/* ----------------------------------------------------------------- domain */

test('the example from the plan folds to one domain', () => {
  // The two spellings §6 names, which must not produce two companies.
  assert.equal(normalizeDomain('https://Barbearia-X.co.mz/'), 'barbearia-x.co.mz');
  assert.equal(normalizeDomain('http://www.barbearia-x.co.mz'), 'barbearia-x.co.mz');
  assert.equal(
    normalizeDomain('https://Barbearia-X.co.mz/'),
    normalizeDomain('http://www.barbearia-x.co.mz'),
  );
});

test('a query string, a path, a port and a trailing dot all fall away', () => {
  assert.equal(
    normalizeDomain('https://barbearia-x.co.mz:443/contactos?utm_source=ig#topo'),
    'barbearia-x.co.mz',
  );
  assert.equal(normalizeDomain('barbearia-x.co.mz.'), 'barbearia-x.co.mz');
});

test('a bare domain needs no scheme', () => {
  assert.equal(normalizeDomain('barbearia-x.co.mz'), 'barbearia-x.co.mz');
});

test('anything that is not a host is null, never an empty string', () => {
  // An empty string would collide every website-less company onto one key,
  // which is the one failure that merges unrelated businesses.
  assert.equal(normalizeDomain(''), null);
  assert.equal(normalizeDomain('   '), null);
  assert.equal(normalizeDomain('localhost'), null);
  assert.equal(normalizeDomain('not a domain'), null);
  assert.equal(normalizeDomain(null), null);
  assert.equal(normalizeDomain(42), null);
});

/* ------------------------------------------------------------------ phone */

test('a Mozambican mobile normalises to E.164 however it was written', () => {
  const expected = '+258841234567';
  assert.equal(normalizePhone('+258841234567', MZ), expected);
  assert.equal(normalizePhone('+258 84 123 4567', MZ), expected);
  assert.equal(normalizePhone('(+258) 84-123-4567', MZ), expected);
  assert.equal(normalizePhone('00258841234567', MZ), expected);
  assert.equal(normalizePhone('084 123 4567', MZ), expected);
  assert.equal(normalizePhone('841234567', MZ), expected);
});

test('a business landline is accepted, unlike the customer normaliser', () => {
  // +258 21 is a Maputo landline. The customer-core normaliser rejects it
  // because a customer has a mobile; a salon's published number is often this.
  assert.equal(normalizePhone('+258 21 300 400', MZ), '+25821300400');
});

test('a number that already carries another country code keeps it', () => {
  assert.equal(normalizePhone('+351 912 345 678', MZ), '+351912345678');
});

test('the country code is configuration, not an assumption', () => {
  assert.equal(normalizePhone('912345678', '+351'), '+351912345678');
});

test('something that is not a phone number is null', () => {
  assert.equal(normalizePhone('', MZ), null);
  assert.equal(normalizePhone('abc', MZ), null);
  assert.equal(normalizePhone('123', MZ), null);
  assert.equal(normalizePhone('1234567890123456789', MZ), null);
  assert.equal(normalizePhone(null, MZ), null);
});

/* ------------------------------------------------------------------- name */

test('accents, punctuation and case all fold away', () => {
  assert.equal(normalizeCompanyName('Salão Beleza'), 'salao beleza');
  assert.equal(normalizeCompanyName('SALAO  BELEZA!'), 'salao beleza');
  assert.equal(normalizeCompanyName('Salão, Beleza.'), 'salao beleza');
});

test('legal suffixes are stripped, including more than one', () => {
  assert.equal(normalizeCompanyName('Barbearia X, Lda'), 'barbearia x');
  assert.equal(normalizeCompanyName('Barbearia X SA'), 'barbearia x');
  assert.equal(normalizeCompanyName('Barbearia X EI'), 'barbearia x');
  assert.equal(normalizeCompanyName('Barbearia X Lda Unipessoal'), 'barbearia x');
  assert.equal(normalizeCompanyName('Barbearia X Limitada'), 'barbearia x');
});

test('an ampersand is a word, not punctuation', () => {
  assert.equal(normalizeCompanyName('Silva & Filhos'), 'silva e filhos');
});

test('a name that is only a legal form folds to nothing rather than to the suffix', () => {
  assert.equal(normalizeCompanyName('Lda'), '');
  assert.equal(normalizeCompanyName('  '), '');
  assert.equal(normalizeCompanyName(null), '');
});

test('a city folds the same way', () => {
  assert.equal(normalizeCity('Maputo'), 'maputo');
  assert.equal(normalizeCity(' MATOLA '), 'matola');
  assert.equal(normalizeCity('Maputo Cidade'), 'maputo cidade');
});

/* ----------------------------------------------------------------- social */

test('the four ways of writing one Instagram profile fold to one key', () => {
  const expected = 'instagram.com/barbearia_x';
  assert.equal(normalizeSocialUrl('https://instagram.com/barbearia_x'), expected);
  assert.equal(normalizeSocialUrl('https://www.instagram.com/barbearia_x/'), expected);
  assert.equal(
    normalizeSocialUrl('https://instagram.com/barbearia_x?igshid=abc'),
    expected,
  );
  assert.equal(normalizeSocialUrl('instagram.com/barbearia_x'), expected);
});

test('a LinkedIn company page keeps the segment that identifies the company', () => {
  assert.equal(
    normalizeSocialUrl('https://linkedin.com/company/barbearia-x'),
    'linkedin.com/company/barbearia-x',
  );
});

test('a link to the network rather than to anyone on it is null', () => {
  assert.equal(normalizeSocialUrl('https://instagram.com'), null);
  assert.equal(normalizeSocialUrl('https://instagram.com/'), null);
});

/* -------------------------------------------------------------- match keys */

test('the keys come back strongest first', () => {
  const keys = buildMatchKeys(
    {
      provider: 'apollo',
      providerOrgId: 'org_1',
      website: 'https://barbearia-x.co.mz',
      phone: '+258841234567',
      name: 'Barbearia X, Lda',
      city: 'Maputo',
      instagramUrl: 'https://instagram.com/barbearia_x',
    },
    MZ,
  );

  assert.deepEqual(
    keys.map((key) => key.kind),
    ['PROVIDER_ORG', 'DOMAIN', 'PHONE', 'NAME_CITY', 'SOCIAL'],
  );
});

test('a missing value never matches another missing value', () => {
  // The property the whole dedup rests on: two companies that both lack a
  // website must not collide on an empty domain key.
  const first = buildMatchKeys({ name: 'Barbearia A', city: 'Maputo' }, MZ);
  const second = buildMatchKeys({ name: 'Barbearia B', city: 'Maputo' }, MZ);

  assert.equal(first.some((key) => key.kind === 'DOMAIN'), false);
  assert.equal(second.some((key) => key.kind === 'DOMAIN'), false);
  assert.equal(
    first.some((a) => second.some((b) => a.kind === b.kind && a.value === b.value)),
    false,
  );
});

test('two spellings of the same business share at least one key', () => {
  // This is the pair in the fixture set: fx-org-001 and fx-org-020.
  const first = buildMatchKeys(
    {
      name: 'Barbearia Exemplo Central',
      city: 'Maputo',
      domain: 'barbearia-exemplo.test',
      phone: '+258840000101',
    },
    MZ,
  );
  const second = buildMatchKeys(
    {
      name: 'Barbearia Exemplo Central',
      city: 'maputo',
      website: 'http://www.Barbearia-Exemplo.test/contactos?utm_source=ig',
      phone: '+258 84 000 0101',
    },
    MZ,
  );

  const shared = first.filter((a) =>
    second.some((b) => a.kind === b.kind && a.value === b.value),
  );
  assert.ok(shared.length >= 3, `expected several shared keys, got ${shared.length}`);
  assert.ok(shared.some((key) => key.kind === 'DOMAIN'));
  assert.ok(shared.some((key) => key.kind === 'PHONE'));
  assert.ok(shared.some((key) => key.kind === 'NAME_CITY'));
});

test('a name without a city produces no name key', () => {
  const keys = buildMatchKeys({ name: 'Barbearia X' }, MZ);
  assert.equal(keys.some((key) => key.kind === 'NAME_CITY'), false);
});

test('a provider id is namespaced by its provider', () => {
  const apollo = buildMatchKeys({ provider: 'apollo', providerOrgId: '1' }, MZ);
  const other = buildMatchKeys({ provider: 'aisa', providerOrgId: '1' }, MZ);
  assert.notEqual(apollo[0].value, other[0].value);
});

test('the same key repeated twice is stored once', () => {
  // A business whose WhatsApp is its phone number.
  const keys = buildMatchKeys(
    { phone: '+258841234567', whatsapp: '084 123 4567' },
    MZ,
  );
  assert.equal(keys.filter((key) => key.kind === 'PHONE').length, 1);
});

test('a document id is stable, and different for different values', () => {
  const a = matchKeyDocId({ kind: 'DOMAIN', value: 'barbearia-x.co.mz' });
  const b = matchKeyDocId({ kind: 'DOMAIN', value: 'barbearia-x.co.mz' });
  const c = matchKeyDocId({ kind: 'DOMAIN', value: 'barbearia-y.co.mz' });

  assert.equal(a, b);
  assert.notEqual(a, c);
  // Must be a legal Firestore document id: no slashes, and short.
  assert.equal(a.includes('/'), false);
  assert.ok(a.length < 64);
});

test('the same value under two kinds gets two ids', () => {
  const domain = matchKeyDocId({ kind: 'DOMAIN', value: 'x.mz' });
  const social = matchKeyDocId({ kind: 'SOCIAL', value: 'x.mz' });
  assert.notEqual(domain, social);
});
