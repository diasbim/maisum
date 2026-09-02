/**
 * Joining businesses with their subcollections, in memory.
 *
 * Firestore has no joins. The merchant list used to be one SQL statement with
 * three LEFT JOINs; here the same answer is assembled from three collection
 * group queries — one for every `subscription_state` in the project, one for
 * every `app_users`, one for every `usage_balances` — and stitched together by
 * the merchant id each document belongs to.
 *
 * That is three reads for the whole page instead of three per business. It is
 * also bounded: a collection group query returns everything, so the callers cap
 * it and report when the cap was hit rather than presenting a partial join as
 * the complete picture.
 *
 * Everything here is pure so the join, the filter and the ordering can be
 * tested without Firestore.
 */

export type BusinessRecord = {
  id: string;
  data: Record<string, unknown>;
};

/** A subcollection document, tagged with the business it came from. */
export type OwnedRecord = {
  merchantId: string;
  data: Record<string, unknown>;
};

export type MerchantSummary = {
  id: string;
  name: string;
  phone: string | null;
  created_at: number | null;
  updated_at: number | null;
  plan_code: string | null;
  plan_name: string | null;
  subscription_status: string | null;
  staff_count: number;
  active_staff_count: number;
  usage_balance_count: number;
  last_operational_update_at: number | null;
};

function str(data: Record<string, unknown>, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function num(data: Record<string, unknown>, ...keys: string[]): number | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string') {
      const parsed = Number(value.trim());
      if (value.trim().length > 0 && Number.isFinite(parsed)) return parsed;
    }
  }
  return null;
}

/** Groups subcollection documents by the business that owns them. */
export function groupByMerchant(
  records: OwnedRecord[],
): Map<string, Array<Record<string, unknown>>> {
  const grouped = new Map<string, Array<Record<string, unknown>>>();
  for (const record of records) {
    if (!record.merchantId) continue;
    const bucket = grouped.get(record.merchantId);
    if (bucket) {
      bucket.push(record.data);
    } else {
      grouped.set(record.merchantId, [record.data]);
    }
  }
  return grouped;
}

/**
 * Builds one merchant summary.
 *
 * A business may have several `subscription_state` documents over its life; the
 * most recently updated one is the current one. Picking arbitrarily would make
 * the plan column flicker between page loads.
 */
export function buildMerchantSummary(
  business: BusinessRecord,
  subscriptions: Array<Record<string, unknown>>,
  staff: Array<Record<string, unknown>>,
  usageBalances: Array<Record<string, unknown>>,
): MerchantSummary {
  const data = business.data;

  const current = [...subscriptions].sort(
    (a, b) => (num(b, 'updated_at') ?? 0) - (num(a, 'updated_at') ?? 0),
  )[0];

  const activeStaff = staff.filter(
    (member) => (str(member, 'status') ?? '').toUpperCase() === 'ACTIVE',
  ).length;

  const businessUpdatedAt = num(data, 'updated_at');

  // The list is ordered by this column, and "last operational update" means the
  // latest activity anywhere on the business, not just an edit to its profile.
  const lastOperational = Math.max(
    businessUpdatedAt ?? 0,
    current ? (num(current, 'updated_at') ?? 0) : 0,
    ...staff.map((member) => num(member, 'updated_at') ?? 0),
    ...usageBalances.map((balance) => num(balance, 'updated_at') ?? 0),
  );

  return {
    id: business.id,
    // Firestore calls it merchant_name; the console and the old SQL call it
    // name. Both spellings are read so documents from either era resolve.
    name: str(data, 'merchant_name', 'name') ?? '',
    phone: str(data, 'phone'),
    created_at: num(data, 'created_at'),
    updated_at: businessUpdatedAt,
    plan_code: current ? str(current, 'plan_code') : null,
    plan_name: current ? str(current, 'plan_name') : null,
    subscription_status: current ? str(current, 'status') : null,
    staff_count: staff.length,
    active_staff_count: activeStaff,
    usage_balance_count: usageBalances.length,
    last_operational_update_at: lastOperational > 0 ? lastOperational : null,
  };
}

export type MerchantQuery = {
  search?: string;
  status?: string;
  planCode?: string;
  limit: number;
  offset: number;
};

export type MerchantPage = {
  items: MerchantSummary[];
  hasMore: boolean;
  total: number;
};

/**
 * Filters, orders and pages the joined summaries.
 *
 * Search is a case-insensitive substring over id, name and phone — what the SQL
 * `ILIKE` did. Firestore cannot express that server-side at all, which is the
 * honest reason it happens here: the alternative is prefix-only matching, and
 * an operator searching for part of a phone number would find nothing.
 */
export function selectMerchants(
  summaries: MerchantSummary[],
  query: MerchantQuery,
): MerchantPage {
  const search = (query.search ?? '').trim().toLowerCase();
  const status = (query.status ?? '').trim().toUpperCase();
  const planCode = (query.planCode ?? '').trim();

  const filtered = summaries.filter((merchant) => {
    if (search.length > 0) {
      const haystack = [merchant.id, merchant.name, merchant.phone ?? '']
        .join('')
        .toLowerCase();
      if (!haystack.includes(search)) return false;
    }
    if (status.length > 0) {
      if ((merchant.subscription_status ?? '').toUpperCase() !== status) {
        return false;
      }
    }
    if (planCode.length > 0 && merchant.plan_code !== planCode) return false;
    return true;
  });

  // Newest activity first, id as the tie-break so the order is stable across
  // requests and paging never repeats or skips a row.
  filtered.sort((a, b) => {
    const delta =
      (b.last_operational_update_at ?? 0) - (a.last_operational_update_at ?? 0);
    return delta !== 0 ? delta : a.id.localeCompare(b.id);
  });

  const offset = Math.max(0, query.offset);
  const items = filtered.slice(offset, offset + query.limit);

  return {
    items,
    hasMore: offset + items.length < filtered.length,
    // Available because the whole set is in hand — the SQL version could only
    // ever say whether another page existed.
    total: filtered.length,
  };
}
