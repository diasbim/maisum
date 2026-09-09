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

export type SourceRecord = Record<string, unknown>;

/* --------------------------------------------------------------- normalisers */

export function asString(data: SourceRecord, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return null;
}

export function asNumber(data: SourceRecord, ...keys: string[]): number | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() !== '') {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) return parsed;
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
export function asBool(data: SourceRecord, ...keys: string[]): boolean | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number' && Number.isFinite(value)) return value !== 0;
    if (typeof value === 'string') {
      const normalized = value.trim().toLowerCase();
      if (normalized === 'true' || normalized === '1') return true;
      if (normalized === 'false' || normalized === '0') return false;
    }
  }
  return null;
}

/** Epoch milliseconds, rejecting the zero the app writes for "never". */
export function asEpoch(data: SourceRecord, ...keys: string[]): number | null {
  const value = asNumber(data, ...keys);
  return value !== null && value > 0 ? value : null;
}

/* ------------------------------------------------------------------- records */

export type CustomerRecord = {
  id: string;
  name: string | null;
  phone: string | null;
  total_points: number;
  total_visits: number;
  total_spent: number;
  average_spend: number | null;
  lifecycle_stage: string | null;
  retention_status: string | null;
  relationship_status: string | null;
  first_visit_at: number | null;
  last_visit_at: number | null;
  created_at: number | null;
  updated_at: number | null;
  archived_at: number | null;
};

export function toCustomer(id: string, data: SourceRecord): CustomerRecord {
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

export type CatalogItemRecord = {
  id: string;
  name: string | null;
  type: string | null;
  default_price: number | null;
  is_active: boolean | null;
  display_order: number;
  created_at: number | null;
  updated_at: number | null;
};

export function toCatalogItem(id: string, data: SourceRecord): CatalogItemRecord {
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

export type RewardRecord = {
  id: string;
  name: string | null;
  description: string | null;
  points_required: number | null;
  is_active: boolean | null;
  created_at: number | null;
  updated_at: number | null;
};

export function toReward(id: string, data: SourceRecord): RewardRecord {
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

export type SaleRecord = {
  id: string;
  amount: number | null;
  points: number | null;
  created_at: number | null;
  cancellation_status: string | null;
  confirmation_status: string | null;
};

/**
 * One sale on a customer's history.
 *
 * The two status fields are carried through rather than collapsed into a
 * single "state": a cancelled sale is still a row in this collection, and
 * dropping it would make the customer's points stop adding up while showing it
 * plainly would overstate how often they came.
 */
export function toSale(id: string, data: SourceRecord): SaleRecord {
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
export function sortSales(rows: SaleRecord[]): SaleRecord[] {
  return [...rows].sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0));
}

export type StaffRecord = {
  id: string;
  phone: string | null;
  role: string | null;
  status: string | null;
  created_at: number | null;
  updated_at: number | null;
  last_login_at: number | null;
};

export function toStaff(id: string, data: SourceRecord): StaffRecord {
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

/* ------------------------------------------------------- querying in memory */

/**
 * Why filtering happens here rather than in the query.
 *
 * A business subcollection is a few hundred documents at pilot scale, and the
 * fields a merchant searches on — a customer's name, a phone — would each need
 * their own composite index. Reading the subcollection once and filtering in
 * memory costs one read for any query, and the cap in
 * `merchant_collections.ts` reports when that stops being true instead of
 * serving a partial answer as if it were complete.
 */

export type RecordQuery = {
  search?: string;
  status?: string;
  limit: number;
  offset: number;
};

export type RecordPage<T> = {
  items: T[];
  hasMore: boolean;
  total: number;
};

/** Case- and accent-insensitive, so "Joao" finds "João". */
export function fold(value: string): string {
  return value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
}

export function matchesSearch(
  fields: Array<string | null>,
  search: string,
): boolean {
  const needle = fold(search);
  if (needle === '') return true;
  return fields.some((value) => value !== null && fold(value).includes(needle));
}

/**
 * Cuts a read down to the cap and says whether anything was cut.
 *
 * The caller reads `cap + 1` documents so that "exactly at the cap" and "one
 * past it" are distinguishable — otherwise a business with exactly 2000
 * customers would be told its list is incomplete when it is not.
 */
export function capDocuments<T>(
  docs: T[],
  cap: number,
): { docs: T[]; truncated: boolean } {
  const truncated = docs.length > cap;
  return { docs: truncated ? docs.slice(0, cap) : docs, truncated };
}

export function paginate<T>(rows: T[], query: RecordQuery): RecordPage<T> {
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
export function selectCustomers(
  rows: CustomerRecord[],
  query: RecordQuery,
): RecordPage<CustomerRecord> {
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
      if (value !== status) return false;
    }
    return true;
  });

  const sorted = [...filtered].sort((a, b) => {
    const byVisit = (b.last_visit_at ?? 0) - (a.last_visit_at ?? 0);
    if (byVisit !== 0) return byVisit;
    return (a.name ?? a.id).localeCompare(b.name ?? b.id, 'pt');
  });

  return paginate(sorted, query);
}

/** The catalogue, in the order the app shows it at the till. */
export function selectCatalog(
  rows: CatalogItemRecord[],
  query: RecordQuery,
): RecordPage<CatalogItemRecord> {
  const search = (query.search ?? '').trim();
  const status = (query.status ?? '').trim().toUpperCase();

  const filtered = rows.filter((row) => {
    if (search !== '' && !matchesSearch([row.name, row.id], search)) return false;
    if (status === 'ACTIVE' && row.is_active === false) return false;
    if (status === 'INACTIVE' && row.is_active !== false) return false;
    if (status === 'PRODUCT' || status === 'SERVICE') {
      if ((row.type ?? '').toUpperCase() !== status) return false;
    }
    return true;
  });

  const sorted = [...filtered].sort((a, b) => {
    const byOrder = a.display_order - b.display_order;
    if (byOrder !== 0) return byOrder;
    return (a.name ?? a.id).localeCompare(b.name ?? b.id, 'pt');
  });

  return paginate(sorted, query);
}

/** Rewards, cheapest first: that is the one a customer reaches next. */
export function selectRewards(
  rows: RewardRecord[],
  query: RecordQuery,
): RecordPage<RewardRecord> {
  const search = (query.search ?? '').trim();
  const status = (query.status ?? '').trim().toUpperCase();

  const filtered = rows.filter((row) => {
    if (
      search !== '' &&
      !matchesSearch([row.name, row.description, row.id], search)
    ) {
      return false;
    }
    if (status === 'ACTIVE' && row.is_active === false) return false;
    if (status === 'INACTIVE' && row.is_active !== false) return false;
    return true;
  });

  const sorted = [...filtered].sort(
    (a, b) => (a.points_required ?? 0) - (b.points_required ?? 0),
  );

  return paginate(sorted, query);
}

/** The team: owners first, then whoever signed in most recently. */
export function selectStaff(
  rows: StaffRecord[],
  query: RecordQuery,
): RecordPage<StaffRecord> {
  const search = (query.search ?? '').trim();
  const status = (query.status ?? '').trim().toUpperCase();

  const rank = (role: string | null): number => {
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
    if (byRole !== 0) return byRole;
    return (
      (b.last_login_at ?? b.updated_at ?? 0) -
      (a.last_login_at ?? a.updated_at ?? 0)
    );
  });

  return paginate(sorted, query);
}

/* ------------------------------------------------- the rest of the business */

/**
 * Everything below serves a surface the business could not see.
 *
 * The app has synced these subcollections up for a while and the portal read
 * none of them: a merchant could see who their customers were, but not what
 * they had bought, what they had redeemed, what the plan had actually
 * consumed, or which of them the retention engine had flagged. The console
 * could see some of it. The business it described could not.
 *
 * The shapes come from `app_migrations.dart` — snake_case keys, epoch
 * milliseconds, flags as 0/1 — so each goes through the normalisers above
 * rather than being trusted as JSON.
 */

export type SaleListRecord = SaleRecord & {
  customer_id: string | null;
};

export function toSaleListItem(id: string, data: SourceRecord): SaleListRecord {
  return {
    ...toSale(id, data),
    customer_id: asString(data, 'customer_id', 'customerId'),
  };
}

export type RedemptionRecord = {
  id: string;
  customer_id: string | null;
  reward_id: string | null;
  points_spent: number | null;
  redeemed_at: number | null;
  status: string | null;
};

export function toRedemption(id: string, data: SourceRecord): RedemptionRecord {
  return {
    id: asString(data, 'id') ?? id,
    customer_id: asString(data, 'customer_id', 'customerId'),
    reward_id: asString(data, 'reward_id', 'rewardId'),
    points_spent: asNumber(data, 'points_spent', 'pointsSpent'),
    redeemed_at: asEpoch(data, 'redeemed_at', 'redeemedAt', 'created_at'),
    status: asString(data, 'status', 'fulfillment_status'),
  };
}

export type AppointmentRecord = {
  id: string;
  customer_id: string | null;
  scheduled_date: number | null;
  status: string | null;
  source: string | null;
  reminder_sent: boolean | null;
  created_at: number | null;
};

export function toAppointment(
  id: string,
  data: SourceRecord,
): AppointmentRecord {
  return {
    id: asString(data, 'id') ?? id,
    customer_id: asString(data, 'customer_id', 'customerId'),
    scheduled_date: asEpoch(data, 'scheduled_date', 'scheduledDate'),
    status: asString(data, 'status'),
    source: asString(data, 'source'),
    reminder_sent: asBool(data, 'reminder_sent', 'reminderSent'),
    created_at: asEpoch(data, 'created_at'),
  };
}

export type LedgerEntryRecord = {
  id: string;
  customer_id: string | null;
  entry_type: string | null;
  points_delta: number | null;
  source_type: string | null;
  source_id: string | null;
  balance_after: number | null;
  occurred_at: number | null;
};

export function toLedgerEntry(
  id: string,
  data: SourceRecord,
): LedgerEntryRecord {
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

export type UsageBalanceRecord = {
  id: string;
  metric_key: string | null;
  used: number;
  limit_value: number | null;
  soft_limit: boolean | null;
  window_start: number | null;
  window_end: number | null;
  updated_at: number | null;
};

export function toUsageBalance(
  id: string,
  data: SourceRecord,
): UsageBalanceRecord {
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

export type RiskScoreRecord = {
  id: string;
  customer_id: string | null;
  days_since_visit: number;
  risk_level: string | null;
  priority: number;
  updated_at: number | null;
};

export function toRiskScore(id: string, data: SourceRecord): RiskScoreRecord {
  return {
    id: asString(data, 'id') ?? id,
    customer_id: asString(data, 'customer_id', 'customerId'),
    days_since_visit: asNumber(data, 'days_since_visit', 'daysSinceVisit') ?? 0,
    risk_level: asString(data, 'risk_level', 'riskLevel'),
    priority: asNumber(data, 'priority') ?? 0,
    updated_at: asEpoch(data, 'updated_at'),
  };
}

export type RecoveryTaskRecord = {
  id: string;
  customer_id: string | null;
  priority: string | null;
  status: string | null;
  due_at: number | null;
  notes: string | null;
  created_at: number | null;
};

export function toRecoveryTask(
  id: string,
  data: SourceRecord,
): RecoveryTaskRecord {
  return {
    id: asString(data, 'id') ?? id,
    customer_id: asString(data, 'customer_id', 'customerId'),
    priority: asString(data, 'priority'),
    status: asString(data, 'status'),
    due_at: asEpoch(data, 'due_at', 'dueAt'),
    notes: asString(data, 'notes'),
    created_at: asEpoch(data, 'created_at'),
  };
}

export type VisitReportRecord = {
  id: string;
  customer_id: string | null;
  task_id: string | null;
  result: string | null;
  notes: string | null;
  visited_at: number | null;
};

export function toVisitReport(
  id: string,
  data: SourceRecord,
): VisitReportRecord {
  return {
    id: asString(data, 'id') ?? id,
    customer_id: asString(data, 'customer_id', 'customerId'),
    task_id: asString(data, 'task_id', 'taskId'),
    result: asString(data, 'result'),
    notes: asString(data, 'notes'),
    visited_at: asEpoch(data, 'visited_at', 'visitedAt', 'created_at'),
  };
}

export type SurveyRecord = {
  id: string;
  title: string | null;
  description: string | null;
  is_active: boolean | null;
  /** Filled in by the collection layer, which counts the responses. */
  response_count: number;
  created_at: number | null;
  updated_at: number | null;
};

export function toSurvey(id: string, data: SourceRecord): SurveyRecord {
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

export type ReturnBonusRecord = {
  id: string;
  customer_id: string | null;
  type: string | null;
  value: number | null;
  status: string | null;
  issued_at: number | null;
  expires_at: number | null;
  redeemed_at: number | null;
};

export function toReturnBonus(
  id: string,
  data: SourceRecord,
): ReturnBonusRecord {
  return {
    id: asString(data, 'id') ?? id,
    customer_id: asString(data, 'customer_id', 'customerId'),
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
export function selectByRecency<T extends { id: string }>(
  rows: T[],
  query: RecordQuery,
  read: {
    time: (row: T) => number | null;
    status?: (row: T) => string | null;
    search?: (row: T) => Array<string | null>;
  },
): RecordPage<T> {
  const search = (query.search ?? '').trim();
  const status = (query.status ?? '').trim().toUpperCase();

  const filtered = rows.filter((row) => {
    if (search !== '' && read.search) {
      if (!matchesSearch(read.search(row), search)) return false;
    }
    if (status !== '' && read.status) {
      if ((read.status(row) ?? '').toUpperCase() !== status) return false;
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

/** What a business asks of its own sales: how much, and how often. */
export type SalesTotals = {
  count: number;
  amount: number;
  points: number;
};

export function totalSales(rows: SaleListRecord[]): SalesTotals {
  return rows.reduce<SalesTotals>(
    (running, row) => ({
      count: running.count + 1,
      amount: running.amount + (row.amount ?? 0),
      points: running.points + (row.points ?? 0),
    }),
    { count: 0, amount: 0, points: 0 },
  );
}
