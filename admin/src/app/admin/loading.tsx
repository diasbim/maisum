import { Skeleton } from './ui';

/**
 * Shown while a navigation's server render is in flight.
 *
 * Individual panels have their own Suspense boundaries; this one covers the gap
 * before any of them exist, so moving between sections never leaves the content
 * area blank.
 */
export default function AdminLoading() {
  return (
    <div>
      <div
        className="skeleton skeleton--line"
        style={{ width: 240, height: 28, marginBottom: 20 }}
      />
      <div className="card">
        <Skeleton lines={5} />
      </div>
    </div>
  );
}
