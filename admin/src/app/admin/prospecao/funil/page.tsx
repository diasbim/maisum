import Link from 'next/link';
import { Suspense } from 'react';

import { fetchFunnel, type FunnelDto } from '@/lib/prospecting-api';
import {
  Card,
  EmptyState,
  ErrorState,
  MetricsSkeleton,
  PageHeader,
  Panel,
  load,
} from '../../ui';

export const metadata = { title: 'Funil de prospeção | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * Where the leads went, and the two numbers that decide what to do next.
 *
 * Not a dashboard. The module was built without AI on the argument that the
 * open question is whether prospecting converts at all, and this is the screen
 * that answers it — so it is written to be *read as an argument*, not as a wall
 * of figures. Each stage says how many got there and what share of the stage
 * before it that is, because a funnel's only interesting number is where it
 * narrows.
 *
 * Two things this screen is careful about:
 *
 * A rate with no denominator is shown as "—", never as 0%. Nobody having
 * reached a stage is a different statement from nobody having converted, and
 * printing 0% asserts the second when only the first is true.
 *
 * The "what this says" panel at the bottom states a decision rule rather than
 * a score. An operator looking at a low reply rate should leave knowing that
 * the next move is another template, not a meeting about AI.
 */

const PROSPECTING = '/admin/prospecao';

function percent(value: number | null): string {
  if (value === null) return '—';
  return `${(value * 100).toFixed(1)}%`;
}

function ratio(value: number | null): string {
  if (value === null) return '—';
  return `${value.toFixed(1)}×`;
}

/* ------------------------------------------------------------------ stages */

function Stages({ funnel }: { funnel: FunnelDto }) {
  if (funnel.total === 0) {
    return (
      <EmptyState
        action={<Link href={PROSPECTING}>Procurar negócios</Link>}
        message="Ainda não há leads. O funil aparece depois da primeira campanha."
      />
    );
  }

  return (
    <div className="card card--flush scroll-x">
      <table>
        <thead>
          <tr>
            <th scope="col">Etapa</th>
            <th className="num" scope="col">
              Chegaram
            </th>
            <th className="num" scope="col">
              Da etapa anterior
            </th>
            <th className="num" scope="col">
              Do total
            </th>
          </tr>
        </thead>
        <tbody>
          {funnel.stages.map((stage) => (
            <tr key={stage.status}>
              <th scope="row">{stage.label}</th>
              <td className="num">{stage.reached}</td>
              <td className="num">{percent(stage.conversion_from_previous)}</td>
              <td className="num">{percent(stage.conversion_from_start)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ------------------------------------------------------------------- exits */

function Exits({ funnel }: { funnel: FunnelDto }) {
  if (funnel.exits.length === 0) {
    return <EmptyState message="Nenhum lead saiu do funil até agora." />;
  }

  return (
    <div className="grid">
      {funnel.exits.map((exit) => (
        <Card key={exit.status} title={exit.label}>
          <p className="metric">{exit.count}</p>
        </Card>
      ))}
    </div>
  );
}

/* --------------------------------------------------------------- templates */

/**
 * Which message works, which is the first thing to fix when replies are low.
 *
 * A template is attributed on *send*, not on generate, and only the first one
 * sent to a lead counts — so a follow-up cannot take credit for a reply the
 * first message won.
 *
 * Rates under the sample bar are shown with the number of sends beside them
 * and marked plainly. One reply out of two is fifty percent and means nothing,
 * and a table that ranked it first would send an operator off to rewrite the
 * template that is actually working.
 */
function Templates({ funnel }: { funnel: FunnelDto }) {
  if (funnel.templates.length === 0) {
    return (
      <EmptyState message="Ainda não foi enviada nenhuma mensagem. A comparação aparece quando registar o primeiro envio." />
    );
  }

  const anyConclusive = funnel.templates.some((entry) => entry.conclusive);

  return (
    <>
      {anyConclusive ? null : (
        <p className="micro">
          Nenhum modelo tem ainda {funnel.min_sends_to_compare} envios. Até lá as
          percentagens são ruído — vale a pena continuar a enviar antes de
          reescrever seja o que for.
        </p>
      )}

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Modelo</th>
              <th className="num" scope="col">
                Enviadas
              </th>
              <th className="num" scope="col">
                Respostas
              </th>
              <th className="num" scope="col">
                Taxa
              </th>
            </tr>
          </thead>
          <tbody>
            {funnel.templates.map((entry) => (
              <tr key={entry.template_id}>
                <th scope="row">
                  <code className="inline">{entry.template_id}</code>
                  {entry.conclusive ? null : (
                    <div className="micro">Amostra pequena</div>
                  )}
                </th>
                <td className="num">{entry.sent}</td>
                <td className="num">{entry.replied}</td>
                <td className="num">{percent(entry.reply_rate)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

/* ----------------------------------------------------------------- signals */

/**
 * The decision rule, written where the numbers are.
 *
 * Deliberately prescriptive. "Reply rate: 4%" tells an operator nothing they
 * can act on; "the problem is the message, try another template" does.
 */
function Signals({ funnel }: { funnel: FunnelDto }) {
  const { replyRate, bandSeparation } = funnel.signals;

  const replyVerdict =
    replyRate === null
      ? 'Ainda não há leads contactados que cheguem para concluir alguma coisa.'
      : replyRate < 0.05
        ? 'Baixa. O problema é a mensagem: teste outra versão do template antes de mudar qualquer outra coisa.'
        : 'Saudável. A mensagem está a funcionar; o gargalo está noutro sítio do funil.';

  const bandVerdict =
    bandSeparation === null
      ? 'Ainda não há conversões suficientes nas duas bandas para comparar.'
      : bandSeparation < 1.5
        ? 'As bandas convertem de forma parecida — o motor de regras não está a discriminar. É aqui, e só aqui, que uma ordenação por IA teria retorno demonstrável.'
        : 'Os leads prioritários convertem melhor do que os de manutenção: as regras estão a discriminar.';

  return (
    <div className="grid">
      <Card hint="Dos leads contactados, quantos responderam." title="Taxa de resposta">
        <p className="metric">{percent(replyRate)}</p>
        <p className="micro">{replyVerdict}</p>
      </Card>

      <Card
        hint="Conversão dos prioritários a dividir pela dos de manutenção."
        title="Separação entre bandas"
      >
        <p className="metric">{ratio(bandSeparation)}</p>
        <p className="micro">{bandVerdict}</p>
      </Card>

      <Card title="Prioritários">
        <p className="metric">
          {funnel.bands.priority.customers} / {funnel.bands.priority.total}
        </p>
        <p className="micro">Clientes sobre leads prioritários.</p>
      </Card>

      <Card title="Manutenção">
        <p className="metric">
          {funnel.bands.nurture.customers} / {funnel.bands.nurture.total}
        </p>
        <p className="micro">Clientes sobre leads de manutenção.</p>
      </Card>
    </div>
  );
}

/* -------------------------------------------------------------------- page */

async function FunnelPanels() {
  const result = await load(fetchFunnel);

  if (result.error !== null || result.data === null) {
    return <ErrorState message={result.error ?? 'Funil indisponível.'} />;
  }

  return (
    <>
      <Panel title="Etapas">
        <Stages funnel={result.data} />
      </Panel>

      <Panel title="O que isto diz">
        <Signals funnel={result.data} />
      </Panel>

      <Panel title="Modelos de mensagem">
        <Templates funnel={result.data} />
      </Panel>

      <Panel title="Saídas">
        <Exits funnel={result.data} />
      </Panel>
    </>
  );
}

export default function FunnelPage() {
  return (
    <>
      <PageHeader
        action={<Link href={PROSPECTING}>Voltar à prospeção</Link>}
        subtitle="Cada etapa conta os leads que chegaram a ela ou passaram dela — não os que estão parados nela agora."
        title="Funil de prospeção"
      />

      <Suspense fallback={<MetricsSkeleton count={4} label="A carregar o funil…" />}>
        <FunnelPanels />
      </Suspense>
    </>
  );
}
