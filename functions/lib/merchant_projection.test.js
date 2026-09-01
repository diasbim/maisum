"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const merchant_projection_js_1 = require("./merchant_projection.js");
const NOW = 1780000000000;
(0, node_test_1.default)('projects a complete business onto the merchants row', () => {
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-1', {
        id: 'm-1',
        merchant_name: '  Cafe Central  ',
        phone: ' +258840000000 ',
        city: 'Maputo',
        created_at: 1770000000000,
        updated_at: 1775000000000,
    }, NOW);
    strict_1.default.equal(result.status, 'ready');
    if (result.status !== 'ready')
        return;
    strict_1.default.deepEqual(result.row, {
        id: 'm-1',
        name: 'Cafe Central',
        phone: '+258840000000',
        created_at: 1770000000000,
        updated_at: 1775000000000,
    });
});
(0, node_test_1.default)('reads the name from merchant_name, which is not what the column is called', () => {
    // The single most likely way to get this wrong: Firestore writes
    // `merchant_name`, the column is `name`. A straight copy yields NULL and the
    // NOT NULL constraint rejects the row.
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-2', { merchant_name: 'Salao Bela', phone: '+258841111111' }, NOW);
    strict_1.default.equal(result.status, 'ready');
    if (result.status !== 'ready')
        return;
    strict_1.default.equal(result.row.name, 'Salao Bela');
});
(0, node_test_1.default)('falls back to name for documents written before merchant_name settled', () => {
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-3', { name: 'Antigo', phone: '+258842222222' }, NOW);
    strict_1.default.equal(result.status, 'ready');
    if (result.status !== 'ready')
        return;
    strict_1.default.equal(result.row.name, 'Antigo');
});
(0, node_test_1.default)('refuses a business with no name instead of inventing one', () => {
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-4', { phone: '+258843333333' }, NOW);
    strict_1.default.equal(result.status, 'skipped');
    if (result.status !== 'skipped')
        return;
    strict_1.default.equal(result.reason, 'missing_name');
});
(0, node_test_1.default)('refuses a business with no phone rather than substituting a placeholder', () => {
    // merchants.phone is NOT NULL UNIQUE. Any placeholder would be claimed by
    // the first incomplete business and collide with every one after it.
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-5', { merchant_name: 'Sem telefone' }, NOW);
    strict_1.default.equal(result.status, 'skipped');
    if (result.status !== 'skipped')
        return;
    strict_1.default.equal(result.reason, 'missing_phone');
});
(0, node_test_1.default)('treats a blank string as absent, not as a value', () => {
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-6', { merchant_name: '   ', phone: '+258844444444' }, NOW);
    strict_1.default.equal(result.status, 'skipped');
    if (result.status !== 'skipped')
        return;
    strict_1.default.equal(result.reason, 'missing_name');
});
(0, node_test_1.default)('rejects a document with no merchant id', () => {
    for (const id of ['', '   ', null, undefined, 42]) {
        const result = (0, merchant_projection_js_1.projectBusinessToMerchant)(id, { merchant_name: 'X', phone: '+1' }, NOW);
        strict_1.default.equal(result.status, 'skipped', `id ${JSON.stringify(id)}`);
        if (result.status !== 'skipped')
            continue;
        strict_1.default.equal(result.reason, 'missing_merchant_id');
    }
});
(0, node_test_1.default)('supplies timestamps only when the document has none', () => {
    const missing = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-7', { merchant_name: 'Novo', phone: '+258845555555' }, NOW);
    strict_1.default.equal(missing.status, 'ready');
    if (missing.status !== 'ready')
        return;
    strict_1.default.equal(missing.row.created_at, NOW);
    // The merchant list orders by updated_at, so a row without one still needs a
    // sortable value rather than a null.
    strict_1.default.equal(missing.row.updated_at, NOW);
    const createdOnly = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-8', { merchant_name: 'Novo', phone: '+258846666666', created_at: 1771000000000 }, NOW);
    strict_1.default.equal(createdOnly.status, 'ready');
    if (createdOnly.status !== 'ready')
        return;
    strict_1.default.equal(createdOnly.row.updated_at, 1771000000000);
});
(0, node_test_1.default)('accepts a timestamp that arrived as a string', () => {
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-9', { merchant_name: 'X', phone: '+258847777777', created_at: '1770000000000' }, NOW);
    strict_1.default.equal(result.status, 'ready');
    if (result.status !== 'ready')
        return;
    strict_1.default.equal(result.row.created_at, 1770000000000);
});
(0, node_test_1.default)('tolerates a missing document body', () => {
    const result = (0, merchant_projection_js_1.projectBusinessToMerchant)('m-10', null, NOW);
    strict_1.default.equal(result.status, 'skipped');
});
(0, node_test_1.default)('every skip reason has an explanation for the backfill report', () => {
    const reasons = ['missing_merchant_id', 'missing_name', 'missing_phone'];
    for (const reason of reasons) {
        strict_1.default.equal(typeof merchant_projection_js_1.SKIP_EXPLANATIONS[reason], 'string');
        strict_1.default.ok(merchant_projection_js_1.SKIP_EXPLANATIONS[reason].length > 0);
    }
});
