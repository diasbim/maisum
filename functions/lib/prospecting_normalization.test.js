"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_normalization_js_1 = require("./prospecting_normalization.js");
const MZ = '+258';
/* ----------------------------------------------------------------- domain */
(0, node_test_1.default)('the example from the plan folds to one domain', () => {
    // The two spellings §6 names, which must not produce two companies.
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('https://Barbearia-X.co.mz/'), 'barbearia-x.co.mz');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('http://www.barbearia-x.co.mz'), 'barbearia-x.co.mz');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('https://Barbearia-X.co.mz/'), (0, prospecting_normalization_js_1.normalizeDomain)('http://www.barbearia-x.co.mz'));
});
(0, node_test_1.default)('a query string, a path, a port and a trailing dot all fall away', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('https://barbearia-x.co.mz:443/contactos?utm_source=ig#topo'), 'barbearia-x.co.mz');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('barbearia-x.co.mz.'), 'barbearia-x.co.mz');
});
(0, node_test_1.default)('a bare domain needs no scheme', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('barbearia-x.co.mz'), 'barbearia-x.co.mz');
});
(0, node_test_1.default)('anything that is not a host is null, never an empty string', () => {
    // An empty string would collide every website-less company onto one key,
    // which is the one failure that merges unrelated businesses.
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)(''), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('   '), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('localhost'), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)('not a domain'), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)(null), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeDomain)(42), null);
});
/* ------------------------------------------------------------------ phone */
(0, node_test_1.default)('a Mozambican mobile normalises to E.164 however it was written', () => {
    const expected = '+258841234567';
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('+258841234567', MZ), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('+258 84 123 4567', MZ), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('(+258) 84-123-4567', MZ), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('00258841234567', MZ), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('084 123 4567', MZ), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('841234567', MZ), expected);
});
(0, node_test_1.default)('a business landline is accepted, unlike the customer normaliser', () => {
    // +258 21 is a Maputo landline. The customer-core normaliser rejects it
    // because a customer has a mobile; a salon's published number is often this.
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('+258 21 300 400', MZ), '+25821300400');
});
(0, node_test_1.default)('a number that already carries another country code keeps it', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('+351 912 345 678', MZ), '+351912345678');
});
(0, node_test_1.default)('the country code is configuration, not an assumption', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('912345678', '+351'), '+351912345678');
});
(0, node_test_1.default)('something that is not a phone number is null', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('', MZ), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('abc', MZ), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('123', MZ), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)('1234567890123456789', MZ), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizePhone)(null, MZ), null);
});
/* ------------------------------------------------------------------- name */
(0, node_test_1.default)('accents, punctuation and case all fold away', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Salão Beleza'), 'salao beleza');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('SALAO  BELEZA!'), 'salao beleza');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Salão, Beleza.'), 'salao beleza');
});
(0, node_test_1.default)('legal suffixes are stripped, including more than one', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Barbearia X, Lda'), 'barbearia x');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Barbearia X SA'), 'barbearia x');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Barbearia X EI'), 'barbearia x');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Barbearia X Lda Unipessoal'), 'barbearia x');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Barbearia X Limitada'), 'barbearia x');
});
(0, node_test_1.default)('an ampersand is a word, not punctuation', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Silva & Filhos'), 'silva e filhos');
});
(0, node_test_1.default)('a name that is only a legal form folds to nothing rather than to the suffix', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('Lda'), '');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)('  '), '');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCompanyName)(null), '');
});
(0, node_test_1.default)('a city folds the same way', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCity)('Maputo'), 'maputo');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCity)(' MATOLA '), 'matola');
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeCity)('Maputo Cidade'), 'maputo cidade');
});
/* ----------------------------------------------------------------- social */
(0, node_test_1.default)('the four ways of writing one Instagram profile fold to one key', () => {
    const expected = 'instagram.com/barbearia_x';
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('https://instagram.com/barbearia_x'), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('https://www.instagram.com/barbearia_x/'), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('https://instagram.com/barbearia_x?igshid=abc'), expected);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('instagram.com/barbearia_x'), expected);
});
(0, node_test_1.default)('a LinkedIn company page keeps the segment that identifies the company', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('https://linkedin.com/company/barbearia-x'), 'linkedin.com/company/barbearia-x');
});
(0, node_test_1.default)('a link to the network rather than to anyone on it is null', () => {
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('https://instagram.com'), null);
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeSocialUrl)('https://instagram.com/'), null);
});
/* -------------------------------------------------------------- match keys */
(0, node_test_1.default)('the keys come back strongest first', () => {
    const keys = (0, prospecting_normalization_js_1.buildMatchKeys)({
        provider: 'apollo',
        providerOrgId: 'org_1',
        website: 'https://barbearia-x.co.mz',
        phone: '+258841234567',
        name: 'Barbearia X, Lda',
        city: 'Maputo',
        instagramUrl: 'https://instagram.com/barbearia_x',
    }, MZ);
    strict_1.default.deepEqual(keys.map((key) => key.kind), ['PROVIDER_ORG', 'DOMAIN', 'PHONE', 'NAME_CITY', 'SOCIAL']);
});
(0, node_test_1.default)('a missing value never matches another missing value', () => {
    // The property the whole dedup rests on: two companies that both lack a
    // website must not collide on an empty domain key.
    const first = (0, prospecting_normalization_js_1.buildMatchKeys)({ name: 'Barbearia A', city: 'Maputo' }, MZ);
    const second = (0, prospecting_normalization_js_1.buildMatchKeys)({ name: 'Barbearia B', city: 'Maputo' }, MZ);
    strict_1.default.equal(first.some((key) => key.kind === 'DOMAIN'), false);
    strict_1.default.equal(second.some((key) => key.kind === 'DOMAIN'), false);
    strict_1.default.equal(first.some((a) => second.some((b) => a.kind === b.kind && a.value === b.value)), false);
});
(0, node_test_1.default)('two spellings of the same business share at least one key', () => {
    // This is the pair in the fixture set: fx-org-001 and fx-org-020.
    const first = (0, prospecting_normalization_js_1.buildMatchKeys)({
        name: 'Barbearia Exemplo Central',
        city: 'Maputo',
        domain: 'barbearia-exemplo.test',
        phone: '+258840000101',
    }, MZ);
    const second = (0, prospecting_normalization_js_1.buildMatchKeys)({
        name: 'Barbearia Exemplo Central',
        city: 'maputo',
        website: 'http://www.Barbearia-Exemplo.test/contactos?utm_source=ig',
        phone: '+258 84 000 0101',
    }, MZ);
    const shared = first.filter((a) => second.some((b) => a.kind === b.kind && a.value === b.value));
    strict_1.default.ok(shared.length >= 3, `expected several shared keys, got ${shared.length}`);
    strict_1.default.ok(shared.some((key) => key.kind === 'DOMAIN'));
    strict_1.default.ok(shared.some((key) => key.kind === 'PHONE'));
    strict_1.default.ok(shared.some((key) => key.kind === 'NAME_CITY'));
});
(0, node_test_1.default)('a name without a city produces no name key', () => {
    const keys = (0, prospecting_normalization_js_1.buildMatchKeys)({ name: 'Barbearia X' }, MZ);
    strict_1.default.equal(keys.some((key) => key.kind === 'NAME_CITY'), false);
});
(0, node_test_1.default)('a provider id is namespaced by its provider', () => {
    const apollo = (0, prospecting_normalization_js_1.buildMatchKeys)({ provider: 'apollo', providerOrgId: '1' }, MZ);
    const other = (0, prospecting_normalization_js_1.buildMatchKeys)({ provider: 'aisa', providerOrgId: '1' }, MZ);
    strict_1.default.notEqual(apollo[0].value, other[0].value);
});
(0, node_test_1.default)('the same key repeated twice is stored once', () => {
    // A business whose WhatsApp is its phone number.
    const keys = (0, prospecting_normalization_js_1.buildMatchKeys)({ phone: '+258841234567', whatsapp: '084 123 4567' }, MZ);
    strict_1.default.equal(keys.filter((key) => key.kind === 'PHONE').length, 1);
});
(0, node_test_1.default)('a document id is stable, and different for different values', () => {
    const a = (0, prospecting_normalization_js_1.matchKeyDocId)({ kind: 'DOMAIN', value: 'barbearia-x.co.mz' });
    const b = (0, prospecting_normalization_js_1.matchKeyDocId)({ kind: 'DOMAIN', value: 'barbearia-x.co.mz' });
    const c = (0, prospecting_normalization_js_1.matchKeyDocId)({ kind: 'DOMAIN', value: 'barbearia-y.co.mz' });
    strict_1.default.equal(a, b);
    strict_1.default.notEqual(a, c);
    // Must be a legal Firestore document id: no slashes, and short.
    strict_1.default.equal(a.includes('/'), false);
    strict_1.default.ok(a.length < 64);
});
(0, node_test_1.default)('the same value under two kinds gets two ids', () => {
    const domain = (0, prospecting_normalization_js_1.matchKeyDocId)({ kind: 'DOMAIN', value: 'x.mz' });
    const social = (0, prospecting_normalization_js_1.matchKeyDocId)({ kind: 'SOCIAL', value: 'x.mz' });
    strict_1.default.notEqual(domain, social);
});
