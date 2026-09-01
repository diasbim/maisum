import { cache } from 'react';

import { fetchMerchantDetail } from '@/lib/admin-api';

/**
 * The merchant detail, fetched once per request.
 *
 * The layout needs the name for the heading and the tabs, and every tab page
 * needs the record itself. `cache` collapses those into a single call for the
 * duration of one render; without it a page load would hit the API twice for
 * the same row.
 */
export const getMerchant = cache(fetchMerchantDetail);
