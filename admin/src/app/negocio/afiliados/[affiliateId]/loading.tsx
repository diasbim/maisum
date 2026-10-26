import { Skeleton } from '../../../admin/ui';

/**
 * Shown while one affiliate's record is in flight.
 *
 * The page blocks on that first read — it decides whether the affiliate exists
 * at all, and `notFound()` can only change the body once a status has been
 * flushed — so this stands in its place. The panels below it stream into their
 * own boundaries and need nothing here.
 */
export default function AffiliateLoading() {
  return (
    <div className="card">
      <Skeleton label="A carregar o afiliado…" lines={5} />
    </div>
  );
}
