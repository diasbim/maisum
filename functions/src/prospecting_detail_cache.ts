/**
 * Details already paid for, so they are never paid for twice.
 *
 * A listing detail costs money every time it is fetched, and nothing about a
 * barbershop's phone number changes between two runs an hour apart. Without a
 * cache, re-running a campaign to check a change in the scoring re-buys every
 * lead in it — which makes the safe act of verifying your own work the
 * expensive one.
 *
 * Keyed by place id, because that is the only stable identifier: the name is
 * the thing that varies, and it is what caused the duplicates this module
 * exists alongside. Google permits the place id to be stored indefinitely;
 * the fields beside it carry a TTL, because a phone number does go stale.
 *
 * The store is injected rather than assumed. The harness passes a JSON file,
 * the pipeline can pass Firestore, and the tests pass a plain object — one
 * behaviour, three homes, and no second source of truth invented for testing.
 */

export type CachedDetail = {
  fetchedAt: number;
  detail: unknown;
};

export type DetailCacheData = {
  byPlaceId: Record<string, CachedDetail>;
  /**
   * Phone number to the place it belongs to.
   *
   * A chain that lists each branch under its own name and one central number
   * is invisible to a name-based comparison, and only shows itself once a
   * detail call has been made. Recording the number means the *next* run
   * recognises the chain before paying, rather than discovering it again.
   */
  phoneToPlaceId: Record<string, string>;
};

export const EMPTY_CACHE: DetailCacheData = { byPlaceId: {}, phoneToPlaceId: {} };

export const DEFAULT_CACHE_TTL_DAYS = 30;

const DAY_MS = 24 * 60 * 60 * 1000;

export type DetailCacheOptions = {
  ttlDays?: number;
  /** Injected so the TTL can be tested without waiting a month. */
  now?: () => number;
};

export class DetailCache {
  private readonly data: DetailCacheData;
  private readonly ttlMs: number;
  private readonly now: () => number;

  /** Calls this cache spared, counted so the report can state the saving. */
  hits = 0;

  constructor(data: DetailCacheData = EMPTY_CACHE, options: DetailCacheOptions = {}) {
    this.data = {
      byPlaceId: { ...data.byPlaceId },
      phoneToPlaceId: { ...data.phoneToPlaceId },
    };
    this.ttlMs = (options.ttlDays ?? DEFAULT_CACHE_TTL_DAYS) * DAY_MS;
    this.now = options.now ?? (() => Date.now());
  }

  /**
   * What was stored for this place, if it is still fresh.
   *
   * An expired entry answers null rather than being deleted. Deleting on read
   * would make a read mutate, and a stale entry is harmless until something
   * asks for it.
   */
  get(placeId: string | null): unknown | null {
    if (placeId === null) return null;
    const entry = this.data.byPlaceId[placeId];
    if (entry === undefined) return null;
    if (this.now() - entry.fetchedAt > this.ttlMs) return null;
    this.hits++;
    return entry.detail;
  }

  /** Records a detail, and the phone that leads back to it. */
  put(placeId: string | null, detail: unknown, phone: string | null): void {
    if (placeId === null) return;
    this.data.byPlaceId[placeId] = { fetchedAt: this.now(), detail };
    if (phone !== null && phone !== '') this.data.phoneToPlaceId[phone] = placeId;
  }

  /** The place a number is already known to belong to, if any. */
  placeForPhone(phone: string | null): string | null {
    if (phone === null) return null;
    return this.data.phoneToPlaceId[phone] ?? null;
  }

  /** What to persist. A copy, so a caller cannot mutate the cache by holding it. */
  snapshot(): DetailCacheData {
    return {
      byPlaceId: { ...this.data.byPlaceId },
      phoneToPlaceId: { ...this.data.phoneToPlaceId },
    };
  }
}
