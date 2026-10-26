import { fetchMyAppointments } from '@/lib/merchant-api';
import { appointmentStatusLabel } from '@/lib/merchant-labels';
import { Badge, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CustomerLink } from '../links';

export const metadata = { title: 'Marcações | MaisUm' };
export const dynamic = 'force-dynamic';

// Stored lowercase by the app; the chips carry what the filter compares, and
// the backend upper-cases both sides before matching.
const FILTERS = [
  { value: '', label: 'Todas' },
  { value: 'SCHEDULED', label: 'Marcadas' },
  { value: 'COMPLETED', label: 'Cumpridas' },
  { value: 'MISSED', label: 'Faltaram' },
  { value: 'CANCELLED', label: 'Canceladas' },
];

export default async function MarcacoesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Marcações"
      subtitle="Quem tem hora marcada, e quem faltou."
      basePath="/negocio/marcacoes"
      searchLabel="Procurar marcações"
      searchPlaceholder="Id do cliente"
      filters={FILTERS}
      singular="marcação"
      plural="marcações"
      emptyMessage="Ainda não há marcações. As que criar na aplicação aparecem aqui."
      rowKey={(row) => row.id}
      fetchPage={fetchMyAppointments}
      columns={[
        { header: 'Quando', cell: (row) => formatDateTime(row.scheduled_date) },
        { header: 'Cliente', cell: (row) => <CustomerLink id={row.customer_id} name={row.customer_name} /> },
        {
          header: 'Estado',
          cell: (row) => (
            <Badge label={appointmentStatusLabel(row.status)} tone={row.status} />
          ),
        },
        {
          header: 'Lembrete',
          cell: (row) =>
            row.reminder_sent === null ? (
              <span className="muted">—</span>
            ) : row.reminder_sent ? (
              'Enviado'
            ) : (
              <span className="muted">Por enviar</span>
            ),
        },
        { header: 'Criada', cell: (row) => formatDateTime(row.created_at) },
      ]}
      footnote="Criar e alterar marcações continua a fazer-se na aplicação."
      searchParams={searchParams}
    />
  );
}
