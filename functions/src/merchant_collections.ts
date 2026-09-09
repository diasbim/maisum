import * as admin from 'firebase-admin';

import {
  capDocuments,
  selectCatalog,
  selectCustomers,
  selectRewards,
  selectStaff,
  sortSales,
  toCatalogItem,
  toCustomer,
  toReward,
  toSale,
  toStaff,
  type CatalogItemRecord,
  type CustomerRecord,
  type RecordPage,
  type RecordQuery,
  type RewardRecord,
  type SaleRecord,
  type StaffRecord,  matchesSearch,
  paginate,
  selectByRecency,
  toAppointment,
  toLedgerEntry,
  toRedemption,
  toRecoveryTask,
  toReturnBonus,
  toRiskScore,
  toSaleListItem,
  toSurvey,
  toUsageBalance,
  toVisitReport,
  totalSales,
  type AppointmentRecord,
  type LedgerEntryRecord,
  type RedemptionRecord,
  type RecoveryTaskRecord,
  type ReturnBonusRecord,
  type RiskScoreRecord,
  type SaleListRecord,
  type SalesTotals,
  type SurveyRecord,
  type UsageBalanceRecord,
  type VisitReportRecord,
} from './merchant_records.js';

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
export const MERCHANT_SCAN_CAP = 2000;

export type MerchantPage<T> = RecordPage<T> & { truncated: boolean };

async function readSubcollection(
  merchantId: string,
  collectionId: string,
): Promise<{
  docs: Array<{ id: string; data: Record<string, unknown> }>;
  truncated: boolean;
}> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection(collectionId)
    // One past the cap, so that a collection sitting exactly on it is not
    // reported as incomplete.
    .limit(MERCHANT_SCAN_CAP + 1)
    .get();

  const capped = capDocuments(snapshot.docs, MERCHANT_SCAN_CAP);

  return {
    docs: capped.docs.map((doc) => ({
      id: doc.id,
      data: (doc.data() ?? {}) as Record<string, unknown>,
    })),
    truncated: capped.truncated,
  };
}

export async function listCustomers(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<CustomerRecord>> {
  const { docs, truncated } = await readSubcollection(merchantId, 'customers');
  const rows = docs.map((doc) => toCustomer(doc.id, doc.data));
  return { ...selectCustomers(rows, query), truncated };
}

export async function getCustomer(
  merchantId: string,
  customerId: string,
): Promise<CustomerRecord | null> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection('customers')
    .doc(customerId)
    .get();
  if (!snapshot.exists) return null;
  return toCustomer(snapshot.id, (snapshot.data() ?? {}) as Record<string, unknown>);
}

/**
 * The customer's recent visits.
 *
 * Sales carry the customer id rather than living under them, so this is a
 * filtered query on one business's own sales — a single equality on
 * `customer_id`, which is the one filter Firestore serves without a composite
 * index as long as nothing else is ordered alongside it. Sorting happens here.
 */
export async function listCustomerSales(
  merchantId: string,
  customerId: string,
  limit = 20,
): Promise<SaleRecord[]> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection('sales')
    .where('customer_id', '==', customerId)
    .limit(200)
    .get();

  const rows = snapshot.docs.map((doc) =>
    toSale(doc.id, (doc.data() ?? {}) as Record<string, unknown>),
  );
  return sortSales(rows).slice(0, limit);
}

export async function listCatalog(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<CatalogItemRecord>> {
  const { docs, truncated } = await readSubcollection(merchantId, 'merchant_items');
  const rows = docs.map((doc) => toCatalogItem(doc.id, doc.data));
  return { ...selectCatalog(rows, query), truncated };
}

export async function listRewards(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<RewardRecord>> {
  const { docs, truncated } = await readSubcollection(merchantId, 'rewards');
  const rows = docs.map((doc) => toReward(doc.id, doc.data));
  return { ...selectRewards(rows, query), truncated };
}

export async function listTeam(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<StaffRecord>> {
  const { docs, truncated } = await readSubcollection(merchantId, 'app_users');
  const rows = docs.map((doc) => toStaff(doc.id, doc.data));
  return { ...selectStaff(rows, query), truncated };
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

async function pagina<T extends { id: string }>(
  merchantId: string,
  colecao: string,
  para: (id: string, data: Record<string, unknown>) => T,
  query: RecordQuery,
  ler: Parameters<typeof selectByRecency<T>>[2],
): Promise<MerchantPage<T>> {
  const { docs, truncated } = await readSubcollection(merchantId, colecao);
  const rows = docs.map((doc) => para(doc.id, doc.data));
  return { ...selectByRecency(rows, query, ler), truncated };
}

export function listSales(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'sales', toSaleListItem, query, {
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
export async function totalsForSales(
  merchantId: string,
  query: RecordQuery,
): Promise<SalesTotals> {
  const { docs } = await readSubcollection(merchantId, 'sales');
  const rows = docs.map((doc) => toSaleListItem(doc.id, doc.data));
  const status = (query.status ?? '').trim().toUpperCase();
  return totalSales(
    status === ''
      ? rows
      : rows.filter(
          (row) => (row.confirmation_status ?? '').toUpperCase() === status,
        ),
  );
}

export function listRedemptions(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'redemptions', toRedemption, query, {
    time: (row) => row.redeemed_at,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id, row.reward_id],
  });
}

export function listAppointments(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'appointments', toAppointment, query, {
    time: (row) => row.scheduled_date,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id],
  });
}

export function listReturnBonuses(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'return_bonuses', toReturnBonus, query, {
    time: (row) => row.issued_at,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id],
  });
}

export function listRecoveryTasks(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'recovery_tasks', toRecoveryTask, query, {
    time: (row) => row.due_at ?? row.created_at,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id, row.notes],
  });
}

export function listVisitReports(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'visit_reports', toVisitReport, query, {
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
export async function listRiskScores(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<RiskScoreRecord>> {
  const { docs, truncated } = await readSubcollection(
    merchantId,
    'customer_risk_scores',
  );
  const rows = docs.map((doc) => toRiskScore(doc.id, doc.data));

  const status = (query.status ?? '').trim().toUpperCase();
  const filtered = rows.filter(
    (row) => status === '' || (row.risk_level ?? '').toUpperCase() === status,
  );
  const sorted = [...filtered].sort((a, b) => {
    const byPriority = b.priority - a.priority;
    if (byPriority !== 0) return byPriority;
    const byDays = b.days_since_visit - a.days_since_visit;
    return byDays !== 0 ? byDays : a.id.localeCompare(b.id);
  });

  return { ...paginate(sorted, query), truncated };
}

/** One customer's points, as the ledger recorded them. */
export async function listCustomerLedger(
  merchantId: string,
  customerId: string,
  limit = 25,
): Promise<LedgerEntryRecord[]> {
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
    .map((doc) => toLedgerEntry(doc.id, (doc.data() ?? {}) as Record<string, unknown>))
    .sort((a, b) => (b.occurred_at ?? 0) - (a.occurred_at ?? 0))
    .slice(0, limit);
}

/** What the plan has actually consumed, against what it allows. */
export async function listUsageBalances(
  merchantId: string,
): Promise<UsageBalanceRecord[]> {
  const { docs } = await readSubcollection(merchantId, 'usage_balances');
  return docs
    .map((doc) => toUsageBalance(doc.id, doc.data))
    .sort((a, b) => (a.metric_key ?? '').localeCompare(b.metric_key ?? ''));
}

/**
 * The surveys, each with how many people answered.
 *
 * The count is the only reason a survey list is worth opening — a survey
 * nobody answered and a survey answered two hundred times look identical
 * without it. Responses are one more capped read, joined in memory.
 */
export async function listSurveys(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<SurveyRecord>> {
  const [surveys, responses] = await Promise.all([
    readSubcollection(merchantId, 'surveys'),
    readSubcollection(merchantId, 'survey_responses'),
  ]);

  const counts = new Map<string, number>();
  for (const doc of responses.docs) {
    const surveyId = doc.data.survey_id ?? doc.data.surveyId;
    if (typeof surveyId === 'string') {
      counts.set(surveyId, (counts.get(surveyId) ?? 0) + 1);
    }
  }

  const rows = surveys.docs.map((doc) => {
    const survey = toSurvey(doc.id, doc.data);
    return { ...survey, response_count: counts.get(survey.id) ?? 0 };
  });

  const search = (query.search ?? '').trim();
  const status = (query.status ?? '').trim().toUpperCase();
  const filtered = rows.filter((row) => {
    if (search !== '' && !matchesSearch([row.title, row.description], search)) {
      return false;
    }
    if (status === 'ACTIVE' && row.is_active === false) return false;
    if (status === 'INACTIVE' && row.is_active !== false) return false;
    return true;
  });
  const sorted = [...filtered].sort(
    (a, b) => (b.created_at ?? 0) - (a.created_at ?? 0),
  );

  return {
    ...paginate(sorted, query),
    truncated: surveys.truncated || responses.truncated,
  };
}
