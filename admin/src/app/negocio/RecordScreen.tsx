import { Suspense, type ReactNode } from 'react';

import { MERCHANT_PAGE_SIZE, type ListQuery, type MerchantList } from '@/lib/merchant-api';
import {
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  Panel,
  TableSkeleton,
  load,
  parseOffset,
  parseSearch,
} from '../admin/ui';
import { ResultCount, SearchForm, TruncationNotice } from './records';

/**
 * One list screen, since the business area now has eleven of them.
 *
 * The first four were written out by hand, and that was right while there were
 * four: each could say exactly what it meant. Seven more of the same shape
 * would have been seven more copies of the same Suspense boundary, the same
 * empty state, the same paging — and the differences between them, which are
 * the only interesting part, would have been buried in the repetition.
 *
 * So the repeated parts live here and each screen supplies only what makes it
 * itself: its columns, its filters, and how to fetch a page. The hand-written
 * screens are left alone; converting them would be churn on code that works,
 * and this earns its place on the new ones.
 */

export type Column<T> = {
  header: string;
  /** Right-aligned, for money and counts. */
  numeric?: boolean;
  cell: (row: T) => ReactNode;
};

export type RecordScreenProps<T> = {
  title: string;
  subtitle: string;
  basePath: string;
  searchLabel: string;
  searchPlaceholder: string;
  /** Omitted entirely on screens with nothing worth searching. */
  searchable?: boolean;
  filters?: Array<{ value: string; label: string }>;
  columns: Array<Column<T>>;
  rowKey: (row: T) => string;
  fetchPage: (query: ListQuery) => Promise<MerchantList<T>>;
  singular: string;
  plural: string;
  /** When there is nothing at all — usually because the app has not sent any. */
  emptyMessage: string;
  /** When a filter or a search excluded everything. */
  filteredEmptyMessage?: string;
  /** Rendered above the table, for totals and the like. */
  summary?: ReactNode;
  /** Rendered under the table, for the "this page only reads" note. */
  footnote?: string;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

async function RecordTable<T>({
  search,
  status,
  offset,
  ...props
}: RecordScreenProps<T> & { search: string; status: string; offset: number }) {
  const result = await load(() =>
    props.fetchPage({
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
            <ClearFilters href={props.basePath} label="Limpar filtros" />
          ) : undefined
        }
        message={
          filtered
            ? (props.filteredEmptyMessage ?? 'Nada corresponde a esta procura.')
            : props.emptyMessage
        }
      />
    );
  }

  return (
    <>
      <TruncationNotice truncated={page.truncated} />
      <ResultCount
        total={page.total}
        singular={props.singular}
        plural={props.plural}
      />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              {props.columns.map((column) => (
                <th
                  key={column.header}
                  scope="col"
                  style={column.numeric ? { textAlign: 'right' } : undefined}
                >
                  {column.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {page.items.map((row) => (
              <tr key={props.rowKey(row)}>
                {props.columns.map((column) => (
                  <td
                    key={column.header}
                    style={column.numeric ? { textAlign: 'right' } : undefined}
                  >
                    {column.cell(row)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={props.basePath}
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.hasMore}
        returned={page.items.length}
      />
    </>
  );
}

export async function RecordScreen<T>(props: RecordScreenProps<T>) {
  const params = await props.searchParams;
  const search = parseSearch(params.search);
  const status = parseSearch(params.status).toUpperCase();
  const offset = parseOffset(params.offset);
  const searchable = props.searchable !== false;

  return (
    <>
      <PageHeader title={props.title} subtitle={props.subtitle} />

      {searchable || props.filters ? (
        <Panel>
          {searchable ? (
            <SearchForm
              action={props.basePath}
              label={props.searchLabel}
              placeholder={props.searchPlaceholder}
              value={search}
              keep={{ status: status || undefined }}
            />
          ) : null}
          {props.filters ? (
            <ChipFilter
              basePath={props.basePath}
              param="status"
              current={status}
              options={props.filters}
              keep={{ search: search || undefined }}
            />
          ) : null}
        </Panel>
      ) : null}

      {props.summary}

      <Panel>
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={5} />}
        >
          <RecordTable
            {...props}
            search={search}
            status={status}
            offset={offset}
          />
        </Suspense>
      </Panel>

      {props.footnote ? <p className="micro">{props.footnote}</p> : null}
    </>
  );
}
