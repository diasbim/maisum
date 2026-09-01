import Link from 'next/link';

import { lookupCustomer } from '@/lib/admin-api';
import {
  Card,
  DefinitionList,
  EmptyState,
  PageHeader,
  Panel,
  formatDateTime,
  load,
  parseSearch,
} from '../ui';

export const metadata = { title: 'Clientes | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * Customer support lookup.
 *
 * A lookup, not a directory. The canonical customer id is an HMAC of the phone
 * number, so a phone resolves to exactly one record with no scan — and there is
 * no query that lists customers by name. That is deliberate and worth keeping:
 * a console that cannot enumerate the customer base cannot leak it either.
 *
 * A plain GET form, so a result is a linkable URL that can be pasted into a
 * support thread.
 */
export default async function CustomersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const phone = parseSearch(params.phone);
  const cardUid = parseSearch(params.card_uid);
  const canonicalCustomerId = parseSearch(params.canonical_customer_id);
  const searched = Boolean(phone || cardUid || canonicalCustomerId);

  const result = searched
    ? await load(() =>
        lookupCustomer({
          phone: phone || undefined,
          cardUid: cardUid || undefined,
          canonicalCustomerId: canonicalCustomerId || undefined,
        }),
      )
    : null;

  return (
    <>
      <PageHeader
        title="Clientes"
        subtitle="Encontrar um cliente por telefone, cartão ou identificador."
      />

      <Card
        title="Procurar"
        hint="Preencha um dos campos. Não existe listagem de clientes — só é possível chegar a um de cada vez."
      >
        <form method="get" action="/admin/customers">
          <div className="form-grid">
            <div className="field">
              <label htmlFor="phone">Telefone</label>
              <input
                className="input"
                id="phone"
                name="phone"
                type="tel"
                placeholder="+258 84 000 0000"
                defaultValue={phone}
                autoComplete="off"
              />
              <p className="field__hint">Aceita formato local ou +258.</p>
            </div>
            <div className="field">
              <label htmlFor="card_uid">Cartão NFC</label>
              <input
                className="input"
                id="card_uid"
                name="card_uid"
                placeholder="04A224B2C15E80"
                defaultValue={cardUid}
                autoComplete="off"
              />
            </div>
            <div className="field">
              <label htmlFor="canonical_customer_id">Identificador</label>
              <input
                className="input"
                id="canonical_customer_id"
                name="canonical_customer_id"
                placeholder="id canónico"
                defaultValue={canonicalCustomerId}
                autoComplete="off"
              />
            </div>
          </div>
          <div className="form-actions">
            <button className="btn btn-navy" type="submit">
              Procurar
            </button>
            {searched ? (
              <Link className="btn btn-outline" href="/admin/customers">
                Limpar
              </Link>
            ) : null}
          </div>
        </form>
      </Card>

      {result === null ? null : result.error !== null ? (
        <Panel>
          <p className="error">{result.error}</p>
        </Panel>
      ) : result.data === null ? (
        <Panel>
          <EmptyState message="Nenhum cliente corresponde a esta procura." />
        </Panel>
      ) : (
        <>
          <Panel title="Cliente">
            <div className="split">
              <Card title="Identidade">
                <DefinitionList
                  entries={[
                    ['Telefone', `••• ${result.data.phone_last4 ?? '????'}`],
                    ['Estado da conta', result.data.account_state],
                    [
                      'Conta associada',
                      result.data.account_linked ? 'Sim' : 'Não',
                    ],
                    ['Criado', formatDateTime(result.data.created_at)],
                    ['Atualizado', formatDateTime(result.data.updated_at)],
                  ]}
                />
                <p className="micro" style={{ marginTop: 12 }}>
                  <code className="inline">
                    {result.data.canonical_customer_id}
                  </code>
                </p>
              </Card>

              <Card
                title={`Cartões (${result.data.cards.length})`}
                hint="Só os últimos quatro caracteres do identificador do cartão."
              >
                {result.data.cards.length === 0 ? (
                  <p className="muted">Sem cartões associados.</p>
                ) : (
                  <ul style={{ margin: 0, paddingLeft: 18, fontSize: '0.85rem' }}>
                    {result.data.cards.map((card) => (
                      <li key={card.card_uid_last4 + card.created_at}>
                        ••••{card.card_uid_last4} · {card.status}
                        {card.linked_by_merchant_id
                          ? ` · ${card.linked_by_merchant_id}`
                          : ''}
                      </li>
                    ))}
                  </ul>
                )}
              </Card>
            </div>
          </Panel>

          <Panel title={`Negócios (${result.data.businesses.length})`}>
            {result.data.businesses.length === 0 ? (
              <EmptyState message="Este cliente não está ligado a nenhum negócio." />
            ) : (
              <div className="card card--flush scroll-x">
                <table>
                  <thead>
                    <tr>
                      <th>Negócio</th>
                      <th>Id no negócio</th>
                      <th>Ligado em</th>
                      <th>Pontos</th>
                    </tr>
                  </thead>
                  <tbody>
                    {result.data.businesses.map((business) => (
                      <tr key={business.merchant_id}>
                        <td>
                          <Link
                            href={`/admin/merchants/${encodeURIComponent(business.merchant_id)}`}
                          >
                            {business.merchant_id}
                          </Link>
                        </td>
                        <td>
                          <code className="inline">
                            {business.business_customer_id || '—'}
                          </code>
                        </td>
                        <td>{formatDateTime(business.linked_at)}</td>
                        <td>
                          <Link
                            className="btn btn-outline btn-sm"
                            href={
                              `/admin/customers/${encodeURIComponent(result.data!.canonical_customer_id)}` +
                              `?merchant_id=${encodeURIComponent(business.merchant_id)}` +
                              `&customer_id=${encodeURIComponent(business.business_customer_id)}`
                            }
                          >
                            Ver livro de pontos
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Panel>
        </>
      )}
    </>
  );
}
