import { fetchMyRecoveryTasks } from '@/lib/merchant-api';
import { taskPriorityLabel, taskStatusLabel } from '@/lib/merchant-labels';
import { Badge, formatDateTime } from '../../admin/ui';
import { RecordScreen } from '../RecordScreen';
import { CompleteTask } from '../CompleteTask';
import { CustomerLink } from '../links';

export const metadata = { title: 'Tarefas de recuperação | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Todas' },
  { value: 'OPEN', label: 'Pendentes' },
  { value: 'COMPLETED', label: 'Concluídas' },
];

function priorityTone(priority: string | null): string {
  switch ((priority ?? '').toUpperCase()) {
    case 'HIGH':
      return 'FAILED';
    case 'MEDIUM':
      return 'PENDING';
    default:
      return '';
  }
}

export default async function TarefasPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <RecordScreen
      title="Tarefas de recuperação"
      subtitle="Quem contactar para trazer de volta, e o que já foi feito."
      basePath="/negocio/tarefas"
      searchLabel="Procurar tarefas"
      searchPlaceholder="Id do cliente ou nota"
      filters={FILTERS}
      singular="tarefa"
      plural="tarefas"
      emptyMessage="Não há tarefas de recuperação. São criadas quando um cliente passa a estar em risco."
      rowKey={(row) => row.id}
      fetchPage={fetchMyRecoveryTasks}
      columns={[
        { header: 'Cliente', cell: (row) => <CustomerLink id={row.customer_id} name={row.customer_name} /> },
        {
          header: 'Prioridade',
          cell: (row) => (
            <Badge label={taskPriorityLabel(row.priority)} tone={priorityTone(row.priority)} />
          ),
        },
        {
          header: 'Estado',
          cell: (row) => (
            <Badge
              label={taskStatusLabel(row.status)}
              tone={(row.status ?? '').toUpperCase() === 'COMPLETED' ? 'ACTIVE' : 'PENDING'}
            />
          ),
        },
        { header: 'Para quando', cell: (row) => formatDateTime(row.due_at) },
        {
          header: 'Nota',
          cell: (row) => row.notes ?? <span className="muted">—</span>,
        },
        {
          header: '',
          cell: (row) =>
            (row.status ?? '').toUpperCase() === 'COMPLETED' ? null : (
              <CompleteTask taskId={row.id} customerName={row.customer_name} />
            ),
        },
      ]}
      footnote="Concluir uma tarefa é a única coisa que se altera aqui. Registar o contacto — a chamada, a mensagem, a visita — continua a fazer-se na aplicação."
      searchParams={searchParams}
    />
  );
}
