import { Suspense } from 'react';

import { fetchMySales } from '@/lib/merchant-api';
import { Card, DefinitionList, Panel, Skeleton, formatAmount, formatDateTime, load } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CustomerLink, SaleStatus } from '../links';

export const metadata = { title: 'Vendas | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Todas' },
  { value: 'CONFIRMED', label: 'Confirmadas' },
  { value: 'PENDING', label: 'Por confirmar' },
  { value: 'REJECTED', label: 'Rejeitadas' },
];

/**
 * The takings, over every sale rather than the page.
 *
 * Its own Suspense boundary and its own request: the number a business opens
 * this page for should not wait behind the table, and the table should not
 * wait behind it.
 */
async function Totals({ status }: { status: string }) {
  const result = await load(() =>
    fetchMySales({ status: status || undefined, limit: 1, offset: 0 }),
  );
  if (result.error !== null) return null;

  const { totals } = result.data;
  return (
    <Card title="No total">
      <DefinitionList
        entries={[
          ['Vendas', totals.count.toLocaleString('pt-PT')],
          ['Valor', formatAmount(totals.amount, 'MZN')],
          ['Pontos atribuídos', totals.points.toLocaleString('pt-PT')],
        ]}
      />
    </Card>
  );
}

export default async function VendasPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const status = String(params.status ?? '').toUpperCase();

  return (
    <RecordScreen
      title="Vendas"
      subtitle="O que passou pela caixa, da mais recente para a mais antiga."
      basePath="/negocio/vendas"
      searchLabel="Procurar vendas"
      searchPlaceholder="Id da venda ou do cliente"
      filters={FILTERS}
      singular="venda"
      plural="vendas"
      emptyMessage="Ainda não há vendas registadas. As que fizer na aplicação aparecem aqui."
      filteredEmptyMessage="Nenhuma venda corresponde a esta procura."
      rowKey={(sale) => sale.id}
      fetchPage={fetchMySales}
      summary={
        <Panel>
          <Suspense fallback={<Skeleton lines={3} />}>
            <Totals status={status} />
          </Suspense>
        </Panel>
      }
      columns={[
        { header: 'Data', cell: (sale) => formatDateTime(sale.created_at) },
        { header: 'Cliente', cell: (sale) => <CustomerLink id={sale.customer_id} /> },
        { header: 'Valor', numeric: true, cell: (sale) => formatAmount(sale.amount, 'MZN') },
        {
          header: 'Pontos',
          numeric: true,
          cell: (sale) => (sale.points ?? 0).toLocaleString('pt-PT'),
        },
        { header: 'Estado', cell: (sale) => <SaleStatus sale={sale} /> },
      ]}
      searchParams={searchParams}
    />
  );
}
