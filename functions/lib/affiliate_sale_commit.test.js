"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_engine_js_1 = require("./affiliate_engine.js");
const affiliate_sale_commit_js_1 = require("./affiliate_sale_commit.js");
/**
 * The referred sale, checked without an emulator.
 *
 * The commit is one transaction with seven writes in it, and the property that
 * matters — all of them or none — is not something a unit test of any single
 * step can see. So the transaction is a port, and this file implements a fake
 * one that behaves the way Firestore does in the two ways that bite: it
 * refuses a read issued after a write, and it refuses a `create` on a document
 * that already exists. A commit path that would be rejected in production
 * fails here instead.
 *
 * The fake can also be told to fail partway through. That is the test for
 * atomicity: the plan is staged, the failure lands, and the store is checked
 * to be exactly as it was.
 */
const NOW = 1800000000000;
const MERCHANT = 'm1';
const CODE = 'AFI-ANA-7K2P';
const CUSTOMER = 'c1';
const PHONE = '+258841234567';
function gatewayOver(docs, options = {}) {
    const applied = [];
    const gateway = {
        async runTransaction(run) {
            const staged = [];
            let hasWritten = false;
            const stage = (operation) => {
                hasWritten = true;
                if (options.failAfterWrites !== undefined &&
                    staged.length >= options.failAfterWrites) {
                    throw new Error('injected transaction failure');
                }
                staged.push(operation);
            };
            const transaction = {
                async getDoc(docPath) {
                    strict_1.default.ok(!hasWritten, `read after write: ${docPath}`);
                    const data = docs.get(docPath);
                    return data === undefined ? null : { ...data };
                },
                async queryDocs(collectionPath, field, value, limit) {
                    strict_1.default.ok(!hasWritten, `query after write: ${collectionPath}`);
                    const rows = [];
                    for (const [docPath, data] of docs) {
                        if (!docPath.startsWith(`${collectionPath}/`))
                            continue;
                        const id = docPath.slice(collectionPath.length + 1);
                        if (id.includes('/'))
                            continue;
                        if (data[field] !== value)
                            continue;
                        rows.push({ id, data: { ...data } });
                        if (rows.length >= limit)
                            break;
                    }
                    return rows;
                },
                create: (docPath, data) => stage({ kind: 'create', path: docPath, data }),
                merge: (docPath, data) => stage({ kind: 'merge', path: docPath, data }),
            };
            const result = await run(transaction);
            for (const operation of staged) {
                if (operation.kind === 'create') {
                    strict_1.default.ok(!docs.has(operation.path), `create on an existing document: ${operation.path}`);
                    docs.set(operation.path, { ...operation.data });
                }
                else {
                    docs.set(operation.path, {
                        ...(docs.get(operation.path) ?? {}),
                        ...operation.data,
                    });
                }
                applied.push(operation);
            }
            return result;
        },
    };
    return { gateway, applied };
}
/* --------------------------------------------------------------- fixtures */
const LINK_ID = affiliate_engine_js_1.affiliateIds.link('af1', MERCHANT);
const ATTRIBUTION_ID = affiliate_engine_js_1.affiliateIds.attribution(MERCHANT, CUSTOMER);
const SALE_ID = affiliate_engine_js_1.affiliateIds.sale('d1', 'l1');
const FIRST_REWARD_ID = affiliate_engine_js_1.affiliateIds.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE');
const RETURN_REWARD_ID = affiliate_engine_js_1.affiliateIds.reward(ATTRIBUTION_ID, 'CUSTOMER_RETURN');
function config(overrides = {}) {
    return {
        ...affiliate_contracts_js_1.DEFAULT_AFFILIATE_CONFIG,
        enabled: true,
        firstSaleRewardPoints: 100,
        ...overrides,
    };
}
function storeWith(overrides = {}) {
    const docs = new Map();
    docs.set(affiliate_sale_commit_js_1.referralPaths.business(MERCHANT), {
        id: MERCHANT,
        loyalty_config: { points_per_mzn: 100, version: 2 },
    });
    docs.set(affiliate_sale_commit_js_1.referralPaths.codeLookup(CODE), {
        code: CODE,
        merchant_id: overrides.lookupMerchantId ?? MERCHANT,
        affiliate_id: 'af1',
        code_id: 'ac1',
    });
    docs.set(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'), {
        id: 'ac1',
        merchant_id: MERCHANT,
        affiliate_id: 'af1',
        status: 'ACTIVE',
        starts_at: NOW - 86400000,
        expires_at: NOW + 86400000,
        usage_limit: null,
        usage_count: 0,
        first_visit_only: true,
        benefit_type: 'FIXED_AMOUNT',
        benefit_value: 50,
        ...overrides.code,
    });
    docs.set(affiliate_sale_commit_js_1.referralPaths.affiliate('af1'), {
        id: 'af1',
        status: 'ACTIVE',
        phone_e164: '+258840000001',
        ...overrides.affiliate,
    });
    docs.set(affiliate_sale_commit_js_1.referralPaths.link(MERCHANT, LINK_ID), {
        id: LINK_ID,
        merchant_id: MERCHANT,
        affiliate_id: 'af1',
        status: 'ACTIVE',
        ...overrides.link,
    });
    docs.set(affiliate_sale_commit_js_1.referralPaths.customer(MERCHANT, CUSTOMER), {
        id: CUSTOMER,
        merchant_id: MERCHANT,
        phone: PHONE,
        confirmed_points: 0,
        ...overrides.customer,
    });
    for (const [docPath, data] of Object.entries(overrides.extra ?? {})) {
        docs.set(docPath, data);
    }
    return docs;
}
function input(overrides = {}) {
    return {
        merchantId: MERCHANT,
        deviceId: 'd1',
        localSaleId: 'l1',
        customerId: CUSTOMER,
        customerPhoneE164: PHONE,
        grossAmount: 500,
        rawCode: 'afi-ana-7k2p',
        items: [],
        appUserId: 'u1',
        now: NOW,
        ...overrides,
    };
}
async function commit(docs, overrides = {}, settings = config(), options = {}) {
    const { gateway } = gatewayOver(docs, options);
    return (0, affiliate_sale_commit_js_1.commitReferralSale)(gateway, input(overrides), () => settings);
}
/* ----------------------------------------------------------- happy paths */
(0, node_test_1.default)('a fixed discount is applied, attributed and rewarded in one transaction', async () => {
    const docs = storeWith();
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.ok(sale, 'the sale was not written');
    // The customer pays 450 and earns points on what they paid, not on the
    // pre-discount amount.
    strict_1.default.equal(sale.amount, 450);
    strict_1.default.equal(sale.gross_amount, 500);
    strict_1.default.equal(sale.points, 4);
    strict_1.default.equal(sale.referral_benefit_type, 'FIXED_AMOUNT');
    strict_1.default.equal(sale.referral_benefit_amount, 50);
    strict_1.default.equal(sale.affiliate_code_id, 'ac1');
    strict_1.default.equal(sale.referral_status, 'ATTRIBUTED');
    strict_1.default.equal(sale.cancellation_status, 'ACTIVE');
    strict_1.default.equal(sale.referral_idempotency_key, (0, affiliate_engine_js_1.saleIdempotencyKey)('d1', 'l1'));
    const attribution = docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
    strict_1.default.equal(attribution?.status, 'CONFIRMED');
    strict_1.default.equal(attribution?.first_sale_id, SALE_ID);
    const reward = docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID));
    strict_1.default.equal(reward?.status, 'PENDING');
    strict_1.default.equal(reward?.value, 100);
    strict_1.default.equal(reward?.trigger_sale_id, SALE_ID);
    // The code was spent exactly once.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    const attributedEvent = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'REFERRAL_ATTRIBUTED', SALE_ID);
    strict_1.default.ok(docs.has(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, attributedEvent)));
    const rewardEvent = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'AFFILIATE_REWARD_CREATED', SALE_ID);
    strict_1.default.ok(docs.has(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, rewardEvent)));
    // The message is queued in the transaction and sent by a worker later.
    const outbox = affiliate_engine_js_1.affiliateIds.outbox(MERCHANT, 'affiliate_new_customer', SALE_ID);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.outbox(MERCHANT, outbox))?.status, 'QUEUED');
    strict_1.default.equal(outcome.result.referral.attribution_id, ATTRIBUTION_ID);
    strict_1.default.equal(outcome.result.referral.reward?.status, 'PENDING');
    strict_1.default.equal(outcome.result.replayed, false);
});
(0, node_test_1.default)('a percentage is taken in centavos and never rounds in the code favour', async () => {
    const docs = storeWith({
        code: { benefit_type: 'PERCENTAGE', benefit_value: 10 },
    });
    const outcome = await commit(docs, { grossAmount: 99.99 });
    strict_1.default.equal(outcome.status, 'committed');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    // 10% of 99.99 is 9.999; rounding up would give away a centavo per sale.
    strict_1.default.equal(sale?.referral_benefit_amount, 9.99);
    strict_1.default.equal(sale?.amount, 90);
    strict_1.default.equal(sale?.gross_amount, 99.99);
});
(0, node_test_1.default)('a points benefit adds a ledger entry and leaves the price alone', async () => {
    const docs = storeWith({
        code: { benefit_type: 'POINTS', benefit_value: 25 },
        customer: { confirmed_points: 7 },
    });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'committed');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.equal(sale?.amount, 500, 'a points benefit is not a discount');
    strict_1.default.equal(sale?.referral_benefit_amount, 25);
    const entry = docs.get(affiliate_sale_commit_js_1.referralPaths.ledgerEntry(MERCHANT, (0, affiliate_sale_commit_js_1.referralBonusLedgerEntryId)(SALE_ID)));
    strict_1.default.ok(entry, 'the promotional points were not written to the ledger');
    strict_1.default.equal(entry.entry_type, 'REFERRAL_BONUS');
    strict_1.default.equal(entry.source_type, 'referral');
    strict_1.default.equal(entry.source_id, SALE_ID);
    strict_1.default.equal(entry.points_delta, 25);
    strict_1.default.equal(entry.balance_after, 32);
    // Just before the sale, so the sale's own entry stays the newest one.
    strict_1.default.ok(entry.occurred_at < NOW);
});
(0, node_test_1.default)('an existing customer under an open code gets the benefit and nothing else', async () => {
    const docs = storeWith({
        code: { first_visit_only: false },
        extra: {
            [`${affiliate_sale_commit_js_1.referralPaths.sales(MERCHANT)}/old-sale`]: {
                id: 'old-sale',
                customer_id: CUSTOMER,
                amount: 200,
                cancellation_status: 'ACTIVE',
            },
        },
    });
    (0, node_test_1.default)('a prior rejected attribution is confirmed by a later valid acquisition', async () => {
        const attributionPath = affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID);
        const docs = storeWith({
            extra: {
                [attributionPath]: {
                    id: ATTRIBUTION_ID,
                    merchant_id: MERCHANT,
                    affiliate_id: 'af-old',
                    affiliate_code_id: 'old-code',
                    customer_id: CUSTOMER,
                    first_sale_id: 'old-sale',
                    status: 'REJECTED',
                    rejection_reason: 'CODE_EXPIRED',
                    attributed_at: NOW - 1000,
                    created_at: NOW - 1000,
                    updated_at: NOW - 1000,
                },
            },
        });
        const outcome = await commit(docs);
        strict_1.default.equal(outcome.status, 'committed');
        const attribution = docs.get(attributionPath);
        strict_1.default.equal(attribution?.status, 'CONFIRMED');
        strict_1.default.equal(attribution?.affiliate_id, 'af1');
        strict_1.default.equal(attribution?.affiliate_code_id, 'ac1');
        strict_1.default.equal(attribution?.first_sale_id, SALE_ID);
        strict_1.default.equal(attribution?.rejection_reason, null);
        strict_1.default.equal(attribution?.created_at, NOW - 1000);
        strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
        strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status, 'PENDING');
    });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.equal(sale?.amount, 450, 'the benefit was not applied');
    strict_1.default.equal(sale?.referral_status, 'PENDING');
    // No acquisition happened, so nothing is owed and the code is not spent.
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)), false);
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID)), false);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
    strict_1.default.equal(outcome.result.referral.attribution_id, null);
    strict_1.default.equal(outcome.result.referral.reward, null);
});
/* -------------------------------------------------------------- refusals */
(0, node_test_1.default)('a code that expired since the preview is refused, and nothing is written', async () => {
    const docs = storeWith({ code: { expires_at: NOW - 1 } });
    const before = new Set(docs.keys());
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CODE_EXPIRED');
    strict_1.default.equal(typeof outcome.message, 'string');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID)), false);
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)), false);
    // The refusal itself is recorded, and it is the only thing written.
    const added = [...docs.keys()].filter((key) => !before.has(key));
    strict_1.default.equal(added.length, 1);
    strict_1.default.ok(added[0].includes('affiliate_events'));
});
(0, node_test_1.default)('an existing customer under a first-visit code is refused by eligibility', async () => {
    const docs = storeWith({
        extra: {
            [`${affiliate_sale_commit_js_1.referralPaths.sales(MERCHANT)}/old-sale`]: {
                id: 'old-sale',
                customer_id: CUSTOMER,
                amount: 200,
            },
        },
    });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CUSTOMER_NOT_ELIGIBLE');
});
(0, node_test_1.default)("another business's code is not found, and its documents are never read", async () => {
    const docs = storeWith({ lookupMerchantId: 'm2' });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    // Not AFFILIATE_INACTIVE, not CODE_DISABLED: a distinguishable answer is a
    // way to enumerate another business's codes.
    strict_1.default.equal(outcome.reason, 'CODE_NOT_FOUND');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID)), false);
});
(0, node_test_1.default)('an affiliate selling to themselves is refused', async () => {
    const docs = storeWith({ affiliate: { phone_e164: PHONE } });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'SELF_REFERRAL_NOT_ALLOWED');
});
(0, node_test_1.default)('a customer the server has never seen cannot be attributed anything', async () => {
    const docs = storeWith();
    docs.delete(affiliate_sale_commit_js_1.referralPaths.customer(MERCHANT, CUSTOMER));
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'customer_not_found');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID)), false);
});
/* ---------------------------------------------------------------- replay */
(0, node_test_1.default)('the same request twice makes one sale, one attribution and one reward', async () => {
    const docs = storeWith();
    const first = await commit(docs);
    const second = await commit(docs);
    strict_1.default.equal(first.status, 'committed');
    strict_1.default.equal(second.status, 'replayed');
    if (second.status !== 'replayed')
        return;
    const sales = [...docs.keys()].filter((key) => key.startsWith(`${affiliate_sale_commit_js_1.referralPaths.sales(MERCHANT)}/`));
    strict_1.default.deepEqual(sales, [affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID)]);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    strict_1.default.equal(second.result.replayed, true);
    strict_1.default.equal(second.result.referral.attribution_id, ATTRIBUTION_ID);
    strict_1.default.equal(second.result.referral.reward?.id, FIRST_REWARD_ID);
    const rewards = [...docs.keys()].filter((key) => key.includes('affiliate_rewards/'));
    strict_1.default.equal(rewards.length, 1);
});
(0, node_test_1.default)('reusing a local sale id for a different sale is a conflict, not a sale', async () => {
    const docs = storeWith();
    await commit(docs);
    const outcome = await commit(docs, { grossAmount: 900 });
    strict_1.default.equal(outcome.status, 'conflict');
    // The committed sale is untouched.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID))?.gross_amount, 500);
});
(0, node_test_1.default)('changing an item under the same local sale id is a conflict', async () => {
    const docs = storeWith();
    const original = {
        id: 'rsi-1',
        merchantItemId: 'service-1',
        nameSnapshot: 'Corte',
        typeSnapshot: 'SERVICE',
        quantity: 1,
        unitPrice: 500,
        subtotal: 500,
    };
    await commit(docs, { items: [original] });
    const outcome = await commit(docs, {
        items: [
            {
                ...original,
                merchantItemId: 'service-2',
                nameSnapshot: 'Barba',
            },
        ],
    });
    strict_1.default.equal(outcome.status, 'conflict');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.saleItem(MERCHANT, original.id))
        ?.merchant_item_id, 'service-1');
});
/* ------------------------------------------------------------- atomicity */
(0, node_test_1.default)('a failure partway through leaves nothing behind', async () => {
    const docs = storeWith();
    const before = new Map([...docs].map(([key, value]) => [key, JSON.stringify(value)]));
    await strict_1.default.rejects(() => commit(docs, {}, config(), { failAfterWrites: 2 }), /injected transaction failure/);
    strict_1.default.deepEqual(new Map([...docs].map(([key, value]) => [key, JSON.stringify(value)])), before, 'a partial commit reached the store');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID)), false);
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)), false);
});
(0, node_test_1.default)('the sale is written before anything that depends on it', async () => {
    const docs = storeWith();
    const { gateway, applied } = gatewayOver(docs);
    await (0, affiliate_sale_commit_js_1.commitReferralSale)(gateway, input(), () => config());
    const paths = applied.map((operation) => operation.path);
    strict_1.default.equal(paths[0], affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.ok(paths.includes(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)));
    strict_1.default.ok(paths.includes(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID)));
    strict_1.default.ok(paths.includes(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1')));
});
/* ---------------------------------------------------------- cancellation */
async function cancel(docs, saleId = SALE_ID, merchantId = MERCHANT) {
    const { gateway } = gatewayOver(docs);
    return (0, affiliate_sale_commit_js_1.reverseReferralSale)(gateway, {
        merchantId,
        saleId,
        cancelledAt: NOW + 1000,
        actorId: 'u1',
    });
}
(0, node_test_1.default)('cancelling a referred sale cancels the acquisition and the unpaid reward once', async () => {
    const docs = storeWith();
    await commit(docs);
    const first = await cancel(docs);
    strict_1.default.equal(first.status, 'reversed');
    strict_1.default.equal(first.attribution_cancelled, true);
    strict_1.default.deepEqual(first.rewards_cancelled, [FIRST_REWARD_ID]);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CANCELLED');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status, 'CANCELLED');
    // The code was used. Cancelling the sale does not give the use back.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    const second = await cancel(docs);
    strict_1.default.equal(second.status, 'already_reversed');
    strict_1.default.deepEqual(second.rewards_cancelled, []);
});
(0, node_test_1.default)('a reward already paid is left alone and raised for a person', async () => {
    const docs = storeWith();
    await commit(docs);
    docs.set(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID), {
        ...docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID)),
        status: 'PAID',
        paid_at: NOW + 1,
    });
    const outcome = await cancel(docs);
    strict_1.default.deepEqual(outcome.rewards_cancelled, []);
    strict_1.default.deepEqual(outcome.rewards_needing_review, [FIRST_REWARD_ID]);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status, 'PAID', 'points already handed over were unpaid by a status change');
    const signalId = affiliate_engine_js_1.affiliateIds.fraudSignal(MERCHANT, 'PAID_REWARD_SALE_CANCELLED', FIRST_REWARD_ID);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.fraudSignal(MERCHANT, signalId))?.requires_manual_review, true);
});
(0, node_test_1.default)('a sale with no code cancels without touching anything of the referral', async () => {
    const docs = storeWith({
        extra: {
            [affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, 'plain')]: {
                id: 'plain',
                merchant_id: MERCHANT,
                customer_id: CUSTOMER,
                amount: 200,
            },
        },
    });
    const outcome = await cancel(docs, 'plain');
    strict_1.default.equal(outcome.status, 'not_referred');
    strict_1.default.equal(outcome.attribution_cancelled, false);
});
(0, node_test_1.default)('a cancellation cannot reach a sale of another business', async () => {
    const docs = storeWith();
    await commit(docs);
    // Same sale id, asked for as another business: the path does not resolve.
    const outcome = await cancel(docs, SALE_ID, 'm2');
    strict_1.default.equal(outcome.status, 'not_referred');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CONFIRMED');
});
/* --------------------------------------------------------------- returns */
async function recordReturn(docs, saleId, occurredAt, settings) {
    const { gateway } = gatewayOver(docs);
    return (0, affiliate_sale_commit_js_1.recordReferredCustomerReturn)(gateway, {
        merchantId: MERCHANT,
        saleId,
        customerId: CUSTOMER,
        amount: 300,
        occurredAt,
    }, settings);
}
const RETURNS_ON = config({
    returnRewardEnabled: true,
    returnRewardPoints: 40,
    returnWindowDays: 30,
});
(0, node_test_1.default)('a referred customer coming back is recorded once and rewarded once', async () => {
    const docs = storeWith();
    await commit(docs);
    const first = await recordReturn(docs, 'sale-2', NOW + 86400000, RETURNS_ON);
    const second = await recordReturn(docs, 'sale-2', NOW + 86400000, RETURNS_ON);
    strict_1.default.equal(first.status, 'recorded');
    strict_1.default.equal(second.status, 'already_recorded');
    const reward = docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID));
    strict_1.default.equal(reward?.value, 40);
    strict_1.default.equal(reward?.status, 'PENDING');
    strict_1.default.equal(reward?.trigger_sale_id, 'sale-2');
    const eventId = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'REFERRED_CUSTOMER_RETURNED', 'sale-2');
    strict_1.default.ok(docs.has(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, eventId)));
});
(0, node_test_1.default)('the sale that made the attribution is not a return', async () => {
    const docs = storeWith();
    await commit(docs);
    const outcome = await recordReturn(docs, SALE_ID, NOW, RETURNS_ON);
    strict_1.default.equal(outcome.status, 'first_sale');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
});
(0, node_test_1.default)('a return outside the window is recorded but earns nothing', async () => {
    const docs = storeWith();
    await commit(docs);
    const outcome = await recordReturn(docs, 'sale-late', NOW + 31 * 86400000, RETURNS_ON);
    strict_1.default.equal(outcome.status, 'out_of_window');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
    const eventId = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'REFERRED_CUSTOMER_RETURNED', 'sale-late');
    strict_1.default.ok(docs.has(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, eventId)), 'the visit still happened and is still history');
});
(0, node_test_1.default)('a customer nobody referred triggers nothing on a second sale', async () => {
    const docs = storeWith();
    const outcome = await recordReturn(docs, 'sale-2', NOW, RETURNS_ON);
    strict_1.default.equal(outcome.status, 'not_referred');
});
(0, node_test_1.default)('a retriggered return writes one event, one reward and one message', async () => {
    // The hook hangs off the ordinary sale write, and Firestore fires that
    // trigger at least once — sometimes more. Every document it writes is keyed
    // by the fact rather than by the firing, so the second one adds nothing.
    const docs = storeWith();
    await commit(docs);
    const eventId = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'REFERRED_CUSTOMER_RETURNED', 'sale-2');
    const rewardEventId = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'AFFILIATE_REWARD_CREATED', RETURN_REWARD_ID);
    const outboxId = affiliate_engine_js_1.affiliateIds.outbox(MERCHANT, 'affiliate_customer_returned', 'sale-2');
    const writes = [];
    for (let firing = 0; firing < 3; firing++) {
        const { gateway, applied } = gatewayOver(docs);
        await (0, affiliate_sale_commit_js_1.recordReferredCustomerReturn)(gateway, {
            merchantId: MERCHANT,
            saleId: 'sale-2',
            customerId: CUSTOMER,
            amount: 300,
            occurredAt: NOW + 86400000,
        }, RETURNS_ON);
        writes.push(...applied);
    }
    const created = (docPath) => writes.filter((write) => write.kind === 'create' && write.path === docPath).length;
    strict_1.default.equal(created(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, eventId)), 1, 'return event');
    strict_1.default.equal(created(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, rewardEventId)), 1, 'reward event');
    strict_1.default.equal(created(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), 1, 'reward');
    strict_1.default.equal(created(affiliate_sale_commit_js_1.referralPaths.outbox(MERCHANT, outboxId)), 1, 'queued message');
});
(0, node_test_1.default)('a queued message names the reward it is about, not a frozen status', async () => {
    // The worker re-reads the reward at delivery time, so a merchant who
    // approves in the meantime is quoted correctly rather than as still
    // deciding. That is only possible if the row says which reward it means.
    const docs = storeWith();
    await commit(docs);
    await recordReturn(docs, 'sale-2', NOW + 86400000, RETURNS_ON);
    const firstSale = docs.get(affiliate_sale_commit_js_1.referralPaths.outbox(MERCHANT, affiliate_engine_js_1.affiliateIds.outbox(MERCHANT, 'affiliate_new_customer', SALE_ID)));
    const returned = docs.get(affiliate_sale_commit_js_1.referralPaths.outbox(MERCHANT, affiliate_engine_js_1.affiliateIds.outbox(MERCHANT, 'affiliate_customer_returned', 'sale-2')));
    strict_1.default.equal(firstSale?.payload?.reward_id, FIRST_REWARD_ID);
    strict_1.default.equal(returned?.payload?.reward_id, RETURN_REWARD_ID);
});
(0, node_test_1.default)('cancelling a return sale cancels its reward and leaves the acquisition', async () => {
    const docs = storeWith();
    await commit(docs);
    await recordReturn(docs, 'sale-2', NOW + 86400000, RETURNS_ON);
    docs.set(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, 'sale-2'), {
        id: 'sale-2',
        merchant_id: MERCHANT,
        customer_id: CUSTOMER,
        amount: 300,
        affiliate_code_id: 'ac1',
        affiliate_id: 'af1',
    });
    const outcome = await cancel(docs, 'sale-2');
    strict_1.default.equal(outcome.attribution_cancelled, false);
    strict_1.default.deepEqual(outcome.rewards_cancelled, [RETURN_REWARD_ID]);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CONFIRMED');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status, 'PENDING');
});
/* ------------------------------------------------- source-level obligations */
const COMMIT_SOURCE = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_sale_commit.ts'), 'utf8');
(0, node_test_1.default)('the commit re-runs the validation instead of trusting the preview', () => {
    strict_1.default.ok(COMMIT_SOURCE.includes('validateReferral('), 'the sale commit no longer runs the shared validation');
    strict_1.default.ok(COMMIT_SOURCE.includes('saleAmount: input.grossAmount'), 'the commit validates against something other than the real sale amount');
});
(0, node_test_1.default)('no value a client could send decides what anything is worth', () => {
    // The benefit comes off the code, the reward off the settings, the points off
    // the business's loyalty config. A request field named like any of them would
    // be a way to price your own discount.
    for (const forbidden of [
        'payload.benefit',
        'input.benefitValue',
        'input.rewardValue',
        'input.pointsAwarded',
        'input.affiliateId',
    ]) {
        strict_1.default.ok(!COMMIT_SOURCE.includes(forbidden), `${forbidden} is read from the request`);
    }
    strict_1.default.ok(COMMIT_SOURCE.includes('calculateBenefit(code, input.grossAmount)'));
    strict_1.default.ok(COMMIT_SOURCE.includes('planFirstSaleReward(config)'));
});
(0, node_test_1.default)('no phone number reaches an id, an event or a stored document', () => {
    const stored = COMMIT_SOURCE.split('\n').filter((line) => {
        const text = line.replace(/\r$/, '').trim();
        if (text.startsWith('*') || text.startsWith('//') || text.startsWith('/*'))
            return false;
        return /phone/i.test(text);
    });
    for (const line of stored) {
        strict_1.default.ok(/phoneFingerprint|customerPhoneE164|phoneAlreadyKnown|phoneMatchCount|phoneE164|'phone'/.test(line), `a phone is used in an unreviewed way: ${line.trim()}`);
    }
});
(0, node_test_1.default)('the usage count is only ever increased', () => {
    strict_1.default.ok(COMMIT_SOURCE.includes('usage_count: code.usageCount + 1'));
    strict_1.default.ok(!/usage_count:\s*[^+\n]*-\s*1/.test(COMMIT_SOURCE), 'something decrements the usage count');
});
