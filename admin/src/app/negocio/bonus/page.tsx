import { fetchMyReturnBonuses } from '@/lib/merchant-api';
import { bonusStatusLabel, bonusTypeLabel } from '@/lib/merchant-labels';
import { Badge, formatAmount, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CustomerLink } from '../links';

export const metadata = { title: 'Bónus de retorno | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Por usar' },
  { value: 'REDEEMED', label: 'Usados' },
  { value: 'EXPIRED', label: 'Expirados' },
];

/**
 * A bonus is worth different things depending on its type.
 *
 * A discount is money and a points bonus is points; printing both as "50"
 * with no unit would make the column meaningless.
 */
function bonusValue(type: string | null, value: number | null) {
  if (value === null) return <span className="muted">—</span>;
  const kind = (type ?? '').toUpperCase();
  if (kind === 'DISCOUNT') return formatAmount(value, 'MZN');
  if (kind === 'EXTRA_POINTS') return `${value.toLocaleString('pt-PT')} pontos`;
  return value.toLocaleString('pt-PT');
}

export default async function BonusPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Bónus de retorno"
      subtitle="O que ofereceu para trazer um cliente de volta, e se resultou."
      basePath="/negocio/bonus"
      searchLabel="Procurar bónus"
      searchPlaceholder="Id do cliente"
      filters={FILTERS}
      singular="bónus"
      plural="bónus"
      emptyMessage="Ainda não foi emitido nenhum bónus de retorno."
      rowKey={(row) => row.id}
      fetchPage={fetchMyReturnBonuses}
      columns={[
        { header: 'Emitido', cell: (row) => formatDateTime(row.issued_at) },
        { header: 'Cliente', cell: (row) => <CustomerLink id={row.customer_id} /> },
        { header: 'Tipo', cell: (row) => bonusTypeLabel(row.type) ?? '—' },
        {
          header: 'Valor',
          numeric: true,
          cell: (row) => bonusValue(row.type, row.value),
        },
        {
          header: 'Estado',
          cell: (row) => <Badge label={bonusStatusLabel(row.status)} tone={row.status} />,
        },
        {
          header: 'Válido até',
          cell: (row) => formatDateTime(row.expires_at),
        },
      ]}
      searchParams={searchParams}
    />
  );
}
