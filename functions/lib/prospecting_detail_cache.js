"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.DetailCache = exports.DEFAULT_CACHE_TTL_DAYS = exports.EMPTY_CACHE = void 0;
exports.EMPTY_CACHE = { byPlaceId: {}, phoneToPlaceId: {} };
exports.DEFAULT_CACHE_TTL_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;
class DetailCache {
    constructor(data = exports.EMPTY_CACHE, options = {}) {
        /** Calls this cache spared, counted so the report can state the saving. */
        this.hits = 0;
        this.data = {
            byPlaceId: { ...data.byPlaceId },
            phoneToPlaceId: { ...data.phoneToPlaceId },
        };
        this.ttlMs = (options.ttlDays ?? exports.DEFAULT_CACHE_TTL_DAYS) * DAY_MS;
        this.now = options.now ?? (() => Date.now());
    }
    /**
     * What was stored for this place, if it is still fresh.
     *
     * An expired entry answers null rather than being deleted. Deleting on read
     * would make a read mutate, and a stale entry is harmless until something
     * asks for it.
     */
    get(placeId) {
        if (placeId === null)
            return null;
        const entry = this.data.byPlaceId[placeId];
        if (entry === undefined)
            return null;
        if (this.now() - entry.fetchedAt > this.ttlMs)
            return null;
        this.hits++;
        return entry.detail;
    }
    /** Records a detail, and the phone that leads back to it. */
    put(placeId, detail, phone) {
        if (placeId === null)
            return;
        this.data.byPlaceId[placeId] = { fetchedAt: this.now(), detail };
        if (phone !== null && phone !== '')
            this.data.phoneToPlaceId[phone] = placeId;
    }
    /** The place a number is already known to belong to, if any. */
    placeForPhone(phone) {
        if (phone === null)
            return null;
        return this.data.phoneToPlaceId[phone] ?? null;
    }
    /** What to persist. A copy, so a caller cannot mutate the cache by holding it. */
    snapshot() {
        return {
            byPlaceId: { ...this.data.byPlaceId },
            phoneToPlaceId: { ...this.data.phoneToPlaceId },
        };
    }
}
exports.DetailCache = DetailCache;
