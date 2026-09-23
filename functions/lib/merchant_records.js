"use strict";
/**
 * Shaping the business's own operational records for the web.
 *
 * These documents are written by the mobile app, which syncs SQLite rows
 * straight up: snake_case keys, epoch milliseconds for times, and booleans
 * stored as 0/1 integers (`is_active`, `active`, `synced`). A web client that
 * assumed JSON-shaped values would read every inactive item as active, so
 * every field goes through a normaliser here rather than being passed along
 * as it was stored.
 *
 * Kept free of firebase-admin on purpose: this is the part worth testing, and
 * `merchant_collections.ts` is the part that talks to Firestore.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.asString = asString;
exports.asNumber = asNumber;
exports.asBool = asBool;
exports.asEpoch = asEpoch;
exports.toCustomer = toCustomer;
exports.toCatalogItem = toCatalogItem;
exports.toReward = toReward;
exports.toSale = toSale;
exports.sortSales = sortSales;
exports.toStaff = toStaff;
exports.fold = fold;
exports.matchesSearch = matchesSearch;
exports.capDocuments = capDocuments;
exports.paginate = paginate;
exports.selectCustomers = selectCustomers;
exports.selectCatalog = selectCatalog;
exports.selectRewards = selectRewards;
exports.selectStaff = selectStaff;
exports.toSaleListItem = toSaleListItem;
exports.toRedemption = toRedemption;
exports.toAppointment = toAppointment;
exports.toLedgerEntry = toLedgerEntry;
exports.toUsageBalance = toUsageBalance;
exports.toRiskScore = toRiskScore;
exports.toRecoveryTask = toRecoveryTask;
exports.toVisitReport = toVisitReport;
exports.toSurvey = toSurvey;
exports.toSurveyResponse = toSurveyResponse;
exports.toSurveyQuestion = toSurveyQuestion;
exports.renderSurveyAnswer = renderSurveyAnswer;
exports.toReturnBonus = toReturnBonus;
exports.selectByRecency = selectByRecency;
exports.totalSales = totalSales;
/* --------------------------------------------------------------- normalisers */
function asString(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'string' && value.trim() !== '')
            return value.trim();
    }
    return null;
}
function asNumber(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'number' && Number.isFinite(value))
            return value;
        if (typeof value === 'string' && value.trim() !== '') {
            const parsed = Number(value);
            if (Number.isFinite(parsed))
                return parsed;
        }
    }
    return null;
}
/**
 * A flag as the app stores it.
 *
 * `1`/`0` is the SQLite spelling and by far the common case; real booleans
 * arrive from documents the backend wrote. Anything else is unknown rather
 * than false — a missing flag should not read as "disabled" on a screen that
 * lists what a business sells.
 */
function asBool(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'boolean')
            return value;
        if (typeof value === 'number' && Number.isFinite(value))
            return value !== 0;
        if (typeof value === 'string') {
            const normalized = value.trim().toLowerCase();
            if (normalized === 'true' || normalized === '1')
                return true;
            if (normalized === 'false' || normalized === '0')
                return false;
        }
    }
    return null;
}
/** Epoch milliseconds, rejecting the zero the app writes for "never". */
function asEpoch(data, ...keys) {
    const value = asNumber(data, ...keys);
    return value !== null && value > 0 ? value : null;
}
function toCustomer(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        name: asString(data, 'name'),
        phone: asString(data, 'phone'),
        total_points: asNumber(data, 'total_points') ?? 0,
        total_visits: asNumber(data, 'total_visits') ?? 0,
        total_spent: asNumber(data, 'total_spent') ?? 0,
        average_spend: asNumber(data, 'average_spend'),
        lifecycle_stage: asString(data, 'lifecycle_stage'),
        retention_status: asString(data, 'retention_status'),
        relationship_status: asString(data, 'relationship_status'),
        first_visit_at: asEpoch(data, 'first_visit_at'),
        last_visit_at: asEpoch(data, 'last_visit_at'),
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
        archived_at: asEpoch(data, 'archived_at'),
    };
}
function toCatalogItem(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        name: asString(data, 'name'),
        type: asString(data, 'type'),
        default_price: asNumber(data, 'default_price'),
        is_active: asBool(data, 'is_active', 'active'),
        display_order: asNumber(data, 'display_order') ?? 0,
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
    };
}
function toReward(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        name: asString(data, 'name'),
        description: asString(data, 'description'),
        points_required: asNumber(data, 'points_required'),
        // The app's reward model calls the flag `active`; `is_active` is the
        // spelling every other collection uses, so both are accepted.
        is_active: asBool(data, 'active', 'is_active'),
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
    };
}
/**
 * One sale on a customer's history.
 *
 * The two status fields are carried through rather than collapsed into a
 * single "state": a cancelled sale is still a row in this collection, and
 * dropping it would make the customer's points stop adding up while showing it
 * plainly would overstate how often they came.
 */
function toSale(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        amount: asNumber(data, 'amount'),
        points: asNumber(data, 'points'),
        created_at: asEpoch(data, 'created_at'),
        cancellation_status: asString(data, 'cancellation_status'),
        confirmation_status: asString(data, 'confirmation_status'),
    };
}
/** Newest first. A sale with no date sorts last rather than as 1970. */
function sortSales(rows) {
    return [...rows].sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0));
}
function toStaff(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        phone: asString(data, 'phone'),
        role: asString(data, 'role'),
        status: asString(data, 'status'),
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
        last_login_at: asEpoch(data, 'last_login_at'),
    };
}
/** Case- and accent-insensitive, so "Joao" finds "João". */
function fold(value) {
    return value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
}
function matchesSearch(fields, search) {
    const needle = fold(search);
    if (needle === '')
        return true;
    return fields.some((value) => value !== null && fold(value).includes(needle));
}
/**
 * Cuts a read down to the cap and says whether anything was cut.
 *
 * The caller reads `cap + 1` documents so that "exactly at the cap" and "one
 * past it" are distinguishable — otherwise a business with exactly 2000
 * customers would be told its list is incomplete when it is not.
 */
function capDocuments(docs, cap) {
    const truncated = docs.length > cap;
    return { docs: truncated ? docs.slice(0, cap) : docs, truncated };
}
function paginate(rows, query) {
    const offset = Math.max(0, query.offset);
    const limit = Math.max(1, query.limit);
    const items = rows.slice(offset, offset + limit);
    return {
        items,
        hasMore: offset + items.length < rows.length,
        total: rows.length,
    };
}
/**
 * The customer list, ordered the way the counter thinks about it.
 *
 * Most recent visit first, because the question behind this screen is usually
 * "who was just here". Customers who have never visited fall to the bottom in
 * name order rather than in whatever order Firestore returned them.
 */
function selectCustomers(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' && !matchesSearch([row.name, row.phone, row.id], search)) {
            return false;
        }
        if (status !== '') {
            // A document written before the field existed is an active customer,
            // which is what the app assumes too.
            const value = (row.relationship_status ?? 'ACTIVE').toUpperCase();
            if (value !== status)
                return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byVisit = (b.last_visit_at ?? 0) - (a.last_visit_at ?? 0);
        if (byVisit !== 0)
            return byVisit;
        return (a.name ?? a.id).localeCompare(b.name ?? b.id, 'pt');
    });
    return paginate(sorted, query);
}
/** The catalogue, in the order the app shows it at the till. */
function selectCatalog(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' && !matchesSearch([row.name, row.id], search))
            return false;
        if (status === 'ACTIVE' && row.is_active === false)
            return false;
        if (status === 'INACTIVE' && row.is_active !== false)
            return false;
        if (status === 'PRODUCT' || status === 'SERVICE') {
            if ((row.type ?? '').toUpperCase() !== status)
                return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byOrder = a.display_order - b.display_order;
        if (byOrder !== 0)
            return byOrder;
        return (a.name ?? a.id).localeCompare(b.name ?? b.id, 'pt');
    });
    return paginate(sorted, query);
}
/** Rewards, cheapest first: that is the one a customer reaches next. */
function selectRewards(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' &&
            !matchesSearch([row.name, row.description, row.id], search)) {
            return false;
        }
        if (status === 'ACTIVE' && row.is_active === false)
            return false;
        if (status === 'INACTIVE' && row.is_active !== false)
            return false;
        return true;
    });
    const sorted = [...filtered].sort((a, b) => (a.points_required ?? 0) - (b.points_required ?? 0));
    return paginate(sorted, query);
}
/** The team: owners first, then whoever signed in most recently. */
function selectStaff(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const rank = (role) => {
        switch ((role ?? '').toUpperCase()) {
            case 'OWNER':
                return 0;
            case 'MANAGER':
                return 1;
            default:
                return 2;
        }
    };
    const filtered = rows.filter((row) => {
        if (search !== '' && !matchesSearch([row.phone, row.id, row.role], search)) {
            return false;
        }
        if (status !== '' && (row.status ?? '').toUpperCase() !== status) {
            return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byRole = rank(a.role) - rank(b.role);
        if (byRole !== 0)
            return byRole;
        return ((b.last_login_at ?? b.updated_at ?? 0) -
            (a.last_login_at ?? a.updated_at ?? 0));
    });
    return paginate(sorted, query);
}
function toSaleListItem(id, data) {
    return {
        ...toSale(id, data),
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
    };
}
function toRedemption(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
        reward_id: asString(data, 'reward_id', 'rewardId'),
        reward_name: null,
        points_spent: asNumber(data, 'points_spent', 'pointsSpent'),
        redeemed_at: asEpoch(data, 'redeemed_at', 'redeemedAt', 'created_at'),
        status: asString(data, 'status', 'fulfillment_status'),
    };
}
function toAppointment(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
        scheduled_date: asEpoch(data, 'scheduled_date', 'scheduledDate'),
        status: asString(data, 'status'),
        source: asString(data, 'source'),
        reminder_sent: asBool(data, 'reminder_sent', 'reminderSent'),
        created_at: asEpoch(data, 'created_at'),
    };
}
function toLedgerEntry(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        entry_type: asString(data, 'entry_type', 'entryType'),
        points_delta: asNumber(data, 'points_delta', 'pointsDelta'),
        source_type: asString(data, 'source_type', 'sourceType'),
        source_id: asString(data, 'source_id', 'sourceId'),
        balance_after: asNumber(data, 'balance_after', 'balanceAfter'),
        occurred_at: asEpoch(data, 'occurred_at', 'occurredAt', 'created_at'),
    };
}
function toUsageBalance(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        metric_key: asString(data, 'metric_key', 'metricKey'),
        used: asNumber(data, 'used') ?? 0,
        // Null is "no ceiling", which is a different answer from zero.
        limit_value: asNumber(data, 'limit_value', 'limitValue'),
        soft_limit: asBool(data, 'soft_limit', 'softLimit'),
        window_start: asEpoch(data, 'window_start', 'windowStart'),
        window_end: asEpoch(data, 'window_end', 'windowEnd'),
        updated_at: asEpoch(data, 'updated_at'),
    };
}
function toRiskScore(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
        days_since_visit: asNumber(data, 'days_since_visit', 'daysSinceVisit') ?? 0,
        risk_level: asString(data, 'risk_level', 'riskLevel'),
        priority: asNumber(data, 'priority') ?? 0,
        updated_at: asEpoch(data, 'updated_at'),
    };
}
function toRecoveryTask(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
        priority: asString(data, 'priority'),
        status: asString(data, 'status'),
        due_at: asEpoch(data, 'due_at', 'dueAt'),
        notes: asString(data, 'notes'),
        created_at: asEpoch(data, 'created_at'),
    };
}
function toVisitReport(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
        task_id: asString(data, 'task_id', 'taskId'),
        result: asString(data, 'result'),
        notes: asString(data, 'notes'),
        visited_at: asEpoch(data, 'visited_at', 'visitedAt', 'created_at'),
    };
}
function toSurvey(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        title: asString(data, 'title'),
        description: asString(data, 'description'),
        is_active: asBool(data, 'is_active', 'isActive', 'active'),
        response_count: 0,
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
    };
}
function toSurveyResponse(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        survey_id: asString(data, 'survey_id', 'surveyId'),
        // Both filled in by the joins, not stored on the row.
        survey_title: null,
        customer_id: asString(data, 'customer_id', 'customerId'),
        customer_name: null,
        channel: asString(data, 'channel'),
        submitted_at: asEpoch(data, 'submitted_at', 'submittedAt', 'created_at'),
        answers: [],
    };
}
function toSurveyQuestion(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        survey_id: asString(data, 'survey_id', 'surveyId'),
        question_text: asString(data, 'question_text', 'questionText'),
        question_type: asString(data, 'question_type', 'questionType'),
        sort_order: asNumber(data, 'sort_order', 'sortOrder') ?? 0,
    };
}
/**
 * Renders a stored answer as text.
 *
 * Exactly one of the three value columns carries the answer, so the first
 * non-empty one wins. A boolean is the only value that cannot speak for
 * itself — `true` is not an answer anybody gave, "Sim" is.
 */
function renderSurveyAnswer(data) {
    const text = asString(data, 'answer_text', 'answerText');
    if (text != null && text.trim() !== '')
        return text.trim();
    const numeric = asNumber(data, 'answer_numeric', 'answerNumeric');
    if (numeric != null)
        return String(numeric);
    const bool = asBool(data, 'answer_bool', 'answerBool');
    if (bool != null)
        return bool ? 'Sim' : 'Não';
    return null;
}
function toReturnBonus(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        customer_id: asString(data, 'customer_id', 'customerId'),
        // Filled in by the join, not stored on the row.
        customer_name: null,
        type: asString(data, 'type'),
        value: asNumber(data, 'value'),
        status: asString(data, 'status'),
        issued_at: asEpoch(data, 'issued_at', 'issuedAt'),
        expires_at: asEpoch(data, 'expires_at', 'expiresAt'),
        redeemed_at: asEpoch(data, 'redeemed_at', 'redeemedAt'),
    };
}
/* ---------------------------------------------------- selecting the new ones */
/**
 * One selector, because these lists differ only in what they sort by.
 *
 * `selectCustomers` and the rest above each earned their own function by
 * having a genuinely different idea of order — most recent visit, the order
 * the till shows, the owner first. These do not: every one of them is "newest
 * first", filtered by an exact status and a substring. Writing eight
 * near-copies would have made the differences between them harder to see, not
 * easier.
 */
function selectByRecency(rows, query, read) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' && read.search) {
            if (!matchesSearch(read.search(row), search))
                return false;
        }
        if (status !== '' && read.status) {
            if ((read.status(row) ?? '').toUpperCase() !== status)
                return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byTime = (read.time(b) ?? 0) - (read.time(a) ?? 0);
        // Ties break on id so that paging is stable: without it two rows written
        // in the same millisecond could swap between page one and page two.
        return byTime !== 0 ? byTime : a.id.localeCompare(b.id);
    });
    return paginate(sorted, query);
}
function totalSales(rows) {
    return rows.reduce((running, row) => ({
        count: running.count + 1,
        amount: running.amount + (row.amount ?? 0),
        points: running.points + (row.points ?? 0),
    }), { count: 0, amount: 0, points: 0 });
}
