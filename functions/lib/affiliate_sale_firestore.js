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
exports.firestoreReferralSaleGateway = void 0;
exports.commitReferralSaleToFirestore = commitReferralSaleToFirestore;
exports.reverseReferralSaleInFirestore = reverseReferralSaleInFirestore;
exports.recordReferredCustomerReturnInFirestore = recordReferredCustomerReturnInFirestore;
const admin = __importStar(require("firebase-admin"));
const affiliate_store_js_1 = require("./affiliate_store.js");
const affiliate_sale_commit_js_1 = require("./affiliate_sale_commit.js");
/**
 * The referral sale commands, bound to Firestore.
 *
 * `affiliate_sale_commit.ts` decides; this file is the only thing that knows
 * the decision lands in Firestore. The split is not decoration: the commit is
 * one transaction with seven writes in it, and a test that needed an emulator
 * to check "either all of them or none" would not be run often enough to
 * matter. With the ports here, the decision is tested against a fake that can
 * fail halfway through on purpose.
 *
 * The adapter is deliberately thin. It translates a path to a reference and a
 * query to a `where`, and does nothing else — no defaults, no retries, no
 * field mapping — so there is nothing in it that can disagree with the plan.
 */
const db = () => admin.firestore();
function refFor(path) {
    return db().doc(path);
}
function transactionPorts(transaction) {
    return {
        async getDoc(path) {
            const snapshot = await transaction.get(refFor(path));
            return snapshot.exists ? (snapshot.data() ?? {}) : null;
        },
        async queryDocs(collectionPath, field, value, limit) {
            const snapshot = await transaction.get(db().collection(collectionPath).where(field, '==', value).limit(limit));
            return snapshot.docs.map((doc) => ({
                id: doc.id,
                data: (doc.data() ?? {}),
            }));
        },
        create(path, data) {
            transaction.create(refFor(path), data);
        },
        merge(path, data) {
            transaction.set(refFor(path), data, { merge: true });
        },
    };
}
exports.firestoreReferralSaleGateway = {
    runTransaction(run) {
        return db().runTransaction((transaction) => run(transactionPorts(transaction)));
    },
};
/** The authoritative commit, as a route may call it. */
async function commitReferralSaleToFirestore(input) {
    return (0, affiliate_sale_commit_js_1.commitReferralSale)(exports.firestoreReferralSaleGateway, input, (business) => (0, affiliate_store_js_1.affiliateConfigFrom)((business ?? {})));
}
/** The reversal the sale-cancellation path calls once a sale is cancelled. */
async function reverseReferralSaleInFirestore(input) {
    return (0, affiliate_sale_commit_js_1.reverseReferralSale)(exports.firestoreReferralSaleGateway, input);
}
/**
 * The return hook, called from the sale the business already processes.
 *
 * Reads the business settings outside the transaction on purpose: nothing
 * about a return is a race — the reward is keyed by attribution and type, so a
 * stale setting can at worst create a reward the merchant has since switched
 * off, which is a queued approval they can refuse.
 */
async function recordReferredCustomerReturnInFirestore(input) {
    const business = await db().collection('businesses').doc(input.merchantId).get();
    const config = (0, affiliate_store_js_1.affiliateConfigFrom)((business.data() ?? {}));
    // Every sale in the product reaches this hook, and almost none of them
    // belong to a business that has affiliates at all. One document read is the
    // cheap way to stop; it also means a business that switches the feature off
    // stops accruing return rewards, which is what switching it off means.
    if (!config.enabled) {
        return { status: 'not_referred', reward_id: null };
    }
    return (0, affiliate_sale_commit_js_1.recordReferredCustomerReturn)(exports.firestoreReferralSaleGateway, input, config);
}
