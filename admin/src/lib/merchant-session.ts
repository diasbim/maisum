import 'server-only';

import { fetchMyBusinesses, type MerchantBusiness } from './merchant-api';
import { getPortalSession } from './session';

export type MerchantSession = {
  uid: string;
  email: string | null;
  /** Every business this account may act as; never empty. */
  businesses: MerchantBusiness[];
  /** The one the portal opens on. */
  active: MerchantBusiness;
};

/**
 * The signed-in business owner, or `null`.
 *
 * Deliberately not a claim check. Most merchants hold no claim at all — the app
 * bootstraps a business under the owner's own uid, and others are reached by
 * the owner field or by phone match on the business document. Asking the API
 * "which businesses am I" is the only answer that agrees with `firestore.rules`
 * for all four paths, so that is what this does.
 */
export async function getMerchantSession(): Promise<MerchantSession | null> {
  const session = await getPortalSession();
  if (!session) return null;

  const businesses = await fetchMyBusinesses();
  if (businesses.length === 0) return null;

  return {
    uid: session.uid,
    email: session.email,
    businesses,
    active: businesses[0],
  };
}
