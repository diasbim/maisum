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
  toSurveyQuestion,
  toSurveyResponse,
  renderSurveyAnswer,
  asString,
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
  type SurveyAnswerRecord,
  type SurveyQuestionRecord,
  type SurveyResponseRecord,
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

/** A row that names a customer by id, and the name once it has been found. */
export type ComCliente = { customer_id?: string | null; customer_name?: string | null };

/**
 * Customer ids to the names an owner recognises.
 *
 * Every list below stores the customer as an id, because that is how the app
 * writes them. On screen that read as `c3` — including on the retention board,
 * whose entire job is to say who to call. The names live one subcollection
 * away, so this is one more capped read joined in memory, the same shape as
 * the response counts on `listSurveys`.
 */
async function nomesDeClientes(merchantId: string): Promise<Map<string, string>> {
  const { docs } = await readSubcollection(merchantId, 'customers');
  const nomes = new Map<string, string>();
  for (const doc of docs) {
    const nome = toCustomer(doc.id, doc.data).name;
    if (nome !== null && nome.trim() !== '') nomes.set(doc.id, nome);
  }
  return nomes;
}

/** The name for a row's customer, or null when there is nothing to show. */
function comNome<T extends ComCliente>(row: T, nomes: Map<string, string>): T {
  const id = row.customer_id ?? null;
  return { ...row, customer_name: id === null ? null : nomes.get(id) ?? null };
}

async function pagina<T extends { id: string } & ComCliente>(
  merchantId: string,
  colecao: string,
  para: (id: string, data: Record<string, unknown>) => T,
  query: RecordQuery,
  ler: Parameters<typeof selectByRecency<T>>[2],
): Promise<MerchantPage<T>> {
  const [{ docs, truncated }, nomes] = await Promise.all([
    readSubcollection(merchantId, colecao),
    nomesDeClientes(merchantId),
  ]);
  // Named before filtering, so that searching a list by "Ana" finds her rows
  // rather than only matching the id nobody knows.
  const rows = docs.map((doc) => comNome(para(doc.id, doc.data), nomes));
  return { ...selectByRecency(rows, query, ler), truncated };
}

export function listSales(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'sales', toSaleListItem, query, {
    time: (row) => row.created_at,
    status: (row) => row.confirmation_status,
    search: (row) => [row.id, row.customer_id, row.customer_name],
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

/**
 * Redemptions, with both names filled in.
 *
 * This list is the one that names two things by id — the customer and the
 * reward they spent points on — so it joins twice. "Ana Matola trocou um Café
 * grátis" is the sentence; `c1` and `r1` are not.
 */
export async function listRedemptions(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<RedemptionRecord>> {
  const [{ docs, truncated }, nomes, recompensas] = await Promise.all([
    readSubcollection(merchantId, 'redemptions'),
    nomesDeClientes(merchantId),
    nomesDeRecompensas(merchantId),
  ]);

  // Both names attached before the search runs, so that typing "Ana" or
  // "Café" finds the row either way.
  const rows = docs.map((doc) => {
    const row = comNome(toRedemption(doc.id, doc.data), nomes);
    return {
      ...row,
      reward_name:
        row.reward_id === null ? null : recompensas.get(row.reward_id) ?? null,
    };
  });

  return {
    ...selectByRecency(rows, query, {
      time: (row) => row.redeemed_at,
      status: (row) => row.status,
      search: (row) => [
        row.id,
        row.customer_id,
        row.customer_name,
        row.reward_id,
        row.reward_name,
      ],
    }),
    truncated,
  };
}

/** Reward ids to their names, for the list that stores only the id. */
async function nomesDeRecompensas(
  merchantId: string,
): Promise<Map<string, string>> {
  const { docs } = await readSubcollection(merchantId, 'rewards');
  const nomes = new Map<string, string>();
  for (const doc of docs) {
    const nome = toReward(doc.id, doc.data).name;
    if (nome !== null && nome.trim() !== '') nomes.set(doc.id, nome);
  }
  return nomes;
}

export function listAppointments(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'appointments', toAppointment, query, {
    time: (row) => row.scheduled_date,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id, row.customer_name],
  });
}

export function listReturnBonuses(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'return_bonuses', toReturnBonus, query, {
    time: (row) => row.issued_at,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id, row.customer_name],
  });
}

export function listRecoveryTasks(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'recovery_tasks', toRecoveryTask, query, {
    time: (row) => row.due_at ?? row.created_at,
    status: (row) => row.status,
    search: (row) => [row.id, row.customer_id, row.customer_name, row.notes],
  });
}

export function listVisitReports(merchantId: string, query: RecordQuery) {
  return pagina(merchantId, 'visit_reports', toVisitReport, query, {
    time: (row) => row.visited_at,
    status: (row) => row.result,
    search: (row) => [row.id, row.customer_id, row.customer_name, row.notes],
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
  const [{ docs, truncated }, nomes] = await Promise.all([
    readSubcollection(merchantId, 'customer_risk_scores'),
    nomesDeClientes(merchantId),
  ]);
  const rows = docs.map((doc) => comNome(toRiskScore(doc.id, doc.data), nomes));

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

/**
 * What the plan has actually consumed this period, against what it allows.
 *
 * One document per metric per calendar month, and nothing deletes a window
 * once it closes — the backend writes `merchant_id || '_' || metric_key || '_'
 * || window_start` and lets them accumulate. Returning all of them showed the
 * same measure several times over with contradicting numbers, and let a period
 * that ended fill the dashboard's three slots at 100%.
 *
 * So: the current window per metric, which is the one the question "how much
 * have I used?" is actually about. A window that has not started yet is not it
 * either, hence the comparison against now rather than simply the latest.
 */
export async function listUsageBalances(
  merchantId: string,
  agora: number = Date.now(),
): Promise<UsageBalanceRecord[]> {
  const { docs } = await readSubcollection(merchantId, 'usage_balances');
  const rows = docs.map((doc) => toUsageBalance(doc.id, doc.data));

  const corrente = new Map<string, UsageBalanceRecord>();
  for (const row of rows) {
    const chave = row.metric_key ?? row.id;
    const anterior = corrente.get(chave);
    if (anterior === undefined || melhorJanela(row, anterior, agora)) {
      corrente.set(chave, row);
    }
  }

  return [...corrente.values()].sort((a, b) =>
    (a.metric_key ?? '').localeCompare(b.metric_key ?? ''),
  );
}

/** Whether `candidato` describes the period in force better than `atual`. */
function melhorJanela(
  candidato: UsageBalanceRecord,
  atual: UsageBalanceRecord,
  agora: number,
): boolean {
  const aberta = (row: UsageBalanceRecord) =>
    (row.window_start ?? 0) <= agora &&
    (row.window_end === null || row.window_end >= agora);

  // A window containing today always wins over one that does not, however
  // recent the other is.
  if (aberta(candidato) !== aberta(atual)) return aberta(candidato);

  // Otherwise the later window, so a business between periods sees the one
  // that just closed rather than one from a year ago.
  const por = (row: UsageBalanceRecord) => row.window_start ?? row.updated_at ?? 0;
  return por(candidato) > por(atual);
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

/**
 * What customers actually answered — not how many of them answered.
 *
 * The surveys list carries a response count, which tells a business that
 * people replied and nothing about what they said. A survey exists to be read,
 * so this joins each response back to its survey, its customer and its
 * answers, and hands over rows a screen can print without knowing that an
 * answer lives in one of three value columns.
 *
 * `query.status` filters by survey id rather than by a state: "which survey"
 * is the only filter this list has any use for.
 */
export async function listSurveyResponses(
  merchantId: string,
  query: RecordQuery,
): Promise<MerchantPage<SurveyResponseRecord>> {
  const [responses, answers, questions, surveys, nomes] = await Promise.all([
    readSubcollection(merchantId, 'survey_responses'),
    readSubcollection(merchantId, 'survey_response_answers'),
    readSubcollection(merchantId, 'survey_questions'),
    readSubcollection(merchantId, 'surveys'),
    nomesDeClientes(merchantId),
  ]);

  const titles = new Map<string, string>();
  for (const doc of surveys.docs) {
    const survey = toSurvey(doc.id, doc.data);
    if (survey.title != null) titles.set(survey.id, survey.title);
  }

  const questionById = new Map<string, SurveyQuestionRecord>();
  for (const doc of questions.docs) {
    const question = toSurveyQuestion(doc.id, doc.data);
    questionById.set(question.id, question);
  }

  const answersByResponse = new Map<string, SurveyAnswerRecord[]>();
  for (const doc of answers.docs) {
    const responseId =
      asString(doc.data, 'response_id', 'responseId') ??
      asString(doc.data, 'survey_response_id', 'surveyResponseId');
    if (responseId == null) continue;
    const questionId = asString(doc.data, 'question_id', 'questionId');
    const question = questionId == null ? null : questionById.get(questionId);
    const bucket = answersByResponse.get(responseId) ?? [];
    bucket.push({
      question_id: questionId,
      question_text: question?.question_text ?? null,
      question_type: question?.question_type ?? null,
      sort_order: question?.sort_order ?? 0,
      answer: renderSurveyAnswer(doc.data),
    });
    answersByResponse.set(responseId, bucket);
  }

  const rows = responses.docs.map((doc) => {
    const response = comNome(toSurveyResponse(doc.id, doc.data), nomes);
    const own = (answersByResponse.get(response.id) ?? []).sort(
      (a, b) => a.sort_order - b.sort_order,
    );
    return {
      ...response,
      survey_title:
        response.survey_id == null ? null : titles.get(response.survey_id) ?? null,
      answers: own,
    };
  });

  return {
    ...selectByRecency(rows, query, {
      time: (row) => row.submitted_at,
      // Not a state: the only filter worth having here is which survey.
      status: (row) => row.survey_id,
      search: (row) => [
        row.customer_name,
        row.survey_title,
        ...row.answers.map((answer) => answer.answer),
      ],
    }),
    truncated:
      responses.truncated ||
      answers.truncated ||
      questions.truncated ||
      surveys.truncated,
  };
}
