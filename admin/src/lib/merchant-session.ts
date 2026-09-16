import 'server-only';

import { cache } from 'react';

import { appUserRole, canManageAsOwner } from './admin-claims';
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
 *
 * Wrapped in `cache` so the answer is read once per request. The layout asks
 * it on every page in this area to decide whether to render at all, and the
 * screens that need the business's name — the affiliate ones, to compose the
 * message a code is shared with — would otherwise pay for a second call to
 * `/merchant/businesses` to learn something the layout already knew.
 */
export const getMerchantSession = cache(
  async (): Promise<MerchantSession | null> => {
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
  },
);

/**
 * Whether this person may change things, and what to tell them if not.
 *
 * Reads the token's own role and nothing else — no API call, so a page can ask
 * it beside its data without paying for a second round trip. A manager sees
 * every affiliate screen and none of the controls, with the reason written out
 * rather than left as a button that fails when pressed.
 *
 * Deliberately not a gate. The API refuses the same writes for the same
 * person, in Portuguese, and that refusal is the one that counts.
 */
export type MerchantPermissions = {
  role: 'OWNER' | 'STAFF';
  canManage: boolean;
  /** Why the controls are absent, or null when they are not. */
  reason: string | null;
};

export const STAFF_READ_ONLY_REASON =
  'Só o responsável do negócio pode alterar afiliados, códigos e recompensas.';

export async function getMerchantPermissions(): Promise<MerchantPermissions> {
  const session = await getPortalSession();
  if (!session) {
    return {
      role: 'STAFF',
      canManage: false,
      reason: 'A sessão expirou. Entre novamente para continuar.',
    };
  }

  const canManage = canManageAsOwner(session.claims);
  return {
    role: appUserRole(session.claims),
    canManage,
    reason: canManage ? null : STAFF_READ_ONLY_REASON,
  };
}
