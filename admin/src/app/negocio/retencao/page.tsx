import { fetchMyRiskScores } from '@/lib/merchant-api';
import { riskLevelLabel } from '@/lib/merchant-labels';
import { Badge, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CustomerLink } from '../links';

export const metadata = { title: 'Clientes em risco | MaisUm' };
export const dynamic = 'force-dynamic';

// Stored as colour names, which is why the chips say what the colour means.
const FILTERS = [
  { value: '', label: 'Todos' },
  { value: 'RED', label: 'Críticos' },
  { value: 'ORANGE', label: 'Alerta' },
  { value: 'YELLOW', label: 'Atenção' },
  { value: 'GREEN', label: 'Saudáveis' },
];

/**
 * Red and orange are bad news; the badge should say so without being read.
 *
 * The stored value is a colour name, so it cannot be handed to `tone`
 * directly — 'red' means danger here, but 'GREEN' is not one of the tones the
 * badge knows, and 'YELLOW' is not either.
 */
function riskTone(level: string | null): string {
  switch ((level ?? '').toUpperCase()) {
    case 'RED':
      return 'FAILED';
    case 'ORANGE':
    case 'YELLOW':
      return 'PENDING';
    case 'GREEN':
      return 'ACTIVE';
    default:
      return '';
  }
}

export default async function RetencaoPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Clientes em risco"
      subtitle="Quem está a deixar de vir, do mais urgente para o menos."
      basePath="/negocio/retencao"
      searchLabel="Procurar"
      searchPlaceholder="Id do cliente"
      searchable={false}
      filters={FILTERS}
      singular="cliente"
      plural="clientes"
      emptyMessage="Ainda não há classificações de risco. São calculadas à medida que os clientes visitam."
      rowKey={(row) => row.id}
      fetchPage={fetchMyRiskScores}
      columns={[
        { header: 'Cliente', cell: (row) => <CustomerLink id={row.customer_id} name={row.customer_name} /> },
        {
          header: 'Risco',
          cell: (row) => (
            <Badge label={riskLevelLabel(row.risk_level)} tone={riskTone(row.risk_level)} />
          ),
        },
        {
          header: 'Dias sem vir',
          numeric: true,
          cell: (row) => row.days_since_visit.toLocaleString('pt-PT'),
        },
        {
          header: 'Prioridade',
          numeric: true,
          cell: (row) => row.priority.toLocaleString('pt-PT'),
        },
        { header: 'Calculado', cell: (row) => formatDateTime(row.updated_at) },
      ]}
      footnote="Esta lista é calculada pelo sistema. Para agir sobre ela, veja as tarefas de recuperação."
      searchParams={searchParams}
    />
  );
}
