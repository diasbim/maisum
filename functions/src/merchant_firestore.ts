import * as admin from 'firebase-admin';

import {
  businessGrantsAccess,
  canAccessBusiness,
  merchantIdsFromClaims,
  type MerchantIdentity,
} from './merchant_access';

/**
 * Finding the businesses a signed-in person may act as.
 *
 * `resolveMerchantId()` in index.ts answers a narrower question — it falls back
 * to the caller's uid, which is right for the app's bootstrap case and wrong
 * for everyone else. A merchant matched by phone, or named as owner of a
 * business whose id is not their uid, would be handed their own uid as a
 * business id and see nothing.
 *
 * So this asks Firestore instead of guessing, over the same four paths the
 * rules allow.
 */

const db = () => admin.firestore();

export type AccessibleBusiness = {
  id: string;
  name: string | null;
  data: Record<string, unknown>;
};

function nameOf(data: Record<string, unknown>): string | null {
  const candidates = ['merchant_name', 'name', 'business_name'];
  for (const key of candidates) {
    const value = data[key];
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return null;
}

async function getBusiness(
  merchantId: string,
): Promise<AccessibleBusiness | null> {
  const snapshot = await db().collection('businesses').doc(merchantId).get();
  if (!snapshot.exists) return null;
  const data = (snapshot.data() ?? {}) as Record<string, unknown>;
  return { id: snapshot.id, name: nameOf(data), data };
}

/**
 * Businesses matched by a field on the document rather than by the token.
 *
 * Each is a single indexed equality query. Failures are swallowed per query:
 * a missing index on one path should not deny access that another path grants.
 */
async function queryBy(
  field: string,
  value: string,
): Promise<AccessibleBusiness[]> {
  if (!value) return [];
  try {
    const snapshot = await db()
      .collection('businesses')
      .where(field, '==', value)
      .limit(25)
      .get();
    return snapshot.docs.map((doc) => {
      const data = (doc.data() ?? {}) as Record<string, unknown>;
      return { id: doc.id, name: nameOf(data), data };
    });
  } catch (error) {
    console.error('merchant_lookup_failed', {
      event: 'merchant_lookup_failed',
      field,
      error_message: error instanceof Error ? error.message : String(error),
    });
    return [];
  }
}

/**
 * Every business this person may act as, most-authoritative first.
 *
 * Claims lead because they are deliberate: someone set them. The document
 * paths follow, and the caller opens on the first entry.
 */
export async function listAccessibleBusinesses(
  user: MerchantIdentity,
  claims: unknown,
): Promise<AccessibleBusiness[]> {
  const found = new Map<string, AccessibleBusiness>();
  const remember = (business: AccessibleBusiness | null) => {
    if (business && !found.has(business.id)) found.set(business.id, business);
  };

  // 1. What the token asserts.
  for (const merchantId of merchantIdsFromClaims(claims)) {
    remember(await getBusiness(merchantId));
  }

  // 2. The business the app bootstraps under the owner's own uid.
  remember(await getBusiness(user.uid));

  // 3 and 4. Named as owner, or matched by the phone they signed in with.
  const [byOwner, byUid, byPhone] = await Promise.all([
    queryBy('owner_user_id', user.uid),
    queryBy('firebase_uid', user.uid),
    user.phoneNumber ? queryBy('phone', user.phoneNumber) : Promise.resolve([]),
  ]);
  for (const business of [...byOwner, ...byUid, ...byPhone]) {
    // Re-checked rather than trusted: the query says the field matched, this
    // says the match is one the rules would also accept.
    if (businessGrantsAccess(business.data, user)) remember(business);
  }

  return [...found.values()];
}

/**
 * Confirms a specific business, for a request that names one.
 *
 * Reads the document and asks the same predicate, so a caller cannot reach a
 * business by guessing its id.
 */
export async function authorizeBusiness(
  merchantId: string,
  user: MerchantIdentity,
  claims: unknown,
): Promise<AccessibleBusiness | null> {
  const business = await getBusiness(merchantId);
  // A business that does not exist is still authorized when the id is the
  // caller's own uid: that is the state right before the app bootstraps it.
  if (!canAccessBusiness(merchantId, claims, business?.data ?? null, user)) {
    return null;
  }
  return business;
}
