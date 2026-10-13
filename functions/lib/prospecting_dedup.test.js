"use strict";
/**
 * Deduplication, tested against the run that paid for it.
 *
 * The fixture lives in `prospecting_dedup_fixture.ts`: a real search that cost
 * $0.17, of which $0.06 bought the same phone number three times. These tests
 * assert that the same twenty listings now cost less and reach more
 * businesses.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const prospecting_dedup_js_1 = require("./prospecting_dedup.js");
const prospecting_normalization_js_1 = require("./prospecting_normalization.js");
const prospecting_dedup_fixture_js_1 = require("./prospecting_dedup_fixture.js");
const CURLY = String.fromCharCode(0x2019);
/**
 * A point a given distance due east. Rough, and rough is enough: every
 * assertion is well inside or well outside the radius, never on it.
 */
const at = (point, metresEast) => ({
    latitude: point.latitude,
    longitude: point.longitude + metresEast / (111320 * Math.cos((point.latitude * Math.PI) / 180)),
});
const GENTLEMANS = {
    latitude: prospecting_dedup_fixture_js_1.MAPUTO_RUN[0].latitude,
    longitude: prospecting_dedup_fixture_js_1.MAPUTO_RUN[0].longitude,
};
/* ------------------------------------------------------------ the folding */
(0, node_test_1.default)('the three apostrophes are one business', () => {
    const names = prospecting_dedup_fixture_js_1.MAPUTO_RUN.slice(0, 3).map((row) => (0, prospecting_dedup_js_1.matchName)(row.name));
    strict_1.default.equal(new Set(names).size, 1, 'as três variantes deviam dobrar no mesmo texto');
});
(0, node_test_1.default)('the trade word does not distinguish a business', () => {
    // "Barber Shop" and "Barbershop" are the same word written two ways, and
    // the run contained both spellings.
    strict_1.default.equal((0, prospecting_dedup_js_1.matchName)('Tsemeta Barbershop'), (0, prospecting_dedup_js_1.matchName)('Tsemeta Barber Shop'));
});
(0, node_test_1.default)('a name that is nothing but trade words keeps a key of its own', () => {
    // Otherwise every generically named shop in the city merges into one lead
    // and the operator never learns the others existed.
    strict_1.default.equal((0, prospecting_normalization_js_1.normalizeMatchName)('Barber Shop'), '');
    strict_1.default.notEqual((0, prospecting_dedup_js_1.matchName)('Barber Shop'), '');
    strict_1.default.notEqual((0, prospecting_dedup_js_1.matchName)('Barber Shop'), (0, prospecting_dedup_js_1.matchName)('Hair Studio'));
});
(0, node_test_1.default)('the stored name is untouched — folding is for comparing', () => {
    const original = 'Gentleman' + CURLY + 's Barber Shop';
    (0, prospecting_dedup_js_1.matchName)(original);
    strict_1.default.equal(original, 'Gentleman' + CURLY + 's Barber Shop');
});
/* ----------------------------------------------------------- the distance */
(0, node_test_1.default)('distance is metres, and the radius separates a doorway from a district', () => {
    strict_1.default.ok((0, prospecting_dedup_js_1.distanceMetres)(GENTLEMANS, at(GENTLEMANS, 12)) < prospecting_dedup_js_1.DEFAULT_DEDUP_RADIUS_METRES);
    strict_1.default.ok((0, prospecting_dedup_js_1.distanceMetres)(GENTLEMANS, at(GENTLEMANS, 900)) > prospecting_dedup_js_1.DEFAULT_DEDUP_RADIUS_METRES);
});
/* -------------------------------------------------------------- the dedup */
(0, node_test_1.default)('the run collapses from twenty listings to eighteen businesses', () => {
    const { kept, duplicates } = (0, prospecting_dedup_js_1.dedupeCandidates)(prospecting_dedup_fixture_js_1.MAPUTO_RUN);
    strict_1.default.equal(kept.length, 18);
    strict_1.default.equal(duplicates.length, 2);
});
(0, node_test_1.default)('the surviving Gentleman is the best-evidenced one, not the first', () => {
    const { kept, duplicates } = (0, prospecting_dedup_js_1.dedupeCandidates)(prospecting_dedup_fixture_js_1.MAPUTO_RUN);
    const gentlemanKey = (0, prospecting_dedup_js_1.matchName)(prospecting_dedup_fixture_js_1.MAPUTO_RUN[0].name);
    const gentlemen = kept.filter((row) => (0, prospecting_dedup_js_1.matchName)(row.name) === gentlemanKey);
    strict_1.default.equal(gentlemen.length, 1);
    strict_1.default.equal(gentlemen[0].reviewCount, 56);
    // Every discarded copy names the one it was merged into, so the report can
    // show the operator the arithmetic rather than a shorter list.
    for (const duplicate of duplicates) {
        strict_1.default.equal((0, prospecting_dedup_js_1.matchName)(duplicate.duplicateOf.name), (0, prospecting_dedup_js_1.matchName)(duplicate.candidate.name));
        strict_1.default.equal(duplicate.reason, 'SAME_NAME_NEARBY');
    }
});
(0, node_test_1.default)('an identical source reference is decisive on its own', () => {
    const twice = [prospecting_dedup_fixture_js_1.MAPUTO_RUN[5], { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[5], name: 'Outro Nome Completamente' }];
    const { kept, duplicates } = (0, prospecting_dedup_js_1.dedupeCandidates)(twice);
    strict_1.default.equal(kept.length, 1);
    strict_1.default.equal(duplicates[0].reason, 'SAME_SOURCE_REFERENCE');
});
(0, node_test_1.default)('the same name far apart is two businesses, not one', () => {
    const far = [
        { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[0], sourceReference: 'a' },
        { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[0], sourceReference: 'b', ...at(GENTLEMANS, 4000) },
    ];
    strict_1.default.equal((0, prospecting_dedup_js_1.dedupeCandidates)(far).kept.length, 2);
});
(0, node_test_1.default)('without coordinates the match is weaker, and says so', () => {
    const blind = [
        { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[0], latitude: null, longitude: null },
        { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[2], latitude: null, longitude: null },
    ];
    const { kept, duplicates } = (0, prospecting_dedup_js_1.dedupeCandidates)(blind);
    strict_1.default.equal(kept.length, 1);
    strict_1.default.equal(duplicates[0].reason, 'SAME_NAME_NO_LOCATION');
});
(0, node_test_1.default)('a null review count loses to a stated one', () => {
    // Null means the source said nothing, not that the shop has no reviews —
    // so the listing that carries evidence is the one worth keeping.
    const pair = [
        { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[0], sourceReference: 'a', reviewCount: null },
        { ...prospecting_dedup_fixture_js_1.MAPUTO_RUN[0], sourceReference: 'b', reviewCount: 4 },
    ];
    strict_1.default.equal((0, prospecting_dedup_js_1.dedupeCandidates)(pair).kept[0].reviewCount, 4);
});
/* ------------------------------------------------- the pass after payment */
(0, node_test_1.default)('a repeated phone is caught even when the names differ', () => {
    const seen = new prospecting_dedup_js_1.SeenContacts();
    strict_1.default.equal(seen.observe({ phone: '+258845509796', domain: null }).duplicate, false);
    const second = seen.observe({ phone: '+258845509796', domain: 'outro.co.mz' });
    strict_1.default.equal(second.duplicate, true);
    strict_1.default.equal(second.by, 'phone');
});
(0, node_test_1.default)('a repeated domain is caught too', () => {
    const seen = new prospecting_dedup_js_1.SeenContacts();
    seen.observe({ phone: '+258840000001', domain: 'gentlemans.co.mz' });
    const second = seen.observe({ phone: '+258840000002', domain: 'gentlemans.co.mz' });
    strict_1.default.equal(second.duplicate, true);
    strict_1.default.equal(second.by, 'domain');
});
(0, node_test_1.default)('a third copy is caught, because a second sighting is still recorded', () => {
    const seen = new prospecting_dedup_js_1.SeenContacts();
    seen.observe({ phone: '+258845509796', domain: null });
    seen.observe({ phone: '+258845509796', domain: null });
    strict_1.default.equal(seen.observe({ phone: '+258845509796', domain: null }).duplicate, true);
});
(0, node_test_1.default)('two businesses that share nothing are not duplicates', () => {
    const seen = new prospecting_dedup_js_1.SeenContacts();
    seen.observe({ phone: '+258845509796', domain: 'gentlemans.co.mz' });
    strict_1.default.equal(seen.observe({ phone: '+258878187409', domain: 'tsemeta.co.mz' }).duplicate, false);
});
(0, node_test_1.default)('nothing known is never a duplicate of nothing known', () => {
    // Two listings with neither phone nor site have not been shown to be the
    // same business; treating them as one would discard a real lead.
    const seen = new prospecting_dedup_js_1.SeenContacts();
    seen.observe({ phone: null, domain: null });
    strict_1.default.equal(seen.observe({ phone: null, domain: null }).duplicate, false);
});
