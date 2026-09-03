/**
 * The list envelope, separated from the fetch that carries it.
 *
 * `merchant-api.ts` imports `server-only`, so nothing in it can be run by
 * `node --test`. The two things worth checking — what a filtered URL looks
 * like, and what a screen is told when the envelope is incomplete — live here
 * instead, free of the framework.
 */

/** What a list screen needs: the rows, and whether they are all of them. */
export type MerchantList<T> = {
  items: T[];
  hasMore: boolean;
  total: number;
  /** The read hit its cap, so `total` undercounts. Screens say so. */
  truncated: boolean;
};

export type ListQuery = {
  search?: string;
  status?: string;
  limit?: number;
  offset?: number;
};

export type ListEnvelope<T> = {
  data?: T[];
  paging?: { limit?: number; offset?: number; has_more?: boolean };
  total?: number;
  truncated?: boolean;
};

export const MERCHANT_PAGE_SIZE = 25;

/**
 * The query string for a filtered page.
 *
 * Empty filters are left out rather than sent as blanks: `?search=` and no
 * search at all mean the same thing to the API, and only one of them makes a
 * URL worth pasting into a message.
 */
export function buildListQuery(params: ListQuery): string {
  const search = new URLSearchParams();
  if (params.search?.trim()) search.set('search', params.search.trim());
  if (params.status?.trim()) search.set('status', params.status.trim());
  search.set('limit', String(params.limit ?? MERCHANT_PAGE_SIZE));
  if (params.offset) search.set('offset', String(params.offset));
  return `?${search.toString()}`;
}

/**
 * The envelope as a screen sees it.
 *
 * Every field is defaulted, because a partial envelope must not become an
 * exception on a page that has already started streaming: a missing `has_more`
 * shows one page instead of breaking the table, and a missing `total` falls
 * back to what actually arrived rather than to zero, which would print
 * "Nenhum cliente" above a full list.
 */
export function toMerchantList<T>(body: ListEnvelope<T>): MerchantList<T> {
  const items = body.data ?? [];
  return {
    items,
    hasMore: body.paging?.has_more ?? false,
    total: body.total ?? items.length,
    truncated: body.truncated ?? false,
  };
}
