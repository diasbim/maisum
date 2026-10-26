import Link from 'next/link';

import { fetchMySurveyResponses, fetchMySurveys } from '@/lib/merchant-api';
import { surveyChannelLabel } from '@/lib/merchant-labels';
import { Badge, formatDateTime } from '../../../admin/ui';
import { RecordScreen } from '../../RecordScreen';
import { CustomerLink } from '../../links';

export const metadata = { title: 'Respostas aos inquéritos | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * What customers actually said.
 *
 * The inquéritos list has only ever shown a count, which tells a business that
 * people replied and nothing about what they replied — so the one reason to
 * run a survey never reached the portal at all. This is that half.
 *
 * The chips filter by survey id rather than by a state, which is why the
 * screen opts out of the upper-casing every other list wants: folding a
 * lower-case id would match nothing.
 */
export default async function RespostasPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  // One extra read so the chips can say "Porque não voltou?" instead of a uuid.
  // A survey list that fails is not a reason to withhold the answers, so this
  // degrades to a single "Todos" chip rather than to an error.
  let filters = [{ value: '', label: 'Todos' }];
  try {
    const surveys = await fetchMySurveys({ limit: 25 });
    filters = [
      { value: '', label: 'Todos' },
      ...surveys.items
        .filter((survey) => survey.response_count > 0)
        .map((survey) => ({
          value: survey.id,
          label: survey.title ?? survey.id,
        })),
    ];
  } catch {
    filters = [{ value: '', label: 'Todos' }];
  }

  return (
    <RecordScreen
      title="Respostas aos inquéritos"
      subtitle="O que os seus clientes responderam, pergunta a pergunta."
      basePath="/negocio/inqueritos/respostas"
      searchLabel="Procurar respostas"
      searchPlaceholder="Nome do cliente ou o que respondeu"
      filters={filters.length > 1 ? filters : undefined}
      uppercaseStatus={false}
      singular="resposta"
      plural="respostas"
      emptyMessage="Ainda não há respostas. As que registar na aplicação aparecem aqui."
      filteredEmptyMessage="Nenhuma resposta corresponde a esta procura."
      rowKey={(row) => row.id}
      fetchPage={fetchMySurveyResponses}
      columns={[
        {
          header: 'Quando',
          cell: (row) => formatDateTime(row.submitted_at),
        },
        {
          header: 'Cliente',
          cell: (row) =>
            row.customer_id === null ? (
              // Not an error and not a gap: a response can be given anonymously
              // on purpose, and saying so is more use than an em dash.
              <span className="muted">Anónimo</span>
            ) : (
              <CustomerLink id={row.customer_id} name={row.customer_name} />
            ),
        },
        {
          header: 'Inquérito',
          cell: (row) => row.survey_title ?? <span className="muted">—</span>,
        },
        {
          header: 'Como chegou',
          cell: (row) => <Badge label={surveyChannelLabel(row.channel)} />,
        },
        {
          header: 'Respostas',
          cell: (row) =>
            row.answers.length === 0 ? (
              <span className="muted">Sem respostas registadas</span>
            ) : (
              <dl className="answers">
                {row.answers.map((answer, index) => (
                  <div key={`${row.id}-${answer.question_id ?? index}`}>
                    <dt className="micro">
                      {answer.question_text ?? 'Pergunta removida'}
                    </dt>
                    <dd>
                      {answer.answer ?? (
                        <span className="muted">Sem resposta</span>
                      )}
                    </dd>
                  </div>
                ))}
              </dl>
            ),
        },
      ]}
      summary={
        <p className="micro">
          <Link href="/negocio/inqueritos">← Voltar aos inquéritos</Link>
        </p>
      }
      footnote="Registar respostas continua a fazer-se na aplicação."
      searchParams={searchParams}
    />
  );
}
