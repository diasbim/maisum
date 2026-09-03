"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const merchant_bootstrap_1 = require("./merchant_bootstrap");
const MERCHANT = 'm-1';
const NOW = Date.UTC(2026, 8, 15, 12, 0, 0); // 15 September 2026
function seed(status = 'TRIAL') {
    return (0, merchant_bootstrap_1.bootstrapDocuments)({
        merchantId: MERCHANT,
        subscriptionStatus: status,
        now: NOW,
    });
}
function only(collection) {
    return seed().filter((doc) => doc.collection === collection);
}
/* --------------------------------------------------- agreement with the app */
const APP = node_path_1.default.join(__dirname, '..', '..', 'lib', 'features', 'subscription', 'domain');
/**
 * These lists live in Dart and are copied here because Functions cannot import
 * them. Copies drift, so the copy is checked against the original rather than
 * trusted: a feature added to the app now fails this test instead of quietly
 * never being granted to a new business.
 */
(0, node_test_1.default)('the feature keys match the app, in the same order', () => {
    const source = (0, node_fs_1.readFileSync)(node_path_1.default.join(APP, 'feature_keys.dart'), 'utf8');
    const block = /static const List<String> all = \[([\s\S]*?)\];/.exec(source);
    strict_1.default.ok(block, 'feature_keys.dart no longer declares `all`');
    const names = block[1]
        .split(',')
        .map((entry) => entry.trim())
        .filter((entry) => entry !== '');
    const values = names.map((name) => {
        const declared = new RegExp(`static const String ${name} = '([a-z_]+)';`).exec(source);
        strict_1.default.ok(declared, `${name} has no string value in feature_keys.dart`);
        return declared[1];
    });
    strict_1.default.ok(values.length >= 9, `parsed only ${values.length} feature keys`);
    strict_1.default.deepEqual([...merchant_bootstrap_1.FEATURE_KEYS], values);
});
(0, node_test_1.default)('the free plan grants what the app says it grants', () => {
    const source = (0, node_fs_1.readFileSync)(node_path_1.default.join(APP, 'plan_catalog.dart'), 'utf8');
    // `\s*` rather than `\n`: the checkout has CRLF line endings on Windows.
    const block = /Plan\.free: PlanDefinition\(([\s\S]*?)\),\s*Plan\./.exec(source);
    strict_1.default.ok(block, 'plan_catalog.dart no longer defines Plan.free');
    const features = [...block[1].matchAll(/FeatureKeys\.(\w+)/g)].map((m) => m[1]);
    strict_1.default.equal(features.length, 1, 'the free plan gained or lost a feature');
    strict_1.default.equal(features[0], 'whatsappAutomation');
    const limit = /whatsappMonthlyLimit: (\d+)/.exec(block[1]);
    strict_1.default.ok(limit, 'the free plan has no WhatsApp limit');
    strict_1.default.equal(Number(limit[1]), merchant_bootstrap_1.FREE_PLAN.whatsappMonthlyLimit);
});
/* ------------------------------------------------------------ what is written */
(0, node_test_1.default)('a new business gets exactly one subscription state', () => {
    const rows = only('subscription_state');
    strict_1.default.equal(rows.length, 1);
    strict_1.default.equal(rows[0].id, MERCHANT);
    strict_1.default.equal(rows[0].data.plan_code, 'free');
    strict_1.default.equal(rows[0].data.status, 'TRIAL');
});
(0, node_test_1.default)('the status on the business document is carried through', () => {
    // A business created as ACTIVE must not be seeded as TRIAL: the app shows
    // this string, and the console reads it to decide who is paying.
    const rows = (0, merchant_bootstrap_1.bootstrapDocuments)({
        merchantId: MERCHANT,
        subscriptionStatus: 'ACTIVE',
        now: NOW,
    }).filter((doc) => doc.collection === 'subscription_state');
    strict_1.default.equal(rows[0].data.status, 'ACTIVE');
});
(0, node_test_1.default)('a blank status falls back rather than writing an empty one', () => {
    const rows = (0, merchant_bootstrap_1.bootstrapDocuments)({
        merchantId: MERCHANT,
        subscriptionStatus: '   ',
        now: NOW,
    }).filter((doc) => doc.collection === 'subscription_state');
    strict_1.default.equal(rows[0].data.status, 'TRIAL');
});
(0, node_test_1.default)('every feature key gets an entitlement and a flag', () => {
    strict_1.default.equal(only('entitlements').length, merchant_bootstrap_1.FEATURE_KEYS.length);
    strict_1.default.equal(only('feature_flags').length, merchant_bootstrap_1.FEATURE_KEYS.length);
});
(0, node_test_1.default)('the free plan enables one feature and no more', () => {
    const enabled = only('entitlements')
        .filter((doc) => doc.data.is_enabled === true)
        .map((doc) => doc.data.feature_key);
    strict_1.default.deepEqual(enabled, ['whatsapp_automation']);
});
(0, node_test_1.default)('a flag is on even where the plan does not grant the feature', () => {
    // The two answer different questions: the entitlement says whether the plan
    // includes it, the flag says whether it has been withdrawn from this
    // business. A new business has nothing withdrawn.
    const off = only('feature_flags').filter((doc) => doc.data.is_enabled !== true);
    strict_1.default.deepEqual(off, []);
});
(0, node_test_1.default)('document ids match what the app used to write', () => {
    // A business seeded by the old client path and one seeded here have to be
    // the same business; nothing downstream should be able to tell them apart.
    const entitlement = only('entitlements')[0];
    strict_1.default.equal(entitlement.id, `${MERCHANT}_whatsapp_automation`);
    strict_1.default.equal(entitlement.data.id, entitlement.id);
    const config = only('remote_config')[0];
    strict_1.default.equal(config.id, `${MERCHANT}_billing_whatsapp_price`);
});
(0, node_test_1.default)('the WhatsApp quota covers the current calendar month', () => {
    const quota = only('usage_balances')[0];
    const window = (0, merchant_bootstrap_1.monthlyWindow)(new Date(NOW));
    strict_1.default.equal(quota.data.metric_key, merchant_bootstrap_1.WHATSAPP_MESSAGES_METRIC);
    strict_1.default.equal(quota.data.window_start, window.start);
    strict_1.default.equal(quota.data.window_end, window.end);
    strict_1.default.equal(quota.data.used, 0);
    strict_1.default.equal(quota.data.limit_value, merchant_bootstrap_1.FREE_PLAN.whatsappMonthlyLimit);
    strict_1.default.equal(quota.id, `${MERCHANT}_${merchant_bootstrap_1.WHATSAPP_MESSAGES_METRIC}_${window.start}`);
});
(0, node_test_1.default)('the month window ends a millisecond before the next one begins', () => {
    const september = (0, merchant_bootstrap_1.monthlyWindow)(new Date(2026, 8, 15));
    const october = (0, merchant_bootstrap_1.monthlyWindow)(new Date(2026, 9, 1));
    strict_1.default.equal(september.end + 1, october.start);
});
(0, node_test_1.default)('December rolls into January rather than into month thirteen', () => {
    const december = (0, merchant_bootstrap_1.monthlyWindow)(new Date(2026, 11, 20));
    const january = (0, merchant_bootstrap_1.monthlyWindow)(new Date(2027, 0, 5));
    strict_1.default.equal(december.end + 1, january.start);
});
(0, node_test_1.default)('every seeded document carries the business it belongs to', () => {
    for (const doc of seed()) {
        strict_1.default.equal(doc.data.merchant_id, MERCHANT, `${doc.collection}/${doc.id} has no merchant_id`);
        strict_1.default.equal(doc.data.updated_at, NOW);
    }
});
(0, node_test_1.default)('only server-owned collections are seeded', () => {
    // Nothing here may touch a collection the client is allowed to write, or the
    // trigger would be overwriting the till's own work.
    const collections = new Set(seed().map((doc) => doc.collection));
    strict_1.default.deepEqual([...collections].sort(), [
        'entitlements',
        'feature_flags',
        'remote_config',
        'subscription_state',
        'usage_balances',
    ]);
});
