import { redirect } from 'next/navigation';

import { resolvePortalHome } from '@/lib/portal-home';

/**
 * The bare address, routed to whichever area the visitor belongs in.
 *
 * It used to redirect to `/admin` unconditionally, which was right while the
 * console was the only thing here. It is not right now: a business owner
 * typing the address was bounced off the console's gate and told they had no
 * access to the portal they had just signed into.
 */
export default async function RootPage() {
  redirect(await resolvePortalHome());
}
