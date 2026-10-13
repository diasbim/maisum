import Link from 'next/link';
import { notFound } from 'next/navigation';

import { ErrorState, PageHeader, load } from '../../ui';
import { MerchantTabs } from './MerchantTabs';
import { getMerchant } from './data';

/**
 * Whether the merchant exists at all.
 *
 * An API failure is deliberately not treated as a 404: rendering "does not
 * exist" during an outage would send an operator hunting for a data problem
 * that is really a downed service.
 */
function isMissing(result: { error: string | null; data: unknown }): boolean {
  return !result.error && result.data === null;
}

/**
 * Heading and tabs, shared by the three merchant views.
 *
 * The 404 check lives here so a missing merchant is caught once instead of in
 * each tab. It has to happen before anything of this route is flushed, or the
 * status is already sent and `notFound()` can only change the body — which is
 * why the Suspense boundary for the tab content sits below this layout rather
 * than at `/admin`. See `loading.tsx` beside this file.
 */
export default async function MerchantLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ merchantId: string }>;
}) {
  const { merchantId } = await params;
  const result = await load(() => getMerchant(merchantId));

  if (isMissing(result)) {
    notFound();
  }

  const merchant = result.data;

  return (
    <>
      <PageHeader
        title={merchant?.name || merchantId}
        subtitle={merchant ? merchant.id : undefined}
        action={
          <Link className="btn btn-outline btn-sm" href="/admin/merchants">
            ← Todos os negócios
          </Link>
        }
      />

      <MerchantTabs merchantId={merchantId} />

      {result.error ? <ErrorState message={result.error} /> : children}
    </>
  );
}
