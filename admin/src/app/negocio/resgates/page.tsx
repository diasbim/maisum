import { fetchMyRedemptions } from '@/lib/merchant-api';
import { Badge, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CustomerLink } from '../links';

export const metadata = { title: 'Resgates | MaisUm' };
export const dynamic = 'force-dynamic';

export default async function ResgatesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Resgates"
      subtitle="As recompensas que os seus clientes já trocaram por pontos."
      basePath="/negocio/resgates"
      searchLabel="Procurar resgates"
      searchPlaceholder="Id do cliente ou da recompensa"
      singular="resgate"
      plural="resgates"
      emptyMessage="Ainda ninguém trocou pontos por uma recompensa."
      rowKey={(row) => row.id}
      fetchPage={fetchMyRedemptions}
      columns={[
        { header: 'Data', cell: (row) => formatDateTime(row.redeemed_at) },
        { header: 'Cliente', cell: (row) => <CustomerLink id={row.customer_id} /> },
        {
          header: 'Recompensa',
          cell: (row) =>
            row.reward_id ? <code>{row.reward_id}</code> : <span className="muted">—</span>,
        },
        {
          header: 'Pontos gastos',
          numeric: true,
          cell: (row) =>
            row.points_spent === null ? '—' : row.points_spent.toLocaleString('pt-PT'),
        },
        {
          header: 'Estado',
          // No translation table: the app writes no fixed vocabulary here yet,
          // and inventing one would be guessing at values that do not exist.
          cell: (row) => <Badge label={row.status} tone={row.status} />,
        },
      ]}
      searchParams={searchParams}
    />
  );
}
