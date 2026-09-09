import { fetchMySurveys } from '@/lib/merchant-api';
import { Badge, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';

export const metadata = { title: 'Inquéritos | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'INACTIVE', label: 'Inativos' },
];

export default async function InqueritosPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Inquéritos"
      subtitle="O que perguntou aos seus clientes, e quantos responderam."
      basePath="/negocio/inqueritos"
      searchLabel="Procurar inquéritos"
      searchPlaceholder="Título ou descrição"
      filters={FILTERS}
      singular="inquérito"
      plural="inquéritos"
      emptyMessage="Ainda não criou nenhum inquérito. Os que criar na aplicação aparecem aqui."
      rowKey={(row) => row.id}
      fetchPage={fetchMySurveys}
      columns={[
        {
          header: 'Inquérito',
          cell: (row) => (
            <>
              <strong>{row.title ?? row.id}</strong>
              {row.description ? (
                <>
                  <br />
                  <span className="micro">{row.description}</span>
                </>
              ) : null}
            </>
          ),
        },
        {
          // The only reason to open this list: a survey nobody answered and
          // one answered two hundred times look identical without it.
          header: 'Respostas',
          numeric: true,
          cell: (row) => row.response_count.toLocaleString('pt-PT'),
        },
        {
          header: 'Estado',
          cell: (row) => (
            <Badge
              label={row.is_active === false ? 'Inativo' : 'Ativo'}
              tone={row.is_active === false ? 'INACTIVE' : 'ACTIVE'}
            />
          ),
        },
        { header: 'Criado', cell: (row) => formatDateTime(row.created_at) },
      ]}
      footnote="Criar e editar inquéritos continua a fazer-se na aplicação."
      searchParams={searchParams}
    />
  );
}
