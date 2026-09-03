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
exports.MERCHANT_SCAN_CAP = void 0;
exports.listCustomers = listCustomers;
exports.getCustomer = getCustomer;
exports.listCustomerSales = listCustomerSales;
exports.listCatalog = listCatalog;
exports.listRewards = listRewards;
exports.listTeam = listTeam;
const admin = __importStar(require("firebase-admin"));
const merchant_records_js_1 = require("./merchant_records.js");
/**
 * Reading one business's own operational records.
 *
 * Every function here takes a merchantId the caller has *already* been
 * authorized for — `businessForRequest` in index.ts does that, over
 * `merchant_access.ts`. Nothing in this file re-derives access, and nothing in
 * it accepts a merchantId straight from a query string.
 *
 * The console deliberately has no customer directory: it can look one up by
 * phone and no more, so internal staff cannot enumerate the customer base. A
 * business listing *its own* customers is a different question with a
 * different answer — the mobile app already syncs this exact subcollection
 * down to the till, and `firestore.rules` allows the owner to read all of it.
 */
const db = () => admin.firestore();
/**
 * How many documents one subcollection read will pull.
 *
 * Past this the answer would be incomplete, so `truncated` says so and the
 * screen prints it rather than showing a short list as if it were the whole
 * one.
 */
exports.MERCHANT_SCAN_CAP = 2000;
async function readSubcollection(merchantId, collectionId) {
    const snapshot = await db()
        .collection('businesses')
        .doc(merchantId)
        .collection(collectionId)
        .limit(exports.MERCHANT_SCAN_CAP + 1)
        .get();
    const truncated = snapshot.size > exports.MERCHANT_SCAN_CAP;
    const docs = truncated ? snapshot.docs.slice(0, exports.MERCHANT_SCAN_CAP) : snapshot.docs;
    return {
        docs: docs.map((doc) => ({
            id: doc.id,
            data: (doc.data() ?? {}),
        })),
        truncated,
    };
}
async function listCustomers(merchantId, query) {
    const { docs, truncated } = await readSubcollection(merchantId, 'customers');
    const rows = docs.map((doc) => (0, merchant_records_js_1.toCustomer)(doc.id, doc.data));
    return { ...(0, merchant_records_js_1.selectCustomers)(rows, query), truncated };
}
async function getCustomer(merchantId, customerId) {
    const snapshot = await db()
        .collection('businesses')
        .doc(merchantId)
        .collection('customers')
        .doc(customerId)
        .get();
    if (!snapshot.exists)
        return null;
    return (0, merchant_records_js_1.toCustomer)(snapshot.id, (snapshot.data() ?? {}));
}
/**
 * The customer's recent visits.
 *
 * Sales carry the customer id rather than living under them, so this is a
 * filtered query on one business's own sales — a single equality on
 * `customer_id`, which is the one filter Firestore serves without a composite
 * index as long as nothing else is ordered alongside it. Sorting happens here.
 */
async function listCustomerSales(merchantId, customerId, limit = 20) {
    const snapshot = await db()
        .collection('businesses')
        .doc(merchantId)
        .collection('sales')
        .where('customer_id', '==', customerId)
        .limit(200)
        .get();
    return snapshot.docs
        .map((doc) => {
        const data = (doc.data() ?? {});
        const at = data.created_at;
        return {
            id: doc.id,
            amount: typeof data.amount === 'number' ? data.amount : null,
            points: typeof data.points === 'number' ? data.points : null,
            created_at: typeof at === 'number' && at > 0 ? at : null,
            // Carried through because a cancelled sale is still a row in this
            // collection: showing it as a plain visit would overstate the history.
            cancellation_status: typeof data.cancellation_status === 'string'
                ? data.cancellation_status
                : null,
            confirmation_status: typeof data.confirmation_status === 'string'
                ? data.confirmation_status
                : null,
        };
    })
        .sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0))
        .slice(0, limit);
}
async function listCatalog(merchantId, query) {
    const { docs, truncated } = await readSubcollection(merchantId, 'merchant_items');
    const rows = docs.map((doc) => (0, merchant_records_js_1.toCatalogItem)(doc.id, doc.data));
    return { ...(0, merchant_records_js_1.selectCatalog)(rows, query), truncated };
}
async function listRewards(merchantId, query) {
    const { docs, truncated } = await readSubcollection(merchantId, 'rewards');
    const rows = docs.map((doc) => (0, merchant_records_js_1.toReward)(doc.id, doc.data));
    return { ...(0, merchant_records_js_1.selectRewards)(rows, query), truncated };
}
async function listTeam(merchantId, query) {
    const { docs, truncated } = await readSubcollection(merchantId, 'app_users');
    const rows = docs.map((doc) => (0, merchant_records_js_1.toStaff)(doc.id, doc.data));
    return { ...(0, merchant_records_js_1.selectStaff)(rows, query), truncated };
}
