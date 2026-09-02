import * as admin from 'firebase-admin';
import { FieldPath } from 'firebase-admin/firestore';

import {
  buildMerchantSummary,
  groupByMerchant,
  selectMerchants,
  type MerchantPage,
  type MerchantQuery,
  type OwnedRecord,
} from './admin_firestore_join.js';
import { ADMIN_AUDIT_COLLECTION } from './admin_audit.js';

/**
 * The admin console's data layer, over Firestore.
 *
 * Everything the console reads lives in Firestore already — the same paths the
 * mobile app syncs to, listed in FirestoreSyncService._collectionMap. The
 * PostgreSQL schema mirrored these tables but was never connected in
 * production, so reading Firestore is not a workaround; it is reading the
 * source.
 *
 * Two constraints shape this file:
 *
 *  - **There are no joins.** Listing businesses with their subscription and
 *    staff means one collection group query per subcollection, joined in
 *    memory. Three reads for a page instead of three per business.
 *  - **Filtered collection group queries need declared indexes.** Unfiltered
 *    ones do not. So the paths that must always work avoid filters, and the
 *    ones that cannot degrade to an explicit "unavailable" rather than failing
 *    the whole screen.
 */

const db = () => admin.firestore();

/**
 * How many documents a collection group scan will pull before giving up.
 *
 * A console over a pilot's worth of businesses is far inside this. Past it the
 * answer would be wrong, so callers are told rather than served a partial join
 * presented as complete.
 */
export const SCAN_CAP = 5000;

export type Scanned<T> = { items: T[]; truncated: boolean };

/** Reads a whole collection group, tagged with the owning business. */
async function scanOwned(collectionId: string): Promise<Scanned<OwnedRecord>> {
  const snapshot = await db()
    .collectionGroup(collectionId)
    .limit(SCAN_CAP + 1)
    .get();

  const truncated = snapshot.size > SCAN_CAP;
  const docs = truncated ? snapshot.docs.slice(0, SCAN_CAP) : snapshot.docs;

  return {
    items: docs.map((doc) => ({
      // businesses/{merchantId}/{collectionId}/{docId} — the grandparent is
      // the business document.
      merchantId: doc.ref.parent.parent?.id ?? '',
      data: doc.data() as Record<string, unknown>,
    })),
    truncated,
  };
}

export type MerchantListResult = MerchantPage & { truncated: boolean };

export async function listMerchants(
  query: MerchantQuery,
): Promise<MerchantListResult> {
  const [businesses, subscriptions, staff, usage] = await Promise.all([
    db().collection('businesses').limit(SCAN_CAP + 1).get(),
    scanOwned('subscription_state'),
    scanOwned('app_users'),
    scanOwned('usage_balances'),
  ]);

  const businessTruncated = businesses.size > SCAN_CAP;
  const businessDocs = businessTruncated
    ? businesses.docs.slice(0, SCAN_CAP)
    : businesses.docs;

  const subscriptionsBy = groupByMerchant(subscriptions.items);
  const staffBy = groupByMerchant(staff.items);
  const usageBy = groupByMerchant(usage.items);

  const summaries = businessDocs.map((doc) =>
    buildMerchantSummary(
      { id: doc.id, data: doc.data() as Record<string, unknown> },
      subscriptionsBy.get(doc.id) ?? [],
      staffBy.get(doc.id) ?? [],
      usageBy.get(doc.id) ?? [],
    ),
  );

  return {
    ...selectMerchants(summaries, query),
    truncated:
      businessTruncated ||
      subscriptions.truncated ||
      staff.truncated ||
      usage.truncated,
  };
}

/** Every document in one business subcollection. */
async function subcollection(
  merchantId: string,
  collectionId: string,
  limit = 500,
): Promise<Array<Record<string, unknown>>> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection(collectionId)
    .limit(limit)
    .get();
  return snapshot.docs.map((doc) => doc.data() as Record<string, unknown>);
}

function pickString(
  data: Record<string, unknown> | undefined,
  ...keys: string[]
): string | null {
  if (!data) return null;
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function pickNumber(
  data: Record<string, unknown> | undefined,
  ...keys: string[]
): number | null {
  if (!data) return null;
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
  }
  return null;
}

function latest(
  records: Array<Record<string, unknown>>,
): Record<string, unknown> | undefined {
  return [...records].sort(
    (a, b) => (pickNumber(b, 'updated_at') ?? 0) - (pickNumber(a, 'updated_at') ?? 0),
  )[0];
}

export async function getMerchantDetail(
  merchantId: string,
): Promise<Record<string, unknown> | null> {
  const businessDoc = await db().collection('businesses').doc(merchantId).get();
  if (!businessDoc.exists) return null;

  const [
    subscriptions,
    staff,
    usageBalances,
    usageEvents,
    entitlements,
    featureFlags,
    remoteConfig,
  ] = await Promise.all([
    subcollection(merchantId, 'subscription_state', 20),
    subcollection(merchantId, 'app_users', 200),
    subcollection(merchantId, 'usage_balances', 200),
    subcollection(merchantId, 'usage_events', 500),
    subcollection(merchantId, 'entitlements', 200),
    subcollection(merchantId, 'feature_flags', 200),
    subcollection(merchantId, 'remote_config', 200),
  ]);

  const data = businessDoc.data() as Record<string, unknown>;
  const summary = buildMerchantSummary(
    { id: merchantId, data },
    subscriptions,
    staff,
    usageBalances,
  );
  const current = latest(subscriptions);

  const lastStaffLogin = staff.reduce(
    (newest, member) => Math.max(newest, pickNumber(member, 'last_login_at') ?? 0),
    0,
  );
  const lastUsageEvent = usageEvents.reduce(
    (newest, event) =>
      Math.max(newest, pickNumber(event, 'created_at', 'occurred_at') ?? 0),
    0,
  );

  return {
    ...summary,
    plan_version: pickNumber(current, 'plan_version'),
    pricing_version: pickNumber(current, 'pricing_version'),
    trial_ends_at: pickNumber(current, 'trial_ends_at'),
    grace_ends_at: pickNumber(current, 'grace_ends_at'),
    period_start: pickNumber(current, 'period_start'),
    period_end: pickNumber(current, 'period_end'),
    subscription_updated_at: pickNumber(current, 'updated_at'),
    last_staff_login_at: lastStaffLogin > 0 ? lastStaffLogin : null,
    usage_used_total: usageBalances.reduce(
      (total, balance) => total + (pickNumber(balance, 'used') ?? 0),
      0,
    ),
    usage_updated_at: pickNumber(latest(usageBalances), 'updated_at'),
    // Capped by the subcollection read, so a very busy business reports the
    // cap rather than a wrong total. The detail page is a summary, not a
    // billing record.
    usage_event_count: usageEvents.length,
    last_usage_event_at: lastUsageEvent > 0 ? lastUsageEvent : null,
    entitlement_count: entitlements.length,
    feature_flag_count: featureFlags.length,
    remote_config_count: remoteConfig.length,
  };
}

export async function listEntitlements(
  merchantId: string,
): Promise<Array<Record<string, unknown>>> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection('entitlements')
    .get();

  return snapshot.docs
    .map(
      (doc): Record<string, unknown> => ({
        id: doc.id,
        ...(doc.data() as Record<string, unknown>),
      }),
    )
    .sort((a, b) =>
      String(a.feature_key ?? '').localeCompare(String(b.feature_key ?? '')),
    );
}

export async function merchantExists(merchantId: string): Promise<boolean> {
  const doc = await db().collection('businesses').doc(merchantId).get();
  return doc.exists;
}

/**
 * Writes an entitlement override.
 *
 * Keyed by feature so a second override of the same feature replaces the
 * first instead of accumulating rows that contradict each other. Returns the
 * previous state so the audit entry can record what changed.
 */
export async function upsertEntitlement(input: {
  merchantId: string;
  featureKey: string;
  isEnabled: boolean;
  limitValue: number | null;
  unit: string | null;
}): Promise<{
  before: Record<string, unknown> | null;
  after: Record<string, unknown>;
}> {
  const ref = db()
    .collection('businesses')
    .doc(input.merchantId)
    .collection('entitlements')
    .doc(input.featureKey);

  const existing = await ref.get();
  const now = Date.now();

  const after = {
    id: `${input.merchantId}_${input.featureKey}`,
    merchant_id: input.merchantId,
    feature_key: input.featureKey,
    is_enabled: input.isEnabled,
    limit_value: input.limitValue,
    unit: input.unit,
    updated_at: now,
  };

  await ref.set(after, { merge: true });

  return {
    before: existing.exists
      ? (existing.data() as Record<string, unknown>)
      : null,
    after,
  };
}

export async function listStaff(query: {
  search?: string;
  merchantId?: string;
  status?: string;
  role?: string;
  limit: number;
  offset: number;
}): Promise<{ items: Array<Record<string, unknown>>; hasMore: boolean; truncated: boolean }> {
  const [staff, businesses] = await Promise.all([
    query.merchantId
      ? subcollection(query.merchantId, 'app_users', SCAN_CAP).then((items) => ({
          items: items.map((data) => ({
            merchantId: query.merchantId as string,
            data,
          })),
          truncated: false,
        }))
      : scanOwned('app_users'),
    db().collection('businesses').limit(SCAN_CAP).get(),
  ]);

  const names = new Map<string, string>();
  for (const doc of businesses.docs) {
    const data = doc.data() as Record<string, unknown>;
    const name = pickString(data, 'merchant_name', 'name');
    if (name) names.set(doc.id, name);
  }

  const search = (query.search ?? '').trim().toLowerCase();
  const status = (query.status ?? '').trim().toUpperCase();
  const role = (query.role ?? '').trim().toUpperCase();

  const rows = staff.items
    .map(
      (record): Record<string, unknown> => ({
        ...record.data,
        merchant_id: record.merchantId,
        merchant_name: names.get(record.merchantId) ?? null,
      }),
    )
    .filter((row) => {
      if (search.length > 0) {
        const haystack = `${row.phone ?? ''}${row.id ?? ''}`.toLowerCase();
        if (!haystack.includes(search)) return false;
      }
      if (status.length > 0) {
        if (String(row.status ?? '').toUpperCase() !== status) return false;
      }
      if (role.length > 0) {
        if (String(row.role ?? '').toUpperCase() !== role) return false;
      }
      return true;
    })
    .sort(
      (a, b) =>
        ((b.updated_at as number) ?? 0) - ((a.updated_at as number) ?? 0),
    );

  const items = rows.slice(query.offset, query.offset + query.limit);
  return {
    items,
    hasMore: query.offset + items.length < rows.length,
    truncated: staff.truncated,
  };
}

/**
 * The plan catalogue.
 *
 * Firestore stores one flat document per plan — a single price on the document
 * and `features` as an array of keys. The console's contract was shaped by the
 * SQL model, which split those into plans, plan_prices and plan_features. The
 * flat document is mapped up into that shape rather than the other way round,
 * because the reconciliation screen compares feature keys and the mobile app
 * already reads this collection as it stands.
 */
export async function listPlans(): Promise<Array<Record<string, unknown>>> {
  const snapshot = await db().collection('plans').get();

  return snapshot.docs
    .map((doc) => {
      const data = doc.data() as Record<string, unknown>;
      const planCode =
        pickString(data, 'plan_code', 'code', 'planCode') ?? doc.id;
      const amount = pickNumber(
        data,
        'price_cents',
        'priceCents',
        'amount_cents',
        'price',
      );
      const rawFeatures = Array.isArray(data.features) ? data.features : [];
      const isActive = data.is_active !== false && data.active !== false;

      return {
        plan_code: planCode,
        version: pickNumber(data, 'version', 'plan_version') ?? 1,
        name:
          pickString(data, 'display_name', 'name', 'plan_name', 'displayName') ??
          planCode,
        is_active: isActive,
        created_at: pickNumber(data, 'created_at'),
        updated_at: pickNumber(data, 'updated_at'),
        sort_order: pickNumber(data, 'sort_order', 'order', 'position') ?? 999,
        prices:
          amount == null
            ? []
            : [
                {
                  pricing_version: pickNumber(data, 'pricing_version') ?? 1,
                  currency: pickString(data, 'currency') ?? 'MZN',
                  amount,
                  billing_period:
                    pickString(data, 'billing_interval', 'billingInterval') ??
                    'monthly',
                  is_active: isActive,
                  created_at: pickNumber(data, 'created_at'),
                  updated_at: pickNumber(data, 'updated_at'),
                },
              ],
        features: rawFeatures
          .filter((key): key is string => typeof key === 'string')
          .map((key) => ({
            feature_key: key,
            is_enabled: true,
            limit_value:
              key === 'whatsapp'
                ? pickNumber(data, 'whatsapp_monthly_limit', 'whatsappMonthlyLimit')
                : null,
            unit: key === 'whatsapp' ? 'por mes' : null,
            updated_at: pickNumber(data, 'updated_at'),
          })),
      };
    })
    .sort(
      (a, b) =>
        (a.sort_order as number) - (b.sort_order as number) ||
        String(a.plan_code).localeCompare(String(b.plan_code)),
    );
}

/**
 * Writes a plan document.
 *
 * Merged, not replaced: the mobile app reads fields from this collection that
 * the console does not show, and overwriting the document would silently drop
 * them.
 */
export async function upsertPlan(input: {
  planCode: string;
  name: string;
  isActive: boolean;
  version: number;
}): Promise<void> {
  const now = Date.now();
  await db()
    .collection('plans')
    .doc(input.planCode)
    .set(
      {
        plan_code: input.planCode,
        display_name: input.name,
        is_active: input.isActive,
        version: input.version,
        updated_at: now,
        created_at: now,
      },
      { merge: true },
    );
}

export async function upsertPlanPrice(input: {
  planCode: string;
  currency: string;
  amount: number;
  billingPeriod: string;
  pricingVersion: number;
}): Promise<void> {
  await db()
    .collection('plans')
    .doc(input.planCode)
    .set(
      {
        price_cents: input.amount,
        currency: input.currency,
        billing_interval: input.billingPeriod,
        pricing_version: input.pricingVersion,
        updated_at: Date.now(),
      },
      { merge: true },
    );
}

/**
 * Adds or removes a feature key on a plan.
 *
 * The Firestore model has no per-plan feature row to disable, only membership
 * of the `features` array, so disabling means removing the key. Read-modify-
 * write inside a transaction: two operators editing different features of the
 * same plan would otherwise overwrite each other's array.
 */
export async function setPlanFeature(input: {
  planCode: string;
  featureKey: string;
  isEnabled: boolean;
  limitValue: number | null;
}): Promise<{ exists: boolean; features: string[] }> {
  const ref = db().collection('plans').doc(input.planCode);

  return db().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return { exists: false, features: [] };

    const data = snapshot.data() as Record<string, unknown>;
    const current = new Set(
      (Array.isArray(data.features) ? data.features : []).filter(
        (key): key is string => typeof key === 'string',
      ),
    );

    if (input.isEnabled) {
      current.add(input.featureKey);
    } else {
      current.delete(input.featureKey);
    }

    const patch: Record<string, unknown> = {
      features: [...current].sort(),
      updated_at: Date.now(),
    };
    if (input.featureKey === 'whatsapp' && input.limitValue != null) {
      patch.whatsapp_monthly_limit = input.limitValue;
    }

    transaction.set(ref, patch, { merge: true });
    return { exists: true, features: [...current].sort() };
  });
}

/**
 * A count that is allowed to be unavailable.
 *
 * Filtered collection group queries need a declared composite index. Until one
 * is deployed the query fails, and a whole dashboard failing because one tile
 * needs an index is a worse outcome than the tile saying it cannot be
 * computed. The caller reports which ones are missing.
 */
async function safeCount(
  label: string,
  run: () => Promise<number>,
): Promise<{ value: number; available: boolean; label: string }> {
  try {
    return { value: await run(), available: true, label };
  } catch (error) {
    console.warn('admin_summary_metric_unavailable', {
      metric: label,
      message: error instanceof Error ? error.message : String(error),
    });
    return { value: 0, available: false, label };
  }
}

async function countSince(
  collectionId: string,
  field: string,
  since: number,
): Promise<number> {
  const snapshot = await db()
    .collectionGroup(collectionId)
    .where(field, '>=', since)
    .count()
    .get();
  return snapshot.data().count;
}

export type OperationsSummary = Record<string, unknown> & {
  unavailable_metrics: string[];
};

/**
 * The overview figures.
 *
 * Subscription and staff counts come from the same unfiltered collection group
 * scans the merchant list uses, so they need no index and are always
 * available. The time-windowed ones are aggregation queries that do need one,
 * and degrade individually.
 */
export async function getOperationsSummary(): Promise<OperationsSummary> {
  const dayAgo = Date.now() - 24 * 60 * 60 * 1000;

  const [businesses, subscriptions, staff, recovery] = await Promise.all([
    db().collection('businesses').count().get(),
    scanOwned('subscription_state'),
    scanOwned('app_users'),
    scanOwned('recovery_tasks'),
  ]);

  // One business can hold several subscription documents; only the newest
  // describes it today, so the statuses are counted per business, not per row.
  const currentByMerchant = new Map<string, Record<string, unknown>>();
  for (const record of subscriptions.items) {
    const existing = currentByMerchant.get(record.merchantId);
    if (
      !existing ||
      (pickNumber(record.data, 'updated_at') ?? 0) >
        (pickNumber(existing, 'updated_at') ?? 0)
    ) {
      currentByMerchant.set(record.merchantId, record.data);
    }
  }

  let active = 0;
  let trial = 0;
  let attention = 0;
  for (const subscription of currentByMerchant.values()) {
    const status = (pickString(subscription, 'status') ?? '').toUpperCase();
    if (status === 'ACTIVE') active += 1;
    else if (status === 'TRIAL') trial += 1;
    else if (status.length > 0) attention += 1;
  }

  const activeStaff = staff.items.filter(
    (record) => (pickString(record.data, 'status') ?? '').toUpperCase() === 'ACTIVE',
  ).length;

  const openRecovery = recovery.items.filter((record) => {
    const status = (pickString(record.data, 'status') ?? '').toUpperCase();
    return status !== 'DONE' && status !== 'CANCELLED' && status !== 'CLOSED';
  }).length;

  const [usage24h, visits24h, surveys24h, audit24h] = await Promise.all([
    safeCount('usage_events_24h', () =>
      countSince('usage_events', 'created_at', dayAgo),
    ),
    safeCount('visit_reports_24h', () =>
      countSince('visit_reports', 'created_at', dayAgo),
    ),
    safeCount('survey_responses_24h', () =>
      countSince('survey_responses', 'created_at', dayAgo),
    ),
    safeCount('admin_audit_events_24h', async () => {
      const snapshot = await db()
        .collection(ADMIN_AUDIT_COLLECTION)
        .where('created_at', '>=', dayAgo)
        .count()
        .get();
      return snapshot.data().count;
    }),
  ]);

  const lastAudit = await db()
    .collection(ADMIN_AUDIT_COLLECTION)
    .orderBy('created_at', 'desc')
    .limit(1)
    .get()
    .then((snapshot) =>
      snapshot.empty
        ? null
        : pickNumber(snapshot.docs[0].data() as Record<string, unknown>, 'created_at'),
    )
    .catch(() => null);

  const metrics = [usage24h, visits24h, surveys24h, audit24h];

  return {
    merchant_count: businesses.data().count,
    active_subscription_count: active,
    trial_subscription_count: trial,
    attention_subscription_count: attention,
    active_staff_count: activeStaff,
    usage_events_24h: usage24h.value,
    open_recovery_task_count: openRecovery,
    visit_reports_24h: visits24h.value,
    survey_responses_24h: surveys24h.value,
    admin_audit_events_24h: audit24h.value,
    last_admin_audit_at: lastAudit,
    // Reading every usage event to find the newest is not worth one timestamp;
    // the merchant detail page shows it per business, where it is cheap.
    last_usage_event_at: null,
    unavailable_metrics: metrics
      .filter((metric) => !metric.available)
      .map((metric) => metric.label),
  };
}
