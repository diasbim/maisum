import { Suspense } from 'react';

import {
  fetchMyCatalog,
  MERCHANT_PAGE_SIZE,
  type MerchantCatalogItem,
} from '@/lib/merchant-api';
import {
  Badge,
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  Panel,
  TableSkeleton,
  formatAmount,
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../../admin/ui';
import { ResultCount, SearchForm, TruncationNotice } from '../records';

export const metadata = { title: 'Catálogo | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Tudo' },
  { value: 'SERVICE', label: 'Serviços' },
  { value: 'PRODUCT', label: 'Produtos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'INACTIVE', label: 'Inativos' },
];

/** The app's two types, named the way the app names them on the till. */
function typeLabel(item: MerchantCatalogItem): string {
  switch ((item.type ?? '').toUpperCase()) {
    case 'PRODUCT':
      return 'Produto';
    case 'SERVICE':
      return 'Serviço';
    default:
      return '—';
  }
}

async function CatalogTable({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchMyCatalog({
      search: search || undefined,
      status: status || undefined,
      limit: MERCHANT_PAGE_SIZE,
      offset,
    }),
  );
  if (result.error !== null) return <ErrorState message={result.error} />;

  const page = result.data;
  const filtered = search !== '' || status !== '';

  if (page.items.length === 0) {
    return (
      <EmptyState
        action={
          filtered ? (
            <ClearFilters href="/negocio/catalogo" label="Limpar filtros" />
          ) : undefined
        }
        message={
          filtered
            ? 'Nenhum item corresponde a esta procura.'
            : 'O catálogo está vazio. Os serviços e produtos que criar na aplicação aparecem aqui.'
        }
      />
    );
  }

  return (
    <>
      <TruncationNotice truncated={page.truncated} />
      <ResultCount total={page.total} singular="item" plural="itens" />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Item</th>
              <th scope="col">Tipo</th>
              <th className="num" scope="col">
                Preço
              </th>
              <th scope="col">Estado</th>
              <th scope="col">Atualizado</th>
            </tr>
          </thead>
          <tbody>
            {page.items.map((item) => (
              <tr key={item.id}>
                <td>{item.name ?? item.id}</td>
                <td>{typeLabel(item)}</td>
                <td className="num">
                  {item.default_price === null
                    ? 'Sem preço fixo'
                    : formatAmount(item.default_price, 'MZN')}
                </td>
                <td>
                  {/* `null` means the document predates the flag, which the
                      app treats as active — so it is not printed as inactive. */}
                  <Badge
                    label={item.is_active === false ? 'Inativo' : 'Ativo'}
                    tone={item.is_active === false ? 'INACTIVE' : 'ACTIVE'}
                  />
                </td>
                <td>{formatDateTime(item.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath="/negocio/catalogo"
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.hasMore}
        returned={page.items.length}
      />
    </>
  );
}

export default async function MerchantCatalogPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const search = parseSearch(params.search);
  const status = parseSearch(params.status).toUpperCase();
  const offset = parseOffset(params.offset);

  return (
    <>
      <PageHeader
        title="Catálogo"
        subtitle="O que o seu negócio vende, na ordem em que aparece na aplicação."
      />

      <Panel>
        <SearchForm
          action="/negocio/catalogo"
          label="Procurar no catálogo"
          placeholder="Nome do serviço ou produto"
          value={search}
          keep={{ status: status || undefined }}
        />
        <ChipFilter
          basePath="/negocio/catalogo"
          param="status"
          current={status}
          options={FILTERS}
          keep={{ search: search || undefined }}
        />
      </Panel>

      <Panel>
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={6} />}
        >
          <CatalogTable search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>
    </>
  );
}
