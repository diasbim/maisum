"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const prospecting_detail_cache_js_1 = require("./prospecting_detail_cache.js");
const DAY_MS = 24 * 60 * 60 * 1000;
/** A clock the test moves, so a month can pass in a microsecond. */
function clock(start = 1700000000000) {
    let at = start;
    return { now: () => at, advanceDays: (days) => (at += days * DAY_MS) };
}
(0, node_test_1.default)('a cache hit means the paid call is never made', () => {
    const cache = new prospecting_detail_cache_js_1.DetailCache();
    let calls = 0;
    const fetchDetail = (placeId) => {
        const cached = cache.get(placeId);
        if (cached !== null)
            return cached;
        calls++;
        const detail = { phone: '+258845509796' };
        cache.put(placeId, detail, '+258845509796');
        return detail;
    };
    fetchDetail('p-gentleman');
    fetchDetail('p-gentleman');
    fetchDetail('p-gentleman');
    strict_1.default.equal(calls, 1, 'três pedidos, uma só chamada paga');
    strict_1.default.equal(cache.hits, 2);
});
(0, node_test_1.default)('a miss on an unknown place is not an error', () => {
    strict_1.default.equal(new prospecting_detail_cache_js_1.DetailCache().get('nunca-visto'), null);
});
(0, node_test_1.default)('a null place id is never a hit', () => {
    // A provider that returned no reference gives nothing to key on, and
    // treating that as "one unnamed entry" would serve one shop's phone number
    // for another's.
    const cache = new prospecting_detail_cache_js_1.DetailCache();
    cache.put(null, { phone: '+258840000000' }, '+258840000000');
    strict_1.default.equal(cache.get(null), null);
});
(0, node_test_1.default)('an entry older than the TTL is not served', () => {
    const time = clock();
    const cache = new prospecting_detail_cache_js_1.DetailCache(prospecting_detail_cache_js_1.EMPTY_CACHE, { now: time.now });
    cache.put('p-kubila', { phone: '+258845242789' }, '+258845242789');
    time.advanceDays(prospecting_detail_cache_js_1.DEFAULT_CACHE_TTL_DAYS - 1);
    strict_1.default.notEqual(cache.get('p-kubila'), null, 'dentro do prazo, ainda serve');
    time.advanceDays(2);
    strict_1.default.equal(cache.get('p-kubila'), null, 'passado o prazo, paga-se de novo');
});
(0, node_test_1.default)('the TTL is configurable', () => {
    const time = clock();
    const cache = new prospecting_detail_cache_js_1.DetailCache(prospecting_detail_cache_js_1.EMPTY_CACHE, { ttlDays: 1, now: time.now });
    cache.put('p-tsemeta', { phone: '+258878187409' }, '+258878187409');
    time.advanceDays(2);
    strict_1.default.equal(cache.get('p-tsemeta'), null);
});
(0, node_test_1.default)('an expired entry does not count as a hit', () => {
    const time = clock();
    const cache = new prospecting_detail_cache_js_1.DetailCache(prospecting_detail_cache_js_1.EMPTY_CACHE, { ttlDays: 1, now: time.now });
    cache.put('p-x', { phone: null }, null);
    time.advanceDays(2);
    cache.get('p-x');
    strict_1.default.equal(cache.hits, 0, 'uma entrada expirada não poupou chamada nenhuma');
});
(0, node_test_1.default)('a phone leads back to the place it belongs to', () => {
    // So a chain listing every branch under one central number is recognised
    // before the second branch is paid for.
    const cache = new prospecting_detail_cache_js_1.DetailCache();
    cache.put('p-gentleman', { phone: '+258845509796' }, '+258845509796');
    strict_1.default.equal(cache.placeForPhone('+258845509796'), 'p-gentleman');
    strict_1.default.equal(cache.placeForPhone('+258870000000'), null);
    strict_1.default.equal(cache.placeForPhone(null), null);
});
(0, node_test_1.default)('a detail with no phone is still cached', () => {
    const cache = new prospecting_detail_cache_js_1.DetailCache();
    cache.put('p-sem-telefone', { phone: null }, null);
    strict_1.default.notEqual(cache.get('p-sem-telefone'), null);
});
(0, node_test_1.default)('what survives a restart is what was cached', () => {
    const first = new prospecting_detail_cache_js_1.DetailCache();
    first.put('p-kubila', { phone: '+258845242789' }, '+258845242789');
    const second = new prospecting_detail_cache_js_1.DetailCache(first.snapshot());
    strict_1.default.notEqual(second.get('p-kubila'), null);
    strict_1.default.equal(second.placeForPhone('+258845242789'), 'p-kubila');
});
(0, node_test_1.default)('holding the snapshot does not let a caller mutate the cache', () => {
    const cache = new prospecting_detail_cache_js_1.DetailCache();
    cache.put('p-a', { phone: null }, null);
    const taken = cache.snapshot();
    delete taken.byPlaceId['p-a'];
    strict_1.default.notEqual(cache.get('p-a'), null);
});
