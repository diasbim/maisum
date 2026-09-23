import { fetchMyVisitReports } from '@/lib/merchant-api';
import { visitResultLabel } from '@/lib/merchant-labels';
import { Badge, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CustomerLink } from '../links';

export const metadata = { title: 'Relatórios de visita | MaisUm' };
export const dynamic = 'force-dynamic';

// The stored values carry a space ('Needs Promotion'), and the filter matches
// on the upper-cased string, so that is what the chips send.
const FILTERS = [
  { value: '', label: 'Todos' },
  { value: 'RETURNED', label: 'Voltaram' },
  { value: 'INTERESTED', label: 'Interessados' },
  { value: 'NEEDS PROMOTION', label: 'Só com promoção' },
  { value: 'LOST CUSTOMER', label: 'Perdidos' },
];

function resultTone(result: string | null): string {
  const value = (result ?? '').toUpperCase();
  if (value === 'RETURNED') return 'ACTIVE';
  if (value === 'LOST CUSTOMER' || value === 'WRONG NUMBER') return 'FAILED';
  return 'PENDING';
}

export default async function VisitasPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Relatórios de visita"
      subtitle="O que aconteceu quando a equipa contactou um cliente em risco."
      basePath="/negocio/visitas"
      searchLabel="Procurar relatórios"
      searchPlaceholder="Id do cliente ou nota"
      filters={FILTERS}
      singular="relatório"
      plural="relatórios"
      emptyMessage="Ainda não há relatórios de visita. São escritos na aplicação, ao fechar uma tarefa."
      rowKey={(row) => row.id}
      fetchPage={fetchMyVisitReports}
      columns={[
        { header: 'Quando', cell: (row) => formatDateTime(row.visited_at) },
        { header: 'Cliente', cell: (row) => <CustomerLink id={row.customer_id} name={row.customer_name} /> },
        {
          header: 'Resultado',
          cell: (row) => (
            <Badge label={visitResultLabel(row.result)} tone={resultTone(row.result)} />
          ),
        },
        {
          header: 'Nota',
          cell: (row) => row.notes ?? <span className="muted">—</span>,
        },
      ]}
      searchParams={searchParams}
    />
  );
}
