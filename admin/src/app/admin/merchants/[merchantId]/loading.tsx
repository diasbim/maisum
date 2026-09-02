import { Skeleton } from '../../ui';

/**
 * Shown while a merchant's tab content is in flight.
 *
 * This boundary sits below the merchant layout, deliberately. There used to be
 * one at `/admin` covering everything, which flushed the shell — and with it a
 * 200 — before the layout had finished asking whether the merchant exists. By
 * the time `notFound()` ran, the status was already sent, so a missing
 * merchant answered 200 while rendering the not-found page.
 *
 * Below the layout, the layout still blocks long enough to decide, and the tab
 * content still gets a placeholder rather than arriving cold. The other
 * sections need no equivalent: their pages return a shell immediately and
 * stream each panel into its own boundary.
 */
export default function MerchantLoading() {
  return (
    <div className="card">
      <Skeleton lines={5} />
    </div>
  );
}
