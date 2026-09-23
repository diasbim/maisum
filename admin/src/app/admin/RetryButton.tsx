'use client';

import { useRouter } from 'next/navigation';
import { useTransition } from 'react';

/**
 * Re-runs the server render for a panel that failed.
 *
 * The panels are async server components, so recovering from a failed fetch
 * means asking the router to render the route again rather than re-running
 * anything on the client. Without this the only way out of a failed panel is
 * knowing to reload the browser, which is not something an interface should
 * make an operator work out for themselves.
 */
export function RetryButton({ label = 'Tentar de novo' }: { label?: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  return (
    <button
      className="btn btn-outline btn-sm"
      type="button"
      disabled={pending}
      aria-busy={pending}
      onClick={() => startTransition(() => router.refresh())}
    >
      {pending ? 'A tentar…' : label}
    </button>
  );
}
