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
  type StaffRecord,
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
