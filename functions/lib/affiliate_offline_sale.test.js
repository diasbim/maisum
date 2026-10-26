"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_engine_js_1 = require("./affiliate_engine.js");
const affiliate_offline_sale_js_1 = require("./affiliate_offline_sale.js");
const affiliate_sale_commit_js_1 = require("./affiliate_sale_commit.js");
/**
 * Reconciling a sale the till already made.
 *
 * Everything here turns on one asymmetry the online commit does not have: the
 * customer has already paid and gone. A refusal cannot un-charge them, and an
 * acceptance cannot refund them. So the properties under test are about money
 * that has already moved:
 *
 *   a refused code keeps its discount and pays the affiliate nothing;
 *   a valid code the till could not price earns the acquisition but no refund;
 *   a POINTS benefit survives either way, because points are a ledger entry.
 *
 * The same fake transaction as `affiliate_sale_commit.test.ts`: it refuses a
 * read after a write and a `create` on an existing document, so a plan that
 * Firestore would reject fails here instead of in production.
 */
const NOW = 1800000000000;
const MERCHANT = 'm1';
const CODE = 'AFI-ANA-7K2P';
const CUSTOMER = 'c1';
const PHONE = '+258841234567';
function gatewayOver(docs) {
    const applied = [];
    const gateway = {
        async runTransaction(run) {
            const staged = [];
            let hasWritten = false;
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
                create: (docPath, data) => {
                    hasWritten = true;
                    staged.push({ kind: 'create', path: docPath, data });
                },
                merge: (docPath, data) => {
                    hasWritten = true;
                    staged.push({ kind: 'merge', path: docPath, data });
                },
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
const LINK_ID = affiliate_engine_js_1.affiliateIds.link('af1', MERCHANT);
const ATTRIBUTION_ID = affiliate_engine_js_1.affiliateIds.attribution(MERCHANT, CUSTOMER);
const SALE_ID = affiliate_engine_js_1.affiliateIds.sale('d1', 'l1');
const REWARD_ID = affiliate_engine_js_1.affiliateIds.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE');
const SIGNAL_ID = affiliate_engine_js_1.affiliateIds.fraudSignal(MERCHANT, 'OFFLINE_CODE_REJECTED', SALE_ID);
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
    if (overrides.withLookup !== false) {
        docs.set(affiliate_sale_commit_js_1.referralPaths.codeLookup(CODE), {
            code: CODE,
            merchant_id: MERCHANT,
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
    }
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
        offlineBenefitApplied: true,
        appliedBenefit: {
            type: 'FIXED_AMOUNT',
            value: 50,
            discountAmount: 50,
            pointsAwarded: 0,
        },
        localCreatedAt: NOW - 60000,
        ...overrides,
    };
}
async function reconcile(docs, overrides = {}, settings = config()) {
    const { gateway } = gatewayOver(docs);
    return (0, affiliate_offline_sale_js_1.commitOfflineReferralSale)(gateway, input(overrides), () => settings);
}
/* ------------------------------------------------------- the benefit given */
(0, node_test_1.default)('a cached benefit already given is honoured exactly as charged', async () => {
    const docs = storeWith();
    const outcome = await reconcile(docs);
    strict_1.default.equal(outcome.status, 'committed');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.equal(sale?.amount, 450);
    strict_1.default.equal(sale?.gross_amount, 500);
    strict_1.default.equal(sale?.referral_benefit_amount, 50);
    strict_1.default.equal(sale?.referral_status, 'ATTRIBUTED');
    strict_1.default.equal(sale?.referral_source, 'OFFLINE');
    // Points are earned on what the customer paid, exactly as online.
    strict_1.default.equal(sale?.points, 4);
    strict_1.default.equal(sale?.referral_idempotency_key, (0, affiliate_engine_js_1.saleIdempotencyKey)('d1', 'l1'));
});
(0, node_test_1.default)('a code changed to points never erases a discount already given', async () => {
    const docs = storeWith({
        code: { benefit_type: 'POINTS', benefit_value: 120 },
    });
    const outcome = await reconcile(docs);
    strict_1.default.equal(outcome.status, 'committed');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.equal(sale?.amount, 450);
    strict_1.default.equal(sale?.gross_amount, 500);
    strict_1.default.equal(sale?.referral_benefit_type, 'FIXED_AMOUNT');
    strict_1.default.equal(sale?.referral_benefit_value, 50);
    strict_1.default.equal(sale?.referral_benefit_amount, 50);
    strict_1.default.equal(sale?.points, 4);
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.ledgerEntry(MERCHANT, (0, affiliate_sale_commit_js_1.referralBonusLedgerEntryId)(SALE_ID))), false, 'the customer must not receive both the stale discount and new points');
});
(0, node_test_1.default)('the acquisition, the reward and the usage count move together', async () => {
    const docs = storeWith();
    await reconcile(docs);
    const attribution = docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
    strict_1.default.equal(attribution?.status, 'CONFIRMED');
    strict_1.default.equal(attribution?.idempotency_key, affiliate_engine_js_1.referralIdempotencyKeys.attribution(MERCHANT, (0, affiliate_engine_js_1.referralPhoneHash)(PHONE)));
    const reward = docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, REWARD_ID));
    strict_1.default.equal(reward?.status, 'PENDING');
    strict_1.default.equal(reward?.value, 100);
    strict_1.default.equal(reward?.idempotency_key, affiliate_engine_js_1.referralIdempotencyKeys.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE'));
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
});
(0, node_test_1.default)('a key never carries the number it identifies', () => {
    const key = affiliate_engine_js_1.referralIdempotencyKeys.attribution(MERCHANT, (0, affiliate_engine_js_1.referralPhoneHash)(PHONE));
    strict_1.default.ok(!key.includes('841234567'));
    strict_1.default.ok(!key.includes(PHONE));
});
/* --------------------------------------------------------------- refusals */
(0, node_test_1.default)('a refused code keeps the sale and the discount and pays nobody', async () => {
    const docs = storeWith({ code: { expires_at: NOW - 1 } });
    const outcome = await reconcile(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CODE_EXPIRED');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    // The discount stands: reversing it is an invoice sent to somebody who left
    // the shop an hour ago.
    strict_1.default.equal(sale?.amount, 450);
    strict_1.default.equal(sale?.referral_benefit_amount, 50);
    strict_1.default.equal(sale?.referral_status, 'REJECTED');
    strict_1.default.equal(sale?.referral_rejection_reason, 'CODE_EXPIRED');
    const attribution = docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
    strict_1.default.equal(attribution?.status, 'REJECTED');
    strict_1.default.equal(attribution?.rejection_reason, 'CODE_EXPIRED');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, REWARD_ID)), false);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
});
(0, node_test_1.default)('a refusal that cost the business money raises a HIGH signal', async () => {
    const docs = storeWith({ code: { status: 'DISABLED' } });
    await reconcile(docs);
    const signal = docs.get(affiliate_sale_commit_js_1.referralPaths.fraudSignal(MERCHANT, SIGNAL_ID));
    strict_1.default.equal(signal?.signal_type, 'OFFLINE_CODE_REJECTED');
    strict_1.default.equal(signal?.severity, 'HIGH');
    strict_1.default.equal((signal?.metadata).benefit_retained, true);
    strict_1.default.equal((signal?.metadata).retained_amount, 50);
});
(0, node_test_1.default)('a refusal that cost nothing is still recorded, at lower severity', async () => {
    const docs = storeWith({ code: { status: 'DISABLED' } });
    await reconcile(docs, {
        offlineBenefitApplied: false,
        appliedBenefit: null,
    });
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.equal(sale?.amount, 500);
    strict_1.default.equal(sale?.referral_benefit_amount, null);
    const signal = docs.get(affiliate_sale_commit_js_1.referralPaths.fraudSignal(MERCHANT, SIGNAL_ID));
    strict_1.default.equal(signal?.severity, 'MEDIUM');
});
(0, node_test_1.default)('a refusal never overwrites an acquisition another affiliate already has', async () => {
    const docs = storeWith({
        // With `firstVisitOnly` off the validation reaches the clause that is
        // actually about this: the customer belongs to somebody already.
        code: { first_visit_only: false },
        extra: {
            [affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID)]: {
                id: ATTRIBUTION_ID,
                merchant_id: MERCHANT,
                affiliate_id: 'af-other',
                affiliate_code_id: 'ac-other',
                customer_id: CUSTOMER,
                status: 'CONFIRMED',
            },
        },
    });
    const outcome = await reconcile(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CUSTOMER_ALREADY_REFERRED');
    // Somebody else's customer is still theirs.
    const attribution = docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
    strict_1.default.equal(attribution?.affiliate_id, 'af-other');
    strict_1.default.equal(attribution?.status, 'CONFIRMED');
});
/* ------------------------------------------------------- the uncached code */
(0, node_test_1.default)('a valid code the till could not price earns the acquisition, not a refund', async () => {
    const docs = storeWith();
    const outcome = await reconcile(docs, {
        offlineBenefitApplied: false,
        appliedBenefit: null,
    });
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    strict_1.default.equal(outcome.result.referral.monetary_benefit_applied, false);
    strict_1.default.equal(outcome.result.referral.retroactive_discount_applied, false);
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    // Charged in full, and it stays charged in full: money is not refunded by a
    // sync.
    strict_1.default.equal(sale?.amount, 500);
    strict_1.default.equal(sale?.referral_benefit_amount, 0);
    strict_1.default.equal(sale?.referral_status, 'ATTRIBUTED');
    // The affiliate is still credited: the acquisition happened.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CONFIRMED');
    strict_1.default.ok(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, REWARD_ID)));
});
(0, node_test_1.default)('a POINTS benefit is credited even when the till could not price it', async () => {
    const docs = storeWith({
        code: { benefit_type: 'POINTS', benefit_value: 120 },
    });
    const outcome = await reconcile(docs, {
        offlineBenefitApplied: false,
        appliedBenefit: null,
    });
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    strict_1.default.equal(outcome.result.referral.points_benefit_credited, true);
    // Points are an entry in a ledger, and adding one costs the customer nothing
    // they have already paid.
    const ledger = docs.get(affiliate_sale_commit_js_1.referralPaths.ledgerEntry(MERCHANT, (0, affiliate_sale_commit_js_1.referralBonusLedgerEntryId)(SALE_ID)));
    strict_1.default.equal(ledger?.points_delta, 120);
    strict_1.default.equal(ledger?.entry_type, 'REFERRAL_BONUS');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID))?.amount, 500);
});
(0, node_test_1.default)('a discount larger than the bill is capped, never negative', async () => {
    const docs = storeWith();
    await reconcile(docs, {
        grossAmount: 30,
        appliedBenefit: {
            type: 'FIXED_AMOUNT',
            value: 50,
            discountAmount: 50,
            pointsAwarded: 0,
        },
    });
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID));
    strict_1.default.ok(sale?.amount >= 0);
});
/* --------------------------------------------------------- ordering, replay */
(0, node_test_1.default)('a competing sale that finds the limit reached is refused', async () => {
    const docs = storeWith({ code: { usage_limit: 1, usage_count: 1 } });
    const outcome = await reconcile(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    // The earliest qualifying sale to reach the server spent the use; a later
    // arrival is told so.
    strict_1.default.equal(outcome.reason, 'CODE_USAGE_LIMIT_REACHED');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
});
(0, node_test_1.default)('replaying the same reconciliation writes nothing new', async () => {
    const docs = storeWith();
    await reconcile(docs);
    const sizeAfterFirst = docs.size;
    const { gateway, applied } = gatewayOver(docs);
    const outcome = await (0, affiliate_offline_sale_js_1.commitOfflineReferralSale)(gateway, input(), () => config());
    strict_1.default.equal(outcome.status, 'replayed');
    strict_1.default.deepEqual(applied, []);
    strict_1.default.equal(docs.size, sizeAfterFirst);
});
(0, node_test_1.default)('the same local id for a different sale is a conflict, not a replay', async () => {
    const docs = storeWith();
    await reconcile(docs);
    const outcome = await reconcile(docs, { grossAmount: 900 });
    strict_1.default.equal(outcome.status, 'conflict');
});
(0, node_test_1.default)('a customer the server has not seen yet is deferred, not refused', async () => {
    const docs = storeWith();
    docs.delete(affiliate_sale_commit_js_1.referralPaths.customer(MERCHANT, CUSTOMER));
    const outcome = await reconcile(docs);
    // The customer's own create is usually right in front of this in the queue.
    // Refusing here would throw away the sale for being early.
    strict_1.default.equal(outcome.status, 'deferred');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID)), false);
});
/* ------------------------------------------------------------- clock skew */
(0, node_test_1.default)('a device whose clock is a day out still has its sale processed', async () => {
    const docs = storeWith();
    const outcome = await reconcile(docs, {
        localCreatedAt: NOW - affiliate_engine_js_1.CLOCK_SKEW_SIGNAL_MS - 60000,
    });
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    strict_1.default.ok(outcome.result.clock_skew_ms > affiliate_engine_js_1.CLOCK_SKEW_SIGNAL_MS);
    // Recorded on the event so a run of them is visible, never used to refuse a
    // real purchase.
    const eventId = affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'REFERRAL_ATTRIBUTED', SALE_ID);
    const event = docs.get(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, eventId));
    strict_1.default.equal((event?.metadata).clock_skew_exceeded, true);
    // The sale keeps the till's own timestamp, which is what the receipt says.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, SALE_ID))?.created_at, NOW - affiliate_engine_js_1.CLOCK_SKEW_SIGNAL_MS - 60000);
});
/* ------------------------------------------------------------- sale items */
(0, node_test_1.default)('sale items are written once, under deterministic ids', async () => {
    const docs = storeWith();
    await reconcile(docs, {
        items: [
            {
                id: 'rsi_1',
                merchantItemId: 'mi1',
                nameSnapshot: 'Corte',
                typeSnapshot: 'SERVICE',
                quantity: 1,
                unitPrice: 500,
                subtotal: 500,
            },
        ],
    });
    const item = docs.get(affiliate_sale_commit_js_1.referralPaths.saleItem(MERCHANT, 'rsi_1'));
    strict_1.default.equal(item?.sale_id, SALE_ID);
    strict_1.default.equal(item?.quantity, 1);
});
