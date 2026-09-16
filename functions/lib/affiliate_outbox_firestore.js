"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.firestoreOutboxStore = void 0;
exports.createFirestoreOutboxContextResolver = createFirestoreOutboxContextResolver;
exports.setWhatsAppAdapter = setWhatsAppAdapter;
exports.resolveWhatsAppAdapter = resolveWhatsAppAdapter;
const admin = __importStar(require("firebase-admin"));
const affiliate_store_js_1 = require("./affiliate_store.js");
const affiliate_engine_js_1 = require("./affiliate_engine.js");
const affiliate_outbox_js_1 = require("./affiliate_outbox.js");
/**
 * The outbox worker, bound to Firestore, and the one place a WhatsApp provider
 * would be plugged in.
 *
 * `affiliate_outbox.ts` decides; this file knows where the documents are. The
 * split is the same one the sale commit uses, and for the same reason: the
 * claim race and the retry state machine are testable against a fake store,
 * and nothing in the adapter below can disagree with them because it makes no
 * decisions.
 *
 * ── The provider gap ────────────────────────────────────────────────────────
 *
 * There is no WhatsApp provider in this repository: no credentials, no webhook
 * for delivery receipts, no opt-in policy agreed with a provider, and no HTTP
 * integration convention anywhere in `functions/` to copy. Inventing one — a
 * URL and a token read from the environment, a body shape guessed at — would
 * produce code nobody can test against the real thing and a message format
 * that is probably wrong.
 *
 * So the boundary is explicit and empty. `resolveWhatsAppAdapter()` returns
 * null, delivery answers `not_configured`, and the row stays claimable without
 * burning a retry or claiming success. When a provider is chosen, one call to
 * `setWhatsAppAdapter` at startup is the whole integration, and the backlog
 * sends itself on the next sweep.
 *
 * Manual sharing is unaffected: the merchant app's `url_launcher` share sheet
 * is a separate path that needs none of this.
 */
const db = () => admin.firestore();
const outboxRef = (merchantId, outboxId) => db()
    .collection('businesses')
    .doc(merchantId)
    .collection('affiliate_outbox')
    .doc(outboxId);
/* ------------------------------------------------------------------- store */
exports.firestoreOutboxStore = {
    runTransaction(run) {
        return db().runTransaction((transaction) => run({
            async get(merchantId, outboxId) {
                const snapshot = await transaction.get(outboxRef(merchantId, outboxId));
                return snapshot.exists ? (snapshot.data() ?? {}) : null;
            },
            update(merchantId, outboxId, patch) {
                transaction.set(outboxRef(merchantId, outboxId), patch, { merge: true });
            },
        }));
    },
    /**
     * The due backlog, bounded and ordered by when it became due.
     *
     * Scoped to one business when the caller names one — which the trigger and
     * the per-merchant sweep both do — and a collection group query otherwise.
     * Both are covered by the composite indexes on (status, next_attempt_at);
     * neither ever reads a terminal row.
     */
    async listPending(input) {
        const base = input.merchantId === null
            ? db().collectionGroup('affiliate_outbox')
            : db()
                .collection('businesses')
                .doc(input.merchantId)
                .collection('affiliate_outbox');
        const snapshot = await base
            .where('status', 'in', affiliate_outbox_js_1.CLAIMABLE_STATUSES)
            .where('next_attempt_at', '<=', input.now)
            .orderBy('next_attempt_at', 'asc')
            .limit(input.limit)
            .get();
        return snapshot.docs.map((doc) => {
            const data = (doc.data() ?? {});
            const merchantId = typeof data.merchant_id === 'string' && data.merchant_id.trim() !== ''
                ? data.merchant_id.trim()
                : // businesses/{merchantId}/affiliate_outbox/{id}
                    (doc.ref.parent.parent?.id ?? '');
            return { merchantId, id: doc.id, data };
        });
    },
};
/* ----------------------------------------------------------------- context */
function str(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'string' && value.trim() !== '')
            return value.trim();
    }
    return null;
}
function points(payload) {
    for (const key of ['reward_points', 'points']) {
        const value = payload[key];
        if (typeof value === 'number' && Number.isFinite(value))
            return value;
    }
    return 0;
}
/**
 * Reads what the message needs, after the sale that caused it committed.
 *
 * Nothing is taken from the queued row except the ids it was written with: the
 * number, the shop's name and the reward's current status are read from the
 * merchant's own documents at delivery time. That is what makes it impossible
 * for a till to choose who gets a message or what it says, and what keeps a
 * reward approved five minutes ago from being announced as still waiting.
 */
function createFirestoreOutboxContextResolver(options) {
    return async (record) => {
        const businessSnapshot = await db()
            .collection('businesses')
            .doc(record.merchantId)
            .get();
        const business = (businessSnapshot.data() ?? {});
        const config = (0, affiliate_store_js_1.affiliateConfigFrom)(business);
        const merchantName = str(business, 'merchant_name', 'name', 'business_name');
        const context = {
            merchantName,
            notificationsEnabled: config.notificationsEnabled,
            recipientPhoneE164: null,
            blockedReason: null,
            points: points(record.payload),
            rewardStatus: str(record.payload, 'reward_status'),
        };
        // A merchant who switched notifications off is answered before anybody's
        // number is read at all.
        if (!config.notificationsEnabled)
            return context;
        if (record.template === 'customer_referral_thanks') {
            const customerId = str(record.payload, 'customer_id');
            if (customerId === null)
                return context;
            const snapshot = await db()
                .collection('businesses')
                .doc(record.merchantId)
                .collection('customers')
                .doc(customerId)
                .get();
            const customer = (snapshot.data() ?? {});
            // The same consent gate the notification queue enforces: an automated
            // message to a customer who never agreed to one is not ours to send.
            if (str(customer, 'whatsapp_consent_status')?.toUpperCase() !== 'GRANTED') {
                return { ...context, blockedReason: 'consent_missing' };
            }
            return {
                ...context,
                recipientPhoneE164: options.normalizePhone(str(customer, 'phone_e164', 'phone')),
            };
        }
        if (record.affiliateId === null)
            return context;
        const linkId = affiliate_engine_js_1.affiliateIds.link(record.affiliateId, record.merchantId);
        const [affiliateSnapshot, linkSnapshot] = await Promise.all([
            db().collection('affiliates').doc(record.affiliateId).get(),
            db()
                .collection('businesses')
                .doc(record.merchantId)
                .collection('affiliate_merchants')
                .doc(linkId)
                .get(),
        ]);
        const affiliate = (affiliateSnapshot.data() ?? {});
        const link = (linkSnapshot.data() ?? {});
        // Both the platform identity and this business's relationship must be
        // active. A merchant deactivates the link, not the global identity.
        const affiliateStatus = str(affiliate, 'status')?.toUpperCase() ?? 'INACTIVE';
        const linkStatus = str(link, 'status')?.toUpperCase() ?? 'INACTIVE';
        if (!affiliateSnapshot.exists ||
            !linkSnapshot.exists ||
            affiliateStatus !== 'ACTIVE' ||
            linkStatus !== 'ACTIVE') {
            return { ...context, blockedReason: 'affiliate_inactive' };
        }
        return {
            ...context,
            recipientPhoneE164: options.normalizePhone(str(affiliate, 'phone_e164', 'phone')),
            rewardStatus: await currentRewardStatus(record, context.rewardStatus),
        };
    };
}
/**
 * The reward's status as it is now, not as it was when the row was queued.
 *
 * Falls back to the queued value when the reward cannot be located, and the
 * fallback for that is `PENDING` — the direction that can only ever understate
 * the news. Telling an affiliate their points are approved when a merchant has
 * not agreed is the one mistake this feature cannot make.
 */
async function currentRewardStatus(record, queued) {
    const rewardId = str(record.payload, 'reward_id') ??
        rewardIdFromAttribution(record, str(record.payload, 'attribution_id'));
    if (rewardId === null)
        return queued;
    const snapshot = await db()
        .collection('businesses')
        .doc(record.merchantId)
        .collection('affiliate_rewards')
        .doc(rewardId)
        .get();
    if (!snapshot.exists)
        return queued;
    return str((snapshot.data() ?? {}), 'status') ?? queued;
}
function rewardIdFromAttribution(record, attributionId) {
    if (attributionId === null)
        return null;
    return affiliate_engine_js_1.affiliateIds.reward(attributionId, record.template === 'affiliate_customer_returned'
        ? 'CUSTOMER_RETURN'
        : 'FIRST_QUALIFYING_SALE');
}
/* ----------------------------------------------------------------- adapter */
let configuredAdapter = null;
/**
 * Installs a provider.
 *
 * The hook exists so that wiring one is a single call at startup rather than
 * an edit spread through the worker — and so that the day it happens, nothing
 * about claiming, backoff or masking has to be revisited.
 */
function setWhatsAppAdapter(adapter) {
    configuredAdapter = adapter;
}
/**
 * The provider in force, which is none.
 *
 * Returning null is a deliberate answer, not an oversight: see the note at the
 * top of this file. Operational configuration — credentials, the template
 * approval a provider requires, the delivery-receipt webhook — is documented
 * when a provider is actually chosen.
 */
function resolveWhatsAppAdapter() {
    return configuredAdapter;
}
