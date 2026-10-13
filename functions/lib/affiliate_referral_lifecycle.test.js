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
const affiliate_outbox_js_1 = require("./affiliate_outbox.js");
const affiliate_sale_commit_js_1 = require("./affiliate_sale_commit.js");
/**
 * The seven scenarios of §12, each run end to end against one store.
 *
 * The other affiliate test files each hold one seam still and prove a property
 * of it. This one does the opposite: it starts from an empty business, runs a
 * whole scenario through the real commit, the real offline reconciliation, the
 * real return hook and the real outbox worker, and then asks what the business
 * is left holding. A regression that no single-seam test can see — a message
 * queued for a sale that was refused, a reward that survives a replay, a
 * second attribution created by reconnecting — shows up here as a wrong count
 * at the end of a story rather than as a wrong field in the middle of one.
 *
 * It runs without an emulator, deliberately. The transaction is a port, and
 * the double below behaves the way Firestore does in the two ways that decide
 * whether a commit is legal at all: a read issued after a write is refused,
 * and `create` on an existing document is refused. A plan that production
 * would reject fails here instead. What this does *not* prove is that
 * `firestore.rules` and `firestore.indexes.json` are deployed and enforced —
 * that needs the emulator, and is asserted as a source contract in
 * `affiliate_security_contracts.test.ts` instead.
 */
const NOW = 1800000000000;
const DAY = 86400000;
const MERCHANT = 'm1';
const OTHER_MERCHANT = 'm2';
const CODE = 'AFI-ANA-7K2P';
const CUSTOMER = 'c1';
const PHONE = '+258841234567';
const DEVICE = 'till-1';
const LINK_ID = affiliate_engine_js_1.affiliateIds.link('af1', MERCHANT);
const ATTRIBUTION_ID = affiliate_engine_js_1.affiliateIds.attribution(MERCHANT, CUSTOMER);
const FIRST_REWARD_ID = affiliate_engine_js_1.affiliateIds.reward(ATTRIBUTION_ID, 'FIRST_QUALIFYING_SALE');
const RETURN_REWARD_ID = affiliate_engine_js_1.affiliateIds.reward(ATTRIBUTION_ID, 'CUSTOMER_RETURN');
/**
 * One map, shared by every seam in a scenario.
 *
 * The outbox rows the sale transaction writes are read back by the worker from
 * the same paths, so a message the commit never queued is a message the worker
 * cannot invent.
 */
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
/** The same documents, seen the way the outbox worker addresses them. */
function outboxStoreOver(docs) {
    return {
        async runTransaction(run) {
            const staged = new Map();
            const transaction = {
                get: async (merchantId, outboxId) => {
                    const data = docs.get(affiliate_sale_commit_js_1.referralPaths.outbox(merchantId, outboxId));
                    return data === undefined ? null : { ...data };
                },
                update: (merchantId, outboxId, patch) => {
                    const path = affiliate_sale_commit_js_1.referralPaths.outbox(merchantId, outboxId);
                    staged.set(path, { ...(staged.get(path) ?? {}), ...patch });
                },
            };
            const result = await run(transaction);
            for (const [path, patch] of staged) {
                docs.set(path, { ...(docs.get(path) ?? {}), ...patch });
            }
            return result;
        },
        async listPending(input) {
            const rows = [];
            for (const [path, data] of docs) {
                const match = /^businesses\/([^/]+)\/affiliate_outbox\/([^/]+)$/.exec(path);
                if (match === null)
                    continue;
                const [, merchantId, id] = match;
                if (input.merchantId !== null && merchantId !== input.merchantId)
                    continue;
                const status = String(data.status ?? 'QUEUED');
                if (!affiliate_outbox_js_1.CLAIMABLE_STATUSES.includes(status))
                    continue;
                if (Number(data.next_attempt_at ?? 0) > input.now)
                    continue;
                rows.push({ merchantId, id, data: { ...data } });
            }
            rows.sort((left, right) => Number(left.data.created_at ?? 0) - Number(right.data.created_at ?? 0));
            return rows.slice(0, input.limit);
        },
    };
}
/* ------------------------------------------------------------- inspection */
function docsUnder(docs, merchantId, collection) {
    const prefix = `businesses/${merchantId}/${collection}/`;
    return [...docs.keys()].filter((path) => path.startsWith(prefix)).sort();
}
function eventTypes(docs, merchantId = MERCHANT) {
    return docsUnder(docs, merchantId, 'affiliate_events')
        .map((path) => String(docs.get(path)?.event_type ?? ''))
        .sort();
}
function snapshot(docs) {
    return new Map([...docs].map(([key, value]) => [key, JSON.stringify(value)]));
}
/* --------------------------------------------------------------- fixtures */
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
        merchant_name: 'Salão Bela',
        loyalty_config: { points_per_mzn: 100, version: 2 },
    });
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
        code: CODE,
        normalized_code: CODE,
        status: 'ACTIVE',
        starts_at: NOW - DAY,
        expires_at: NOW + 30 * DAY,
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
        display_name: 'Ana Silva',
        first_name: 'Ana',
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
        name: 'Joana Cliente',
        phone: PHONE,
        confirmed_points: 0,
        whatsapp_consent: true,
        ...overrides.customer,
    });
    for (const [path, data] of Object.entries(overrides.extra ?? {})) {
        docs.set(path, data);
    }
    return docs;
}
function input(overrides = {}) {
    return {
        merchantId: MERCHANT,
        deviceId: DEVICE,
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
function offlineInput(overrides = {}) {
    return {
        ...input(),
        offlineBenefitApplied: true,
        appliedBenefit: {
            type: 'FIXED_AMOUNT',
            value: 50,
            discountAmount: 50,
            pointsAwarded: 0,
        },
        localCreatedAt: NOW - 3 * 3600000,
        ...overrides,
    };
}
async function commit(docs, overrides = {}, settings = config(), options = {}) {
    const { gateway } = gatewayOver(docs, options);
    return (0, affiliate_sale_commit_js_1.commitReferralSale)(gateway, input(overrides), () => settings);
}
async function reconcile(docs, overrides = {}, settings = config()) {
    const { gateway } = gatewayOver(docs);
    return (0, affiliate_offline_sale_js_1.commitOfflineReferralSale)(gateway, offlineInput(overrides), () => settings);
}
/**
 * Runs the real worker over whatever the transaction queued.
 *
 * The context resolver mirrors the Firestore one: every number and every name
 * is read from the merchant's own documents at delivery time, never from the
 * queued row, so a message this returns is one the stored data justified.
 */
async function deliverQueuedMessages(docs, options = {}) {
    const sent = [];
    const logged = [];
    const clock = options.now ?? NOW + 1000;
    await (0, affiliate_outbox_js_1.processAffiliateOutbox)({
        store: outboxStoreOver(docs),
        adapter: {
            async send(message) {
                if (options.fail === true)
                    throw new Error('provider down');
                sent.push(message);
                return { providerMessageId: `pm-${sent.length}` };
            },
        },
        resolveContext: async (record) => {
            const business = docs.get(affiliate_sale_commit_js_1.referralPaths.business(record.merchantId));
            const rewardId = typeof record.payload.reward_id === 'string'
                ? record.payload.reward_id
                : null;
            const reward = rewardId === null
                ? null
                : docs.get(affiliate_sale_commit_js_1.referralPaths.reward(record.merchantId, rewardId));
            const context = {
                merchantName: typeof business?.merchant_name === 'string'
                    ? business.merchant_name
                    : null,
                notificationsEnabled: true,
                recipientPhoneE164: null,
                blockedReason: null,
                points: typeof record.payload.reward_points === 'number'
                    ? record.payload.reward_points
                    : 0,
                rewardStatus: typeof reward?.status === 'string'
                    ? reward.status
                    : null,
            };
            if (record.template === 'customer_referral_thanks') {
                const customerId = typeof record.payload.customer_id === 'string'
                    ? record.payload.customer_id
                    : null;
                const customer = customerId === null
                    ? null
                    : docs.get(affiliate_sale_commit_js_1.referralPaths.customer(record.merchantId, customerId));
                if (customer?.whatsapp_consent !== true) {
                    return { ...context, blockedReason: 'consent_missing' };
                }
                return {
                    ...context,
                    recipientPhoneE164: typeof customer.phone === 'string' ? customer.phone : null,
                };
            }
            if (record.affiliateId === null)
                return context;
            const affiliate = docs.get(affiliate_sale_commit_js_1.referralPaths.affiliate(record.affiliateId));
            const link = docs.get(affiliate_sale_commit_js_1.referralPaths.link(record.merchantId, affiliate_engine_js_1.affiliateIds.link(record.affiliateId, record.merchantId)));
            if (affiliate?.status !== 'ACTIVE' || link?.status !== 'ACTIVE') {
                return { ...context, blockedReason: 'affiliate_inactive' };
            }
            return {
                ...context,
                recipientPhoneE164: typeof affiliate.phone_e164 === 'string' ? affiliate.phone_e164 : null,
            };
        },
        now: () => clock,
        newClaimId: () => 'claim-1',
        log: (_level, entry) => logged.push(entry),
    }, { merchantId: MERCHANT, limit: 25 });
    return { sent, logged };
}
/* =========================================================== scenario one */
(0, node_test_1.default)('§12.1 a new customer with a valid code is discounted, attributed, rewarded and messaged', async () => {
    const docs = storeWith();
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    // The benefit: 50 off a 500 bill.
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId));
    strict_1.default.equal(sale?.gross_amount, 500);
    strict_1.default.equal(sale?.amount, 450);
    strict_1.default.equal(sale?.referral_benefit_amount, 50);
    // The ordinary points: earned on what the customer paid, by the business's
    // own loyalty rule, exactly as a sale without a code earns them.
    strict_1.default.equal(sale?.points, 4);
    // The attribution, and the first reward it owes.
    const attribution = docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
    strict_1.default.equal(attribution?.status, 'CONFIRMED');
    strict_1.default.equal(attribution?.first_sale_id, saleId);
    strict_1.default.equal(attribution?.affiliate_id, 'af1');
    const reward = docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID));
    strict_1.default.equal(reward?.status, 'PENDING');
    strict_1.default.equal(reward?.value, 100);
    strict_1.default.equal(reward?.reward_type ?? reward?.type, 'FIRST_QUALIFYING_SALE');
    // The code was spent once.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    // The history a merchant reads back.
    strict_1.default.deepEqual(eventTypes(docs), [
        'AFFILIATE_REWARD_CREATED',
        'REFERRAL_ATTRIBUTED',
    ]);
    // The messages: queued by the transaction, sent by the worker afterwards.
    // Two of them — the affiliate is told they earned something, the customer is
    // thanked — and neither is sent inside the transaction that made the sale.
    const queued = docsUnder(docs, MERCHANT, 'affiliate_outbox');
    strict_1.default.equal(queued.length, 2);
    for (const path of queued)
        strict_1.default.equal(docs.get(path)?.status, 'QUEUED');
    const { sent } = await deliverQueuedMessages(docs);
    strict_1.default.deepEqual(sent.map((message) => message.template).sort(), ['affiliate_new_customer', 'customer_referral_thanks']);
    const toAffiliate = sent.find((message) => message.template === 'affiliate_new_customer');
    strict_1.default.equal(toAffiliate?.toPhoneE164, '+258840000001');
    strict_1.default.match(String(toAffiliate?.body), /Salão Bela/);
    for (const path of queued)
        strict_1.default.equal(docs.get(path)?.status, 'SENT');
});
(0, node_test_1.default)('§12.1 a delivery failure leaves the sale, the attribution and the reward exactly as they were', async () => {
    const docs = storeWith();
    await commit(docs);
    const before = snapshot(docs);
    const { sent } = await deliverQueuedMessages(docs, { fail: true });
    strict_1.default.equal(sent.length, 0);
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    for (const path of [
        affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId),
        affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID),
        affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
    ]) {
        strict_1.default.equal(snapshot(docs).get(path), before.get(path), `WhatsApp changed ${path}`);
    }
    // Only the queue rows moved, and they moved to "try again".
    for (const path of docsUnder(docs, MERCHANT, 'affiliate_outbox')) {
        strict_1.default.equal(docs.get(path)?.status, 'QUEUED');
        strict_1.default.equal(docs.get(path)?.attempts, 1);
    }
});
/* =========================================================== scenario two */
(0, node_test_1.default)('§12.2 an existing customer under a first-visit code is refused and the sale goes on without one', async () => {
    const docs = storeWith({
        extra: {
            [`${affiliate_sale_commit_js_1.referralPaths.sales(MERCHANT)}/older-sale`]: {
                id: 'older-sale',
                merchant_id: MERCHANT,
                customer_id: CUSTOMER,
                amount: 200,
                cancellation_status: 'ACTIVE',
            },
        },
    });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CUSTOMER_NOT_ELIGIBLE');
    strict_1.default.equal(outcome.message, affiliate_contracts_js_1.REFERRAL_REASON_MESSAGE.CUSTOMER_NOT_ELIGIBLE);
    // No acquisition, no reward, no message, and the code is not spent.
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_attributions'), []);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), []);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_outbox'), []);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
    strict_1.default.deepEqual(eventTypes(docs), ['REFERRAL_REJECTED']);
    // The referred sale was never written, so the till is free to ring the same
    // basket up as an ordinary sale under the same local id.
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId)), false);
    docs.set(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId), {
        id: saleId,
        merchant_id: MERCHANT,
        customer_id: CUSTOMER,
        amount: 500,
        points: 5,
        cancellation_status: 'ACTIVE',
    });
    const { gateway } = gatewayOver(docs);
    const reversal = await (0, affiliate_sale_commit_js_1.reverseReferralSale)(gateway, {
        merchantId: MERCHANT,
        saleId,
        cancelledAt: NOW + 1,
        actorId: 'u1',
    });
    strict_1.default.equal(reversal.status, 'not_referred', 'the fallback sale carries no referral to undo');
});
/* ========================================================= scenario three */
(0, node_test_1.default)('§12.3 an expired code says so in words the cashier can read, and blocks nothing', async () => {
    const docs = storeWith({ code: { expires_at: NOW - 1 } });
    const before = snapshot(docs);
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CODE_EXPIRED');
    strict_1.default.equal(outcome.message, 'Este código expirou.');
    // No id, no phone, no other business named in what the cashier is shown.
    strict_1.default.doesNotMatch(outcome.message, /af1|ac1|258|m1/);
    // The rejection event is the only thing written.
    const added = [...docs.keys()].filter((path) => !before.has(path));
    strict_1.default.equal(added.length, 1);
    strict_1.default.ok(added[0].startsWith(`businesses/${MERCHANT}/affiliate_events/`));
    strict_1.default.equal(docs.get(added[0])?.event_type, 'REFERRAL_REJECTED');
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1'))), false);
});
/* ========================================================== scenario four */
(0, node_test_1.default)('§12.4 the same submit twice leaves one sale, one attribution, one reward and one ledger entry', async () => {
    const docs = storeWith({
        code: { benefit_type: 'POINTS', benefit_value: 25 },
    });
    const first = await commit(docs);
    const afterFirst = snapshot(docs);
    const second = await commit(docs);
    strict_1.default.equal(first.status, 'committed');
    strict_1.default.equal(second.status, 'replayed');
    if (second.status !== 'replayed')
        return;
    strict_1.default.equal(second.result.replayed, true);
    strict_1.default.deepEqual(snapshot(docs), afterFirst, 'the replay wrote something');
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'sales'), [
        affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId),
    ]);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_attributions'), [
        affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID),
    ]);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), [
        affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
    ]);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'loyalty_ledger'), [
        affiliate_sale_commit_js_1.referralPaths.ledgerEntry(MERCHANT, (0, affiliate_sale_commit_js_1.referralBonusLedgerEntryId)(saleId)),
    ]);
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_outbox').length, 2);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    // And each message is still sent once, not once per submit.
    const { sent } = await deliverQueuedMessages(docs);
    strict_1.default.equal(sent.length, 2);
    const again = await deliverQueuedMessages(docs);
    strict_1.default.equal(again.sent.length, 0);
});
(0, node_test_1.default)('§12.4 the same replay answers the same thing, including the same idempotency key', async () => {
    const docs = storeWith();
    const first = await commit(docs);
    const second = await commit(docs);
    strict_1.default.equal(first.status, 'committed');
    strict_1.default.equal(second.status, 'replayed');
    if (first.status !== 'committed' || second.status !== 'replayed')
        return;
    strict_1.default.equal(second.result.idempotency_key, (0, affiliate_engine_js_1.saleIdempotencyKey)(DEVICE, 'l1'));
    strict_1.default.equal(second.result.referral.attribution_id, first.result.referral.attribution_id);
    strict_1.default.equal(second.result.referral.reward?.id, first.result.referral.reward?.id);
    strict_1.default.equal(second.result.sale.amount, first.result.sale.amount);
});
/* ========================================================== scenario five */
(0, node_test_1.default)('§12.5 an offline sale with a cached code is confirmed once when the till reconnects', async () => {
    const docs = storeWith();
    // Reconnect: the queued operation reaches the server for the first time.
    const reconnected = await reconcile(docs);
    strict_1.default.equal(reconnected.status, 'committed');
    if (reconnected.status !== 'committed')
        return;
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId));
    strict_1.default.equal(sale?.amount, 450, 'the discount the till gave is the one recorded');
    strict_1.default.equal(sale?.gross_amount, 500);
    strict_1.default.equal(sale?.referral_status, 'ATTRIBUTED');
    strict_1.default.equal(sale?.referral_offline_benefit_applied, true);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CONFIRMED');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status, 'PENDING');
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
    // A retry storm after a flaky reconnect: the queue sends it again, twice.
    const afterFirst = snapshot(docs);
    const again = await reconcile(docs);
    const andAgain = await reconcile(docs);
    strict_1.default.equal(again.status, 'replayed');
    strict_1.default.equal(andAgain.status, 'replayed');
    strict_1.default.deepEqual(snapshot(docs), afterFirst, 'a retry wrote a second time');
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_attributions').length, 1);
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_rewards').length, 1);
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_outbox').length, 1);
    const { sent } = await deliverQueuedMessages(docs);
    strict_1.default.equal(sent.length, 1);
});
(0, node_test_1.default)('§12.5 a device whose clock is days out is still reconciled, and the skew is recorded', async () => {
    const docs = storeWith();
    const outcome = await reconcile(docs, { localCreatedAt: NOW - 3 * DAY });
    strict_1.default.equal(outcome.status, 'committed');
    if (outcome.status !== 'committed')
        return;
    strict_1.default.equal(outcome.result.clock_skew_ms, 3 * DAY);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CONFIRMED', 'a wrong clock is a signal, never a refusal');
    // Recorded on the event, so a run of skewed tills is visible afterwards.
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    const event = docs.get(affiliate_sale_commit_js_1.referralPaths.event(MERCHANT, affiliate_engine_js_1.affiliateIds.event(MERCHANT, 'REFERRAL_ATTRIBUTED', saleId)));
    strict_1.default.equal((event?.metadata).clock_skew_exceeded, true);
    strict_1.default.equal((event?.metadata).clock_skew_ms, 3 * DAY);
    // The sale keeps the till's own timestamp: that is what the receipt says.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId))?.created_at, NOW - 3 * DAY);
});
/* =========================================================== scenario six */
(0, node_test_1.default)('§12.6 a code that expired before the sync keeps the sale and the discount, and pays nobody', async () => {
    const docs = storeWith({ code: { expires_at: NOW - 1 } });
    const outcome = await reconcile(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CODE_EXPIRED');
    // The sale is kept, and so is the money already taken off the bill.
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    const sale = docs.get(affiliate_sale_commit_js_1.referralPaths.sale(MERCHANT, saleId));
    strict_1.default.ok(sale, 'the sale was dropped');
    strict_1.default.equal(sale.amount, 450);
    strict_1.default.equal(sale.gross_amount, 500);
    strict_1.default.equal(sale.referral_benefit_amount, 50);
    strict_1.default.equal(sale.referral_status, 'REJECTED');
    strict_1.default.equal(sale.referral_rejection_reason, 'CODE_EXPIRED');
    // The attribution exists, as the refusal it is.
    const attribution = docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID));
    strict_1.default.equal(attribution?.status, 'REJECTED');
    strict_1.default.equal(attribution?.rejection_reason, 'CODE_EXPIRED');
    // Nobody is owed anything, nobody is messaged, and the code is not spent.
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), []);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_outbox'), []);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 0);
    // And the merchant can find out why they paid for nothing.
    const signals = docsUnder(docs, MERCHANT, 'affiliate_fraud_signals');
    strict_1.default.equal(signals.length, 1);
    const signal = docs.get(signals[0]);
    strict_1.default.equal(signal?.signal_type, 'OFFLINE_CODE_REJECTED');
    strict_1.default.equal(signal?.severity, 'HIGH');
    strict_1.default.deepEqual(eventTypes(docs), ['REFERRAL_REJECTED']);
});
(0, node_test_1.default)('§12.6 a rejected offline referral stays rejected however many times the queue retries it', async () => {
    const docs = storeWith({ code: { expires_at: NOW - 1 } });
    await reconcile(docs);
    const afterFirst = snapshot(docs);
    const second = await reconcile(docs);
    const third = await reconcile(docs);
    strict_1.default.equal(second.status, 'replayed');
    strict_1.default.equal(third.status, 'replayed');
    strict_1.default.deepEqual(snapshot(docs), afterFirst);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'REJECTED');
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), []);
});
/* ========================================================= scenario seven */
const RETURNS_ON = config({
    returnRewardEnabled: true,
    returnRewardPoints: 40,
    returnWindowDays: 30,
});
async function secondVisit(docs, occurredAt, settings, saleId = 'sale-2') {
    const { gateway } = gatewayOver(docs);
    return (0, affiliate_sale_commit_js_1.recordReferredCustomerReturn)(gateway, { merchantId: MERCHANT, saleId, customerId: CUSTOMER, amount: 300, occurredAt }, settings);
}
(0, node_test_1.default)('§12.7 a referred customer who comes back inside the window earns one return event and one reward', async () => {
    const docs = storeWith();
    await commit(docs);
    await deliverQueuedMessages(docs);
    const returned = await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON);
    strict_1.default.equal(returned.status, 'recorded');
    const returns = docsUnder(docs, MERCHANT, 'affiliate_events').filter((path) => docs.get(path)?.event_type === 'REFERRED_CUSTOMER_RETURNED');
    strict_1.default.equal(returns.length, 1);
    const reward = docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID));
    strict_1.default.equal(reward?.status, 'PENDING');
    strict_1.default.equal(reward?.value, 40);
    strict_1.default.equal(reward?.trigger_sale_id, 'sale-2');
    // Two rewards in total, and they are the two different kinds.
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards').sort(), [
        affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID),
        affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
    ].sort());
    // The trigger firing again is the same visit, not a second one.
    const afterReturn = snapshot(docs);
    strict_1.default.equal((await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON)).status, 'already_recorded');
    strict_1.default.deepEqual(snapshot(docs), afterReturn);
    const { sent } = await deliverQueuedMessages(docs, { now: NOW + 7 * DAY + 1000 });
    strict_1.default.equal(sent.length, 1, 'the return was announced exactly once');
    strict_1.default.equal(sent[0].template, 'affiliate_customer_returned');
});
(0, node_test_1.default)('§12.7 a return outside the window is history, not money', async () => {
    const docs = storeWith();
    await commit(docs);
    const returned = await secondVisit(docs, NOW + 45 * DAY, RETURNS_ON);
    strict_1.default.equal(returned.status, 'out_of_window');
    strict_1.default.equal(returned.reward_id, null);
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
});
(0, node_test_1.default)('§12.7 a business that never turned return rewards on owes nothing for a return', async () => {
    const docs = storeWith();
    await commit(docs);
    const returned = await secondVisit(docs, NOW + 7 * DAY, config());
    strict_1.default.equal(returned.reward_id, null);
    strict_1.default.equal(docs.has(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, RETURN_REWARD_ID)), false);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_rewards'), [
        affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID),
    ]);
});
/* ================================================= the whole life, at once */
(0, node_test_1.default)('a referral that is sold, returned to and then cancelled leaves nothing payable', async () => {
    const docs = storeWith();
    await commit(docs);
    await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON);
    await deliverQueuedMessages(docs);
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    const { gateway } = gatewayOver(docs);
    const reversal = await (0, affiliate_sale_commit_js_1.reverseReferralSale)(gateway, {
        merchantId: MERCHANT,
        saleId,
        cancelledAt: NOW + 10 * DAY,
        actorId: 'u1',
    });
    strict_1.default.equal(reversal.status, 'reversed');
    strict_1.default.equal(reversal.attribution_cancelled, true);
    // §13: a cancelled sale never leaves a PENDING or APPROVED reward behind.
    for (const path of docsUnder(docs, MERCHANT, 'affiliate_rewards')) {
        const status = docs.get(path)?.status;
        strict_1.default.ok(status !== 'PENDING' && status !== 'APPROVED', `${path} is still ${String(status)} after the sale was cancelled`);
    }
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.attribution(MERCHANT, ATTRIBUTION_ID))?.status, 'CANCELLED');
    // The code stays spent: cancelling is not a way around a usage limit.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 1);
});
(0, node_test_1.default)('a cancellation that cannot take back a paid reward raises it for a person instead', async () => {
    const docs = storeWith();
    await commit(docs);
    docs.set(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID), {
        ...docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID)),
        status: 'PAID',
        paid_at: NOW + DAY,
    });
    const saleId = affiliate_engine_js_1.affiliateIds.sale(DEVICE, 'l1');
    const { gateway } = gatewayOver(docs);
    const reversal = await (0, affiliate_sale_commit_js_1.reverseReferralSale)(gateway, {
        merchantId: MERCHANT,
        saleId,
        cancelledAt: NOW + 2 * DAY,
        actorId: 'u1',
    });
    strict_1.default.deepEqual(reversal.rewards_cancelled, []);
    strict_1.default.deepEqual(reversal.rewards_needing_review, [FIRST_REWARD_ID]);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.reward(MERCHANT, FIRST_REWARD_ID))?.status, 'PAID');
    const signal = docs.get(affiliate_sale_commit_js_1.referralPaths.fraudSignal(MERCHANT, affiliate_engine_js_1.affiliateIds.fraudSignal(MERCHANT, 'PAID_REWARD_SALE_CANCELLED', FIRST_REWARD_ID)));
    strict_1.default.equal(signal?.requires_manual_review, true);
});
/* ===================================================== crossing businesses */
(0, node_test_1.default)("another business's code is not found, and nothing about it leaks", async () => {
    const docs = storeWith();
    // The code exists — it just belongs to somebody else.
    docs.set(affiliate_sale_commit_js_1.referralPaths.codeLookup(CODE), {
        code: CODE,
        merchant_id: OTHER_MERCHANT,
        affiliate_id: 'af9',
        code_id: 'ac9',
    });
    docs.set(affiliate_sale_commit_js_1.referralPaths.code(OTHER_MERCHANT, 'ac9'), {
        id: 'ac9',
        merchant_id: OTHER_MERCHANT,
        affiliate_id: 'af9',
        status: 'ACTIVE',
        starts_at: NOW - DAY,
        expires_at: NOW + DAY,
        usage_count: 0,
        first_visit_only: true,
        benefit_type: 'FIXED_AMOUNT',
        benefit_value: 50,
    });
    const outcome = await commit(docs);
    strict_1.default.equal(outcome.status, 'rejected');
    if (outcome.status !== 'rejected')
        return;
    strict_1.default.equal(outcome.reason, 'CODE_NOT_FOUND');
    strict_1.default.equal(outcome.message, affiliate_contracts_js_1.REFERRAL_REASON_MESSAGE.CODE_NOT_FOUND);
    // Not "disabled", not "expired": a distinguishable answer is an oracle for
    // probing another business's codes.
    strict_1.default.doesNotMatch(outcome.message, new RegExp(OTHER_MERCHANT));
    strict_1.default.doesNotMatch(outcome.message, /af9|ac9/);
    // The other business's code is untouched and nothing was written into it.
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(OTHER_MERCHANT, 'ac9'))?.usage_count, 0);
    strict_1.default.deepEqual(docsUnder(docs, OTHER_MERCHANT, 'affiliate_attributions'), []);
    strict_1.default.deepEqual(docsUnder(docs, OTHER_MERCHANT, 'affiliate_events'), []);
    strict_1.default.deepEqual(docsUnder(docs, MERCHANT, 'affiliate_attributions'), []);
});
/* ================================================== the transaction itself */
(0, node_test_1.default)('a failure partway through a referred sale leaves the business exactly as it was', async () => {
    const docs = storeWith();
    const before = snapshot(docs);
    await strict_1.default.rejects(() => commit(docs, {}, config(), { failAfterWrites: 3 }), /injected transaction failure/);
    strict_1.default.deepEqual(snapshot(docs), before, 'a partial commit reached the store');
    // And the retry after the rollback is a first commit, not a replay.
    const retry = await commit(docs);
    strict_1.default.equal(retry.status, 'committed');
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_rewards').length, 1);
});
(0, node_test_1.default)('a failure partway through an offline reconciliation leaves the queue free to retry', async () => {
    const docs = storeWith();
    const before = snapshot(docs);
    const { gateway } = gatewayOver(docs, { failAfterWrites: 2 });
    await strict_1.default.rejects(() => (0, affiliate_offline_sale_js_1.commitOfflineReferralSale)(gateway, offlineInput(), () => config()), /injected transaction failure/);
    strict_1.default.deepEqual(snapshot(docs), before);
    const retry = await reconcile(docs);
    strict_1.default.equal(retry.status, 'committed');
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_attributions').length, 1);
});
/* ================================================= many sales, one backlog */
(0, node_test_1.default)('a backlog of offline sales reaches the server once each, and the limit stops the rest', async () => {
    const docs = storeWith({ code: { usage_limit: 3 } });
    // Five customers, five queued sales, one code that only three may use.
    for (let index = 0; index < 5; index++) {
        docs.set(affiliate_sale_commit_js_1.referralPaths.customer(MERCHANT, `c${index}`), {
            id: `c${index}`,
            merchant_id: MERCHANT,
            name: `Cliente ${index}`,
            phone: `+2588412345${String(index).padStart(2, '0')}`,
            confirmed_points: 0,
        });
    }
    const statuses = [];
    for (let index = 0; index < 5; index++) {
        const outcome = await reconcile(docs, {
            customerId: `c${index}`,
            customerPhoneE164: `+2588412345${String(index).padStart(2, '0')}`,
            localSaleId: `l${index}`,
        });
        statuses.push(outcome.status);
    }
    // Processed in the order the server received them; the later ones lose.
    strict_1.default.deepEqual(statuses, [
        'committed',
        'committed',
        'committed',
        'rejected',
        'rejected',
    ]);
    strict_1.default.equal(docs.get(affiliate_sale_commit_js_1.referralPaths.code(MERCHANT, 'ac1'))?.usage_count, 3);
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'affiliate_rewards').length, 3);
    // Every one of the five sales is on the books, refused or not.
    strict_1.default.equal(docsUnder(docs, MERCHANT, 'sales').length, 5);
    // Replaying the whole backlog changes nothing.
    const afterFirstPass = snapshot(docs);
    for (let index = 0; index < 5; index++) {
        await reconcile(docs, {
            customerId: `c${index}`,
            customerPhoneE164: `+2588412345${String(index).padStart(2, '0')}`,
            localSaleId: `l${index}`,
        });
    }
    strict_1.default.deepEqual(snapshot(docs), afterFirstPass);
});
/* ============================================================== no secrets */
(0, node_test_1.default)('nothing a scenario writes carries a phone number a person could dial', async () => {
    const docs = storeWith();
    await commit(docs);
    await secondVisit(docs, NOW + 7 * DAY, RETURNS_ON);
    // The customer and affiliate records hold phones by design; every record the
    // referral feature writes about them must not.
    const owned = [
        'affiliate_attributions',
        'affiliate_rewards',
        'affiliate_events',
        'affiliate_fraud_signals',
        'affiliate_outbox',
    ];
    for (const collection of owned) {
        for (const path of docsUnder(docs, MERCHANT, collection)) {
            const serialized = JSON.stringify(docs.get(path));
            strict_1.default.doesNotMatch(serialized, /841234567|840000001/, `${path} carries a reachable number`);
            strict_1.default.ok(!path.includes('841234567'), `${path} is keyed by a phone number`);
        }
    }
});
