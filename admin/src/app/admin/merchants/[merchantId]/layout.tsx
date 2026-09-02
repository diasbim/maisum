import Link from 'next/link';
import { notFound } from 'next/navigation';

import { ErrorState, PageHeader, load } from '../../ui';
import { MerchantTabs } from './MerchantTabs';
import { getMerchant } from './data';

/**
 * Heading and tabs, shared by the three merchant views.
 *
 * The 404 check lives here so a missing merchant is caught once instead of in
 * each tab. An API failure is deliberately not treated as a 404: rendering
 * "does not exist" during an outage would send an operator hunting for a data
 * problem that is really a downed service.
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

  if (!result.error && result.data === null) {
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
