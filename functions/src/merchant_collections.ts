import * as admin from 'firebase-admin';

import {
  selectCatalog,
  selectCustomers,
  selectRewards,
  selectStaff,
  toCatalogItem,
  toCustomer,
  toReward,
  toStaff,
  type CatalogItemRecord,
  type CustomerRecord,
  type RecordPage,
  type RecordQuery,
  type RewardRecord,
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
): Promise<{ docs: Array<{ id: string; data: Record<string, unknown> }>; truncated: boolean }> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection(collectionId)
    .limit(MERCHANT_SCAN_CAP + 1)
    .get();

  const truncated = snapshot.size > MERCHANT_SCAN_CAP;
  const docs = truncated ? snapshot.docs.slice(0, MERCHANT_SCAN_CAP) : snapshot.docs;

  return {
    docs: docs.map((doc) => ({
      id: doc.id,
      data: (doc.data() ?? {}) as Record<string, unknown>,
    })),
    truncated,
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
): Promise<Array<Record<string, unknown>>> {
  const snapshot = await db()
    .collection('businesses')
    .doc(merchantId)
    .collection('sales')
    .where('customer_id', '==', customerId)
    .limit(200)
    .get();

  return snapshot.docs
    .map((doc) => {
      const data = (doc.data() ?? {}) as Record<string, unknown>;
      const at = data.created_at;
      return {
        id: doc.id,
        amount: typeof data.amount === 'number' ? data.amount : null,
        points: typeof data.points === 'number' ? data.points : null,
        created_at: typeof at === 'number' && at > 0 ? at : null,
        // Carried through because a cancelled sale is still a row in this
        // collection: showing it as a plain visit would overstate the history.
        cancellation_status:
          typeof data.cancellation_status === 'string'
            ? data.cancellation_status
            : null,
        confirmation_status:
          typeof data.confirmation_status === 'string'
            ? data.confirmation_status
            : null,
      };
    })
    .sort((a, b) => ((b.created_at as number) ?? 0) - ((a.created_at as number) ?? 0))
    .slice(0, limit);
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
