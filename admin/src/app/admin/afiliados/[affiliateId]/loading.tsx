import { Skeleton } from '../../ui';

/**
 * Shown while one affiliate's record is in flight.
 *
 * The page blocks on that read: it decides whether the record exists at all,
 * and `notFound()` can only change the body once a status has been flushed.
 * This stands in its place rather than letting the console show an empty frame.
 */
export default function AdminAffiliateLoading() {
  return (
    <div className="card">
      <Skeleton label="A carregar o afiliado…" lines={5} />
    </div>
  );
}
