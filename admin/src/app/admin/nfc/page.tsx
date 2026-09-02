import Link from 'next/link';

import { fetchNfcCards } from '@/lib/admin-api';
import {
  Badge,
  Card,
  ClearFilters,
  EmptyState,
  ErrorState,
  formatDateTime,
  load,
  PageHeader,
  Panel,
  parseSearch,
} from '../ui';

export const metadata = { title: 'Cartões NFC | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * The NFC card registry.
 *
 * Looked up one at a time, never listed in bulk — the same reasoning as the
 * customer lookup. A single UID is not secret, but a browsable list of every
 * card in circulation is a different thing from checking one, and the API only
 * ever returns the last four characters.
 */
export default async function NfcPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const cardUid = parseSearch(params.card_uid);
  const canonicalCustomerId = parseSearch(params.canonical_customer_id);
  const searched = Boolean(cardUid || canonicalCustomerId);

  const result = searched
    ? await load(() =>
        fetchNfcCards({
          cardUid: cardUid || undefined,
          canonicalCustomerId: canonicalCustomerId || undefined,
        }),
      )
    : null;

  return (
    <>
      <PageHeader
        title="Cartões NFC"
        subtitle="Consultar um cartão, ou os cartões de um cliente."
      />

      <Card
        title="Procurar"
        hint="Por identificador do cartão, ou pelo identificador canónico do cliente."
      >
        <form method="get" action="/admin/nfc">
          <div className="form-grid">
            <div className="field">
              <label htmlFor="card_uid">Identificador do cartão</label>
              <input
                className="input"
                id="card_uid"
                name="card_uid"
                placeholder="04A224B2C15E80"
                defaultValue={cardUid}
                autoComplete="off"
              />
              <p className="field__hint">8, 14 ou 20 caracteres hexadecimais.</p>
            </div>
            <div className="field">
              <label htmlFor="canonical_customer_id">Cliente</label>
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
              <Link className="btn btn-outline" href="/admin/nfc">
                Limpar
              </Link>
            ) : null}
          </div>
        </form>
      </Card>

      {result === null ? (
        <Panel>
          <div className="info-box">
            Para chegar a um cliente a partir do telefone, use{' '}
            <Link href="/admin/customers">Clientes</Link>. Para associar cartões
            em lote, use <Link href="/admin/operations">Operações</Link>.
          </div>
        </Panel>
      ) : result.error !== null ? (
        <Panel>
          <ErrorState message={result.error} />
        </Panel>
      ) : result.data.length === 0 ? (
        <Panel>
          <EmptyState
            action={<ClearFilters href="/admin/nfc" label="Limpar procura" />}
            message="Nenhum cartão corresponde a esta procura."
          />
        </Panel>
      ) : (
        <Panel title={`${result.data.length} cartão(ões)`}>
          <div className="card card--flush scroll-x">
            <table>
              <thead>
                <tr>
                  <th scope="col">Cartão</th>
                  <th scope="col">Estado</th>
                  <th scope="col">Cliente</th>
                  <th scope="col">Origem</th>
                  <th scope="col">Associado por</th>
                  <th scope="col">Atualizado</th>
                </tr>
              </thead>
              <tbody>
                {result.data.map((card) => (
                  <tr key={card.card_uid_last4 + String(card.created_at)}>
                    <td>
                      <code className="inline">••••{card.card_uid_last4}</code>
                    </td>
                    <td>
                      <Badge label={card.status} />
                    </td>
                    <td>
                      {card.canonical_customer_id ? (
                        <Link
                          href={`/admin/customers?canonical_customer_id=${encodeURIComponent(card.canonical_customer_id)}`}
                        >
                          ver cliente
                        </Link>
                      ) : (
                        <span className="muted">sem cliente</span>
                      )}
                    </td>
                    <td>{card.source ?? '—'}</td>
                    <td>
                      {card.linked_by ?? '—'}
                      {card.linked_by_merchant_id ? (
                        <div className="micro">
                          {card.linked_by_merchant_id}
                        </div>
                      ) : null}
                    </td>
                    <td>{formatDateTime(card.updated_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Panel>
      )}
    </>
  );
}
