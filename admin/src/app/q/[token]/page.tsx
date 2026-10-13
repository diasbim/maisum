import type { Metadata } from 'next';

import { fetchPublicSurvey } from '@/lib/public-survey';
import { SurveyForm } from './SurveyForm';

export const dynamic = 'force-dynamic';

/**
 * A survey, answered by a customer who is not signed in.
 *
 * The one public page in the portal. It is reached from a link the merchant
 * sends over WhatsApp or shows in the shop — "enviados ou preenchidos no
 * local" is the same page either way, and the only difference is whether the
 * token names a customer.
 *
 * `noindex` is inherited from next.config.ts, which is right: these links are
 * shared directly, and a survey turning up in a search result would be a leak
 * of which businesses use the product.
 */
export const metadata: Metadata = {
  title: 'Questionário | MaisUm',
  robots: { index: false, follow: false },
};

function Gone({ message }: { message: string }) {
  return (
    <main className="q-page">
      <div className="q-card q-card--quiet">
        <h1>Este link já não funciona</h1>
        <p>{message}</p>
      </div>
    </main>
  );
}

export default async function SurveyPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const result = await fetchPublicSurvey(token);

  if (!result.ok) {
    return (
      <Gone
        message={
          result.failure.kind === 'unreachable'
            ? 'Não conseguimos abrir o questionário agora. Tente daqui a pouco.'
            : 'O questionário pode ter fechado, ou o link pode ter expirado. Peça um novo ao negócio.'
        }
      />
    );
  }

  const { survey, business_name: businessName, questions, named } = result.value;

  if (questions.length === 0) {
    return <Gone message="Este questionário ainda não tem perguntas." />;
  }

  return (
    <main className="q-page">
      <div className="q-card">
        <header className="q-head">
          {businessName ? <p className="q-from">{businessName}</p> : null}
          <h1>{survey.title}</h1>
          {survey.description ? <p className="q-dek">{survey.description}</p> : null}
          <p className="q-privacy">
            {named
              ? 'A sua resposta fica ligada à sua conta neste negócio.'
              : 'A sua resposta é anónima.'}
          </p>
        </header>
        <SurveyForm token={token} questions={questions} />
      </div>
      <p className="q-foot">MaisUm</p>
    </main>
  );
}
