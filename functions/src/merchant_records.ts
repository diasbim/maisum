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
