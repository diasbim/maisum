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
exports.listSales = listSales;
exports.totalsForSales = totalsForSales;
exports.listRedemptions = listRedemptions;
exports.listAppointments = listAppointments;
exports.listReturnBonuses = listReturnBonuses;
exports.listRecoveryTasks = listRecoveryTasks;
exports.listVisitReports = listVisitReports;
exports.listRiskScores = listRiskScores;
exports.listCustomerLedger = listCustomerLedger;
exports.listUsageBalances = listUsageBalances;
exports.listSurveys = listSurveys;
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
        // One past the cap, so that a collection sitting exactly on it is not
        // reported as incomplete.
        .limit(exports.MERCHANT_SCAN_CAP + 1)
        .get();
    const capped = (0, merchant_records_js_1.capDocuments)(snapshot.docs, exports.MERCHANT_SCAN_CAP);
    return {
        docs: capped.docs.map((doc) => ({
            id: doc.id,
            data: (doc.data() ?? {}),
        })),
        truncated: capped.truncated,
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
    const rows = snapshot.docs.map((doc) => (0, merchant_records_js_1.toSale)(doc.id, (doc.data() ?? {})));
    return (0, merchant_records_js_1.sortSales)(rows).slice(0, limit);
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
/* --------------------------------------------- the surfaces that were absent */
/**
 * The subcollections the portal never read.
 *
 * Same shape as everything above: one capped read, normalised, filtered in
 * memory. The cap is what keeps a busy business honest — `truncated` reaches
 * the screen and the screen says so, rather than serving a short list as if it
 * were the whole one.
 */
async function pagina(merchantId, colecao, para, query, ler) {
    const { docs, truncated } = await readSubcollection(merchantId, colecao);
    const rows = docs.map((doc) => para(doc.id, doc.data));
    return { ...(0, merchant_records_js_1.selectByRecency)(rows, query, ler), truncated };
}
function listSales(merchantId, query) {
    return pagina(merchantId, 'sales', merchant_records_js_1.toSaleListItem, query, {
        time: (row) => row.created_at,
        status: (row) => row.confirmation_status,
        search: (row) => [row.id, row.customer_id],
    });
}
/**
 * Every sale, for the totals.
 *
 * The list is paged, so summing its page would tell a business what it took
 * in on page one — a number that changes when you click "seguinte", which is
 * worse than no number. The totals are computed over the whole read.
 */
async function totalsForSales(merchantId, query) {
    const { docs } = await readSubcollection(merchantId, 'sales');
    const rows = docs.map((doc) => (0, merchant_records_js_1.toSaleListItem)(doc.id, doc.data));
    const status = (query.status ?? '').trim().toUpperCase();
    return (0, merchant_records_js_1.totalSales)(status === ''
        ? rows
        : rows.filter((row) => (row.confirmation_status ?? '').toUpperCase() === status));
}
function listRedemptions(merchantId, query) {
    return pagina(merchantId, 'redemptions', merchant_records_js_1.toRedemption, query, {
        time: (row) => row.redeemed_at,
        status: (row) => row.status,
        search: (row) => [row.id, row.customer_id, row.reward_id],
    });
}
function listAppointments(merchantId, query) {
    return pagina(merchantId, 'appointments', merchant_records_js_1.toAppointment, query, {
        time: (row) => row.scheduled_date,
        status: (row) => row.status,
        search: (row) => [row.id, row.customer_id],
    });
}
function listReturnBonuses(merchantId, query) {
    return pagina(merchantId, 'return_bonuses', merchant_records_js_1.toReturnBonus, query, {
        time: (row) => row.issued_at,
        status: (row) => row.status,
        search: (row) => [row.id, row.customer_id],
    });
}
function listRecoveryTasks(merchantId, query) {
    return pagina(merchantId, 'recovery_tasks', merchant_records_js_1.toRecoveryTask, query, {
        time: (row) => row.due_at ?? row.created_at,
        status: (row) => row.status,
        search: (row) => [row.id, row.customer_id, row.notes],
    });
}
function listVisitReports(merchantId, query) {
    return pagina(merchantId, 'visit_reports', merchant_records_js_1.toVisitReport, query, {
        time: (row) => row.visited_at,
        status: (row) => row.result,
        search: (row) => [row.id, row.customer_id, row.notes],
    });
}
/**
 * The risk board, highest priority first.
 *
 * The one list here that is not "newest first": a retention screen exists to
 * be worked top to bottom, and the newest score is not the most urgent one.
 */
async function listRiskScores(merchantId, query) {
    const { docs, truncated } = await readSubcollection(merchantId, 'customer_risk_scores');
    const rows = docs.map((doc) => (0, merchant_records_js_1.toRiskScore)(doc.id, doc.data));
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => status === '' || (row.risk_level ?? '').toUpperCase() === status);
    const sorted = [...filtered].sort((a, b) => {
        const byPriority = b.priority - a.priority;
        if (byPriority !== 0)
            return byPriority;
        const byDays = b.days_since_visit - a.days_since_visit;
        return byDays !== 0 ? byDays : a.id.localeCompare(b.id);
    });
    return { ...(0, merchant_records_js_1.paginate)(sorted, query), truncated };
}
/** One customer's points, as the ledger recorded them. */
async function listCustomerLedger(merchantId, customerId, limit = 25) {
    const snapshot = await db()
        .collection('businesses')
        .doc(merchantId)
        .collection('loyalty_ledger')
        .where('customer_id', '==', customerId)
        .limit(200)
        .get();
    // Ordered here rather than in the query: adding orderBy alongside the
    // equality would need a composite index, and this is at most 200 rows.
    return snapshot.docs
        .map((doc) => (0, merchant_records_js_1.toLedgerEntry)(doc.id, (doc.data() ?? {})))
        .sort((a, b) => (b.occurred_at ?? 0) - (a.occurred_at ?? 0))
        .slice(0, limit);
}
/** What the plan has actually consumed, against what it allows. */
async function listUsageBalances(merchantId) {
    const { docs } = await readSubcollection(merchantId, 'usage_balances');
    return docs
        .map((doc) => (0, merchant_records_js_1.toUsageBalance)(doc.id, doc.data))
        .sort((a, b) => (a.metric_key ?? '').localeCompare(b.metric_key ?? ''));
}
/**
 * The surveys, each with how many people answered.
 *
 * The count is the only reason a survey list is worth opening — a survey
 * nobody answered and a survey answered two hundred times look identical
 * without it. Responses are one more capped read, joined in memory.
 */
async function listSurveys(merchantId, query) {
    const [surveys, responses] = await Promise.all([
        readSubcollection(merchantId, 'surveys'),
        readSubcollection(merchantId, 'survey_responses'),
    ]);
    const counts = new Map();
    for (const doc of responses.docs) {
        const surveyId = doc.data.survey_id ?? doc.data.surveyId;
        if (typeof surveyId === 'string') {
            counts.set(surveyId, (counts.get(surveyId) ?? 0) + 1);
        }
    }
    const rows = surveys.docs.map((doc) => {
        const survey = (0, merchant_records_js_1.toSurvey)(doc.id, doc.data);
        return { ...survey, response_count: counts.get(survey.id) ?? 0 };
    });
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' && !(0, merchant_records_js_1.matchesSearch)([row.title, row.description], search)) {
            return false;
        }
        if (status === 'ACTIVE' && row.is_active === false)
            return false;
        if (status === 'INACTIVE' && row.is_active !== false)
            return false;
        return true;
    });
    const sorted = [...filtered].sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0));
    return {
        ...(0, merchant_records_js_1.paginate)(sorted, query),
        truncated: surveys.truncated || responses.truncated,
    };
}
